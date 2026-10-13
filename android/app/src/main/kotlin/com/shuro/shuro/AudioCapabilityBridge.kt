package com.shuro.shuro

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Native half of Shuro's audio-capability bridge (playback plan §5.1, Phase 3).
 *
 * It reports what the platform will say about the **output path**, and nothing
 * more. Three rules from the plan are enforced here rather than in the UI:
 *
 *  1. **Every API is version-guarded.** `getDirectPlaybackSupport` is API 33+,
 *     `registerAudioDeviceCallback` is 23+, and `getDevices` is 23+. Where the
 *     OS cannot answer, this returns `unknown` — it never guesses, and it never
 *     blocks playback (rule 4).
 *  2. **Capability is a signal, not a guarantee.** The platform result describes
 *     what the framework would do for a given format/attribute pair. This
 *     bridge therefore reports `supported` / `unsupported` / `unknown` and never
 *     "bit-perfect" (§5.1 rule 5, §10).
 *  3. **Route changes invalidate.** An [AudioDeviceCallback] is registered while
 *     monitoring, and it pushes `routeChanged` back to Dart so the cached answer
 *     is dropped instead of being trusted after a headset or DAC is plugged in
 *     (§5.1 rule 2).
 *
 * ## Channel contract
 *
 * Channel `shuro/audio_capability`:
 *
 *  * `getCapability(usage, contentType, sampleRateHz?, channelCount?,
 *    pcmEncoding?)` → map with
 *    `routeKind` (`builtIn`/`wired`/`bluetooth`/`usb`/`other`/`unknown`),
 *    `routeLabel` (String?), `directPlayback`
 *    (`supported`/`unsupported`/`unknown`), `directPlaybackReason` (String?),
 *    `highResolutionPcmAccepted` (Boolean?, null = never requested),
 *    `bitPerfectUsbAccepted` (Boolean?, null = never requested),
 *    `apiLevel` (Int), `source` (String).
 *  * `startMonitoring()` / `stopMonitoring()` → register/unregister the device
 *    callback.
 *  * callback `routeChanged` → fired on the main thread when output devices are
 *    added or removed.
 *
 * ## What this deliberately does not do
 *
 * It does not request audio focus, does not inspect the decoder, and does not
 * attempt Media3's high-resolution PCM configuration (Phase 4) or USB
 * `AudioMixerAttributes` bit-perfect mode (Phase 5). Those are separate
 * milestones, and §5.1 is explicit that a capability answer must not be turned
 * into a playback guarantee.
 */
class AudioCapabilityBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    companion object {
        const val CHANNEL = "shuro/audio_capability"
        private const val METHOD_GET_CAPABILITY = "getCapability"
        private const val METHOD_START_MONITORING = "startMonitoring"
        private const val METHOD_STOP_MONITORING = "stopMonitoring"
        private const val CALLBACK_ROUTE_CHANGED = "routeChanged"

        private const val PCM_16 = "pcm16"
        private const val PCM_24 = "pcm24"
        private const val PCM_FLOAT = "pcm32float"
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val handler = Handler(Looper.getMainLooper())
    private var deviceCallback: AudioDeviceCallback? = null

    private val audioManager: AudioManager?
        get() = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

    fun attach() {
        channel.setMethodCallHandler { call, result -> onMethodCall(call, result) }
    }

    fun detach() {
        stopMonitoring()
        channel.setMethodCallHandler(null)
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_GET_CAPABILITY -> result.success(
                readCapability(
                    sampleRateHz = call.argument<Int>("sampleRateHz"),
                    channelCount = call.argument<Int>("channelCount"),
                    pcmEncoding = call.argument<String>("pcmEncoding"),
                ),
            )
            METHOD_START_MONITORING -> {
                startMonitoring()
                result.success(null)
            }
            METHOD_STOP_MONITORING -> {
                stopMonitoring()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // --- capability -----------------------------------------------------------------

    private fun readCapability(
        sampleRateHz: Int?,
        channelCount: Int?,
        pcmEncoding: String?,
    ): Map<String, Any?> {
        val manager = audioManager
            ?: return unknownCapability("No AudioManager on this device.")

        val route = readRoute(manager)
        val direct = readDirectPlayback(sampleRateHz, channelCount, pcmEncoding)

        return mapOf(
            "routeKind" to route.kind,
            "routeLabel" to route.label,
            "directPlayback" to direct.state,
            "directPlaybackMode" to direct.mode,
            "directPlaybackReason" to direct.reason,
            // Nothing in this app requests either configuration yet, so the honest
            // answer is null ("not asked") rather than false ("asked and refused").
            // Phase 4/5 fill these in when those paths are actually attempted.
            "highResolutionPcmAccepted" to null,
            "bitPerfectUsbAccepted" to null,
            "apiLevel" to Build.VERSION.SDK_INT,
            "source" to "Android AudioManager",
        )
    }

    private fun unknownCapability(reason: String): Map<String, Any?> = mapOf(
        "routeKind" to "unknown",
        "routeLabel" to null,
        "directPlayback" to "unknown",
        "directPlaybackMode" to "unknown",
        "directPlaybackReason" to reason,
        "highResolutionPcmAccepted" to null,
        "bitPerfectUsbAccepted" to null,
        "apiLevel" to Build.VERSION.SDK_INT,
        "source" to "Android AudioManager",
    )

    private data class Route(val kind: String, val label: String?)

    /**
     * Best-effort classification of the current output route.
     *
     * Android has no "what is the active sink right now" query, so this picks the
     * most specific *present* output device in priority order. It is a reasonable
     * indicator and is labelled as such in the UI — the plan forbids presenting
     * it as verified routing.
     */
    private fun readRoute(manager: AudioManager): Route {
        val devices = try {
            manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        } catch (_: Exception) {
            return Route("unknown", null)
        }
        if (devices.isEmpty()) return Route("unknown", null)

        fun firstOf(vararg types: Int): AudioDeviceInfo? =
            devices.firstOrNull { device -> types.any { it == device.type } }

        firstOf(
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_USB_ACCESSORY,
        )?.let { return Route("usb", it.productName?.toString()?.takeIf { name -> name.isNotBlank() }) }

        firstOf(
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_SPEAKER,
        )?.let { return Route("bluetooth", it.productName?.toString()?.takeIf { name -> name.isNotBlank() }) }

        firstOf(
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_LINE_ANALOG,
        )?.let { return Route("wired", it.productName?.toString()?.takeIf { name -> name.isNotBlank() }) }

        firstOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER, AudioDeviceInfo.TYPE_BUILTIN_EARPIECE)
            ?.let { return Route("builtIn", null) }

        firstOf(AudioDeviceInfo.TYPE_HDMI, AudioDeviceInfo.TYPE_HDMI_ARC, AudioDeviceInfo.TYPE_HDMI_EARC)
            ?.let { return Route("other", "HDMI") }

        return Route("other", devices.firstOrNull()?.productName?.toString())
    }

    private data class DirectPlayback(val state: String, val mode: String, val reason: String?)

    /**
     * `AudioManager.getDirectPlaybackSupport` (API 33+) for the format the app
     * would actually use. It is a **static** method — hence the class-qualified
     * call in [queryDirectPlayback] rather than an instance call.
     *
     * The return value distinguishes *how* the platform would play the stream,
     * which matters more than a bare yes/no: offload bypasses the framework's
     * mixing/resampling stage, and bitstream passthrough hands the compressed
     * stream to the output device undecoded. Both are reported as `supported`,
     * with the mode named so the UI can be specific instead of triumphant.
     *
     * Without a format from Dart there is nothing meaningful to ask about, so the
     * answer is `unknown` with a reason — reporting `supported` for a format
     * nobody specified would be exactly the false precision §4.3 exists to prevent.
     */
    private fun readDirectPlayback(
        sampleRateHz: Int?,
        channelCount: Int?,
        pcmEncoding: String?,
    ): DirectPlayback {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return DirectPlayback("unknown", "unknown", "Android ${Build.VERSION.RELEASE} has no direct-playback query (needs API 33+).")
        }
        if (sampleRateHz == null || channelCount == null) {
            return DirectPlayback("unknown", "unknown", "No audio format was supplied to check.")
        }
        return queryDirectPlayback(sampleRateHz, channelCount, pcmEncoding ?: PCM_16)
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun queryDirectPlayback(
        sampleRateHz: Int,
        channelCount: Int,
        pcmEncoding: String,
    ): DirectPlayback {
        val encoding = when (pcmEncoding) {
            PCM_24 -> AudioFormat.ENCODING_PCM_24BIT_PACKED
            PCM_FLOAT -> AudioFormat.ENCODING_PCM_FLOAT
            else -> AudioFormat.ENCODING_PCM_16BIT
        }
        val channelMask = when (channelCount) {
            1 -> AudioFormat.CHANNEL_OUT_MONO
            else -> AudioFormat.CHANNEL_OUT_STEREO
        }

        val format = AudioFormat.Builder()
            .setSampleRate(sampleRateHz)
            .setEncoding(encoding)
            .setChannelMask(channelMask)
            .build()

        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()

        val description = "$sampleRateHz Hz, $channelCount ch, $pcmEncoding"
        return try {
            when (val support = AudioManager.getDirectPlaybackSupport(format, attributes)) {
                AudioManager.DIRECT_PLAYBACK_NOT_SUPPORTED -> DirectPlayback(
                    "unsupported",
                    "none",
                    "$description — the framework would resample or mix this.",
                )
                AudioManager.DIRECT_PLAYBACK_BITSTREAM_SUPPORTED -> DirectPlayback(
                    "supported",
                    "bitstream",
                    "$description — the compressed stream can be passed through undecoded.",
                )
                AudioManager.DIRECT_PLAYBACK_OFFLOAD_SUPPORTED -> DirectPlayback(
                    "supported",
                    "offload",
                    "$description — a direct offload path exists, bypassing the mixer.",
                )
                AudioManager.DIRECT_PLAYBACK_OFFLOAD_GAPLESS_SUPPORTED -> DirectPlayback(
                    "supported",
                    "offloadGapless",
                    "$description — a direct offload path with gapless support exists.",
                )
                else -> DirectPlayback("unknown", "unknown", "The platform returned an unrecognised direct-playback code ($support).")
            }
        } catch (e: Exception) {
            DirectPlayback("unknown", "unknown", "Direct-playback query failed (${e.javaClass.simpleName}).")
        }
    }

    // --- route monitoring ------------------------------------------------------------

    private fun startMonitoring() {
        if (deviceCallback != null) return
        val manager = audioManager ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return

        val callback = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) = notifyRouteChanged()
            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) = notifyRouteChanged()
        }
        try {
            manager.registerAudioDeviceCallback(callback, handler)
            deviceCallback = callback
        } catch (_: Exception) {
            deviceCallback = null
        }
    }

    private fun stopMonitoring() {
        val callback = deviceCallback ?: return
        try {
            audioManager?.unregisterAudioDeviceCallback(callback)
        } catch (_: Exception) {
            // Already gone — nothing to do.
        }
        deviceCallback = null
    }

    private fun notifyRouteChanged() {
        // Called from the main-thread Handler, which is what the channel needs.
        channel.invokeMethod(CALLBACK_ROUTE_CHANGED, null)
    }
}
