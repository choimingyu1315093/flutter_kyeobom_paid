package com.example.flutter_home_camera

import android.content.Context
import android.os.BatteryManager
import android.os.PowerManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.view.Surface
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "home_camera/screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceHealth" -> {
                        val battery = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
                        val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                        val caps = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
                        val networkType = when {
                            caps == null -> "offline"
                            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                            else -> "other"
                        }
                        val thermal = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) power.currentThermalStatus else -1
                        result.success(mapOf(
                            "battery" to battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY),
                            "charging" to battery.isCharging,
                            "thermal" to thermal,
                            "network" to networkType,
                            "platform" to "android"
                        ))
                    }
                    "enableWaitingMode" -> {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        result.success(null)
                    }
                    "disableWaitingMode" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        result.success(null)
                    }
                    "getViewerLandscapeSide" -> {
                        // Use the actual display rotation, not its width/height:
                        // both landscape orientations have identical dimensions.
                        @Suppress("DEPRECATION")
                        val rotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            display?.rotation
                        } else {
                            windowManager.defaultDisplay.rotation
                        }
                        result.success(when (rotation) {
                            Surface.ROTATION_90 -> "left"
                            Surface.ROTATION_270 -> "right"
                            else -> "unknown"
                        })
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
