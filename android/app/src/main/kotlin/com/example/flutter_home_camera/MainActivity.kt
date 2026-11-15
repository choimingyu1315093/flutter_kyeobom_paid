package com.example.flutter_home_camera

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
