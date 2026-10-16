package com.shuro.shuro

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Native half of the device-capability bridge behind Settings → Performance.
 *
 * Reports exactly what the platform knows about the device — RAM class, CPU
 * count, ABI, refresh rate, battery-saver and thermal state — so the profile
 * picker can choose real presets. Every API is version-guarded and returns
 * null where the OS cannot answer; nothing here is guessed.
 *
 * Channel `shuro/device_profile`:
 *  * `getProfile()` → map:
 *    `totalRamMb` (Int), `isLowRamDevice` (Boolean), `memoryClassMb` (Int),
 *    `largeMemoryClassMb` (Int), `cores` (Int), `sdk` (Int),
 *    `abis` (List<String>), `refreshRateHz` (Double?),
 *    `batterySaver` (Boolean?), `thermalStatus` (Int?, API 29+).
 */
class DeviceProfileBridge(context: Context, messenger: BinaryMessenger) {
    private val appContext = context.applicationContext

    private val channel = MethodChannel(messenger, "shuro/device_profile").apply {
        setMethodCallHandler { call, result ->
            when (call.method) {
                "getProfile" -> result.success(readProfile())
                else -> result.notImplemented()
            }
        }
    }

    private fun readProfile(): Map<String, Any?> {
        val am = appContext.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        val pm = appContext.getSystemService(Context.POWER_SERVICE) as PowerManager
        val out = mutableMapOf<String, Any?>(
            "totalRamMb" to (mi.totalMem / (1024 * 1024)).toInt(),
            "isLowRamDevice" to am.isLowRamDevice,
            "memoryClassMb" to am.memoryClass,
            "largeMemoryClassMb" to am.largeMemoryClass,
            "cores" to Runtime.getRuntime().availableProcessors(),
            "sdk" to Build.VERSION.SDK_INT,
            "abis" to Build.SUPPORTED_ABIS.toList(),
            "batterySaver" to pm.isPowerSaveMode,
        )
        val refresh = appContext.display?.refreshRate
        out["refreshRateHz"] = refresh?.toDouble()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            out["thermalStatus"] = pm.currentThermalStatus
        } else {
            out["thermalStatus"] = null
        }
        return out
    }

    fun detach() {
        channel.setMethodCallHandler(null)
    }
}
