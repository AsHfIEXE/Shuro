package com.shuro.shuro

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Host for the Flutter app, plus the native half of the audio-capability bridge
 * (see [AudioCapabilityBridge]).
 *
 * Extends [AudioServiceActivity] rather than `FlutterActivity`, which is what
 * `just_audio_background`/`audio_service` require: that class overrides
 * `provideFlutterEngine` to hand the activity the same engine the background
 * service uses. With a plain `FlutterActivity` the init fails with
 * "The Activity class declared in your AndroidManifest.xml is wrong or has not
 * provided the correct FlutterEngine", which is exactly what happened before
 * this change — and because `JustAudioBackground.init` was awaited before
 * `runApp`, that failure left the app on a blank screen (see main.dart, which now
 * treats it as non-fatal as well, so a wrong manifest can never blank the app
 * again).
 *
 * The bridge is attached per engine and detached in [onDestroy], so the device
 * callback is never left registered against a dead engine.
 */
class MainActivity : AudioServiceActivity() {
    private var capabilityBridge: AudioCapabilityBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        capabilityBridge = AudioCapabilityBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger).also { it.attach() }
    }

    override fun onDestroy() {
        capabilityBridge?.detach()
        capabilityBridge = null
        super.onDestroy()
    }
}
