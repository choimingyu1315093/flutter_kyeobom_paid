package com.mingyu.kyeobom

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import kotlin.math.log10
import kotlin.math.sqrt
import android.os.BatteryManager
import android.os.PowerManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.app.Notification
import android.app.PendingIntent
import java.nio.ByteOrder
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.LocalAudioTrack
import org.webrtc.AudioTrackSink
import android.app.NotificationChannel
import android.app.NotificationManager
import android.view.Surface
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Baby sound mode is explicit opt-in and foreground-only.
    // Collects only decibel readings, never audio buffers on disk/network.
    @Volatile private var babyMonitoring = false
    @Volatile private var babySoundDb = -100.0
    @Volatile private var babyRecorder: AudioRecord? = null
    private val cryLock = Any()
    private var cryCapture = false
    private var cryCount = 0
    private var cryWindow = FloatArray(15600)
    private var cryRate = 16000
    private var rtcTrack: LocalAudioTrack? = null
    private var rtcSink: AudioTrackSink? = null

    private fun readBabyCryWindow(): Map<String, Any>? = synchronized(cryLock) {
        if (!cryCapture || cryCount != cryWindow.size) return@synchronized null
        val pcm = cryWindow.copyOf()
        cryWindow.fill(0f)
        cryCount = 0
        mapOf("pcm" to pcm, "rate" to cryRate)
    }

    private fun disableBabyCryCapture() = synchronized(cryLock) {
        cryCapture = false
        cryCount = 0
        cryWindow.fill(0f)
    }

    private fun startBabyRtcMonitoring(trackId: String): String? {
        if (babyMonitoring || rtcTrack != null) return "기존 마이크 감지를 먼저 중지해야 합니다"
        val track = FlutterWebRTCPlugin.sharedSingleton?.getLocalTrack(trackId) as? LocalAudioTrack
            ?: return "WebRTC 마이크를 찾을 수 없습니다"
        val sink = AudioTrackSink { buffer, bits, rate, channels, frames, _ ->
            if (bits == 16 && rate in 16000..192000 && channels > 0 && frames > 0) {
                val samples = buffer.duplicate().order(ByteOrder.nativeOrder()).asShortBuffer()
                synchronized(cryLock) {
                    if (cryCapture && rtcTrack === track) {
                        if (rate != cryRate) {
                            cryRate = rate
                            cryWindow = FloatArray(kotlin.math.round(rate * 0.975).toInt())
                            cryCount = 0
                        }
                        val count = minOf(frames, samples.remaining() / channels)
                        var power = 0.0
                        for (j in 0 until count) {
                            var value = 0.0
                            for (c in 0 until channels) value += samples.get().toDouble() / 32768.0
                            value /= channels
                            power += value * value
                            if (cryCount < cryWindow.size) cryWindow[cryCount++] = value.toFloat()
                        }
                        if (count > 0) babySoundDb = (20.0 * log10(maxOf(sqrt(power / count), 0.00001))).coerceIn(-100.0, 0.0)
                    }
                }
            }
        }
        synchronized(cryLock) {
            cryRate = 16000
            cryWindow = FloatArray(15600)
            cryCount = 0
            cryCapture = true
            rtcTrack = track
            rtcSink = sink
            babySoundDb = -100.0
        }
        track.addSink(sink)
        return null
    }

    private fun startBabyMonitoring(enableCryQa: Boolean): String? {
        if (babyMonitoring) return null
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED) return "마이크 권한이 필요합니다"
        val rate = 16000
        val channel = AudioFormat.CHANNEL_IN_MONO
        val encoding = AudioFormat.ENCODING_PCM_16BIT
        val minimum = AudioRecord.getMinBufferSize(rate, channel, encoding)
        if (minimum <= 0) return "오디오 입력 버퍼를 만들 수 없습니다"
        val recorder = try {
            AudioRecord(
                MediaRecorder.AudioSource.MIC, rate, channel, encoding,
                maxOf(minimum * 2, 4096)
            )
        } catch (error: Exception) {
            return "기기 마이크 초기화 실패: ${error.javaClass.simpleName}"
        }
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            return "기기 마이크를 사용할 수 없습니다"
        }
        try {
            recorder.startRecording()
        } catch (error: Exception) {
            recorder.release()
            return "마이크 감지 시작 실패: ${error.javaClass.simpleName}"
        }
        babyRecorder = recorder
        babySoundDb = -100.0
        synchronized(cryLock) {
            cryCapture = enableCryQa
            cryRate = 16000
            cryWindow = FloatArray(15600)
            cryCount = 0
            cryWindow.fill(0f)
        }
        babyMonitoring = true
        Thread({
            val samples = ShortArray(1024)
            while (babyMonitoring && babyRecorder === recorder) {
                val count = recorder.read(samples, 0, samples.size)
                if (count <= 0 || !babyMonitoring || babyRecorder !== recorder) break
                synchronized(cryLock) {
                    if (cryCapture && babyRecorder === recorder) {
                        for (i in 0 until count) {
                            if (cryCount == cryWindow.size) break
                            cryWindow[cryCount++] = samples[i] / 32768.0f
                        }
                    }
                }
                var power = 0.0
                for (i in 0 until count) {
                    val sample = samples[i].toDouble()
                    power += sample * sample
                }
                val rms = sqrt(power / count) / 32768.0
                babySoundDb = (20.0 * log10(maxOf(rms, 0.00001)))
                    .coerceIn(-100.0, 0.0)
            }
        }, "KyeobomBabySoundMeter").apply {
            isDaemon = true
            start()
        }
        return null
    }

    private fun stopBabyMonitoring() {
        babyMonitoring = false
        disableBabyCryCapture()
        val track = rtcTrack
        val sink = rtcSink
        rtcTrack = null
        rtcSink = null
        if (track != null && sink != null) track.removeSink(sink)
        val recorder = babyRecorder
        babyRecorder = null
        babySoundDb = -100.0
        if (recorder != null) {
            try {
                if (recorder.recordingState ==
                    AudioRecord.RECORDSTATE_RECORDING) recorder.stop()
            } catch (_: Exception) {}
            try {
                recorder.release()
            } catch (_: Exception) {}
        }
    }

    override fun onStop() {
        stopBabyMonitoring()
        super.onStop()
    }

    override fun onDestroy() {
        stopBabyMonitoring()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Android 8+: background FCM uses this channel. Do not start any
        // camera, microphone or foreground service just for a notification.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notifications = getSystemService(Context.NOTIFICATION_SERVICE)
                as? NotificationManager
            notifications?.createNotificationChannel(NotificationChannel(
                "kyeobom_baby_cry", "아기 울음 알림", NotificationManager.IMPORTANCE_HIGH))
            notifications?.createNotificationChannel(
                NotificationChannel(
                    "kyeobom_health_alerts",
                    "거치폰 배터리·발열 위험",
                    NotificationManager.IMPORTANCE_HIGH
                )
            )
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "home_camera/screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startBabyRtcMonitoring" -> {
                        val id = call.argument<String>("trackId")
                        val failure = if (id == null) "마이크 트랙 없음" else startBabyRtcMonitoring(id)
                        if (failure == null) result.success(null)
                        else result.error("BABY_RTC_UNAVAILABLE", failure, null)
                    }
                    "showBabyCryNotification" -> {
                        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            result.success(null)
                        } else {
                            val launch = packageManager.getLaunchIntentForPackage(packageName)
                            val pending = launch?.let { PendingIntent.getActivity(this, 0, it,
                                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) }
                            val builder = if (Build.VERSION.SDK_INT >= 26)
                                Notification.Builder(this, "kyeobom_baby_cry")
                            else Notification.Builder(this).setPriority(Notification.PRIORITY_HIGH).setDefaults(Notification.DEFAULT_ALL)
                            if (pending != null) builder.setContentIntent(pending)
                            manager.notify(7301, builder.setSmallIcon(android.R.drawable.ic_dialog_info)
                                .setContentTitle("아기 울음소리가 감지됐어요")
                                .setContentText("아기의 상태를 확인해 주세요.")
                                .setAutoCancel(true).build())
                            result.success(null)
                        }
                    }
                    "startBabySoundMonitoring" -> {
                        val failure = startBabyMonitoring(call.argument<Boolean>("cryQa") == true)
                        if (failure == null) result.success(null)
                        else result.error("BABY_SOUND_UNAVAILABLE", failure, null)
                    }
                    "readBabySoundLevel" -> result.success(babySoundDb)
                    "readBabyCryWindow" -> result.success(readBabyCryWindow())
                    "disableBabyCryCapture" -> {
                        disableBabyCryCapture()
                        result.success(null)
                    }
                    "stopBabySoundMonitoring" -> {
                        stopBabyMonitoring()
                        result.success(null)
                    }
                    "getDeviceHealth" -> {
                        try {
                            // Telemetry must not destabilize the home camera.
                            // A device/OS may not expose every optional health API.
                            val battery = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
                            val power = getSystemService(Context.POWER_SERVICE) as? PowerManager
                            val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                            val network = connectivity?.activeNetwork
                            val caps = network?.let { connectivity?.getNetworkCapabilities(it) }
                            val networkType = when {
                                caps == null -> "offline"
                                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                                else -> "other"
                            }
                            val thermal = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                power?.currentThermalStatus ?: -1
                            } else {
                                -1
                            }
                            result.success(mapOf(
                                "battery" to (battery?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1),
                                "charging" to (battery?.isCharging ?: false),
                                "thermal" to thermal,
                                "network" to networkType,
                                "platform" to "android"
                            ))
                        } catch (exception: Exception) {
                            // Native MethodChannel errors are returned to Dart,
                            // where the publisher already catches and ignores
                            // telemetry failures independently from WebRTC.
                            android.util.Log.e("KyeobomHealth", "Health collection failed", exception)
                            result.error("HEALTH_UNAVAILABLE", "Unable to read device health", null)
                        }
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