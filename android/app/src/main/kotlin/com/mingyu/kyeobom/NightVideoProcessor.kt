package com.mingyu.kyeobom

import android.os.SystemClock
import android.util.Log
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import org.webrtc.JavaI420Buffer
import org.webrtc.VideoFrame
import java.nio.ByteBuffer

/** Operates on the existing WebRTC source BEFORE encoding. Original frames
 * are returned verbatim in normal light or on unsupported/slow devices.
 * No torch, file IO, new camera, added track, or frame queue.
 */
internal class NightVideoProcessor(private val qa: Boolean = false) : LocalVideoTrack.ExternalVideoFrameProcessing {
    private val policy = NightLumaPolicy()
    private val tables = Array(17) { NightLumaPolicy.lut(it) }
    private val histogram = IntArray(256)
    private var lastLog = ""
    private var lastLogAt = 0L

    private fun report(state: String, detail: String = "") {
        if (!qa) return
        val now = SystemClock.elapsedRealtime()
        if (state == lastLog && now - lastLogAt < 10_000) return
        lastLog = state
        lastLogAt = now
        Log.i("KyeobomNightQA", "state=$state $detail")
    }
    private var nextSample = 0L
    private var bypassUntil = 0L
    private var slowFrames = 0
    private var row = ByteArray(0)

    override fun onFrame(frame: VideoFrame): VideoFrame {
        val started = SystemClock.elapsedRealtime()
        if (started < bypassUntil) return frame
        if (!policy.active && started < nextSample) return frame
        val w = frame.buffer.width
        val h = frame.buffer.height
        if (w <= 0 || h <= 0 || w.toLong() * h > 3_200_000L) {
            report("unsupported_size", "${w}x$h")
            return frame
        }
        var input: VideoFrame.I420Buffer? = null
        var output: JavaI420Buffer? = null
        return try {
            val src = frame.buffer.toI420() ?: run { report("unsupported_buffer"); return frame }
            input = src
            if (started >= nextSample || policy.active) {
                val y = src.dataY
                var sum = 0.0
                var count = 0
                var dark = 0
                histogram.fill(0)
                for (gy in 0 until 12) {
                    val py = ((gy * 2 + 1) * h / 24).coerceAtMost(h - 1)
                    for (gx in 0 until 16) {
                        val px = ((gx * 2 + 1) * w / 32).coerceAtMost(w - 1)
                        val code = y.get(py * src.strideY + px).toInt() and 255
                        histogram[code]++
                        val v = ((code - 16) / 219.0).coerceIn(0.0, 1.0)
                        sum += v
                        count++
                        if (v < 0.30) dark++
                    }
                }
                val mean = sum / count
                val fraction = dark.toDouble() / count
                val low = ((NightLumaPolicy.percentile(histogram, count, 10) - 16) / 219.0).coerceIn(0.0, 1.0)
                val high = ((NightLumaPolicy.percentile(histogram, count, 95) - 16) / 219.0).coerceIn(0.0, 1.0)
                if (started >= nextSample) {
                    policy.observe(mean, fraction, low, high)
                    nextSample = started + 400
                } else if (policy.shouldBypass(mean, fraction, low, high)) {
                    policy.reset()
                }
                if (!policy.active) report(
                    if (high < .025 || (high < .065 && high - low < .018)) "insufficient_signal" else "original",
                    "mean=$mean p95=$high dark=$fraction"
                )
            }
            if (!policy.active) return frame
            val step = policy.nextStrengthStep()
            if (step == 0) return frame
            val dst = JavaI420Buffer.allocate(w, h)
            output = dst
            if (row.size < w) row = ByteArray(w)
            copyPlane(src.dataY, src.strideY, dst.dataY, dst.strideY, w, h, tables[step])
            val cw = (w + 1) / 2
            val ch = (h + 1) / 2
            copyPlane(src.dataU, src.strideU, dst.dataU, dst.strideU, cw, ch, null)
            copyPlane(src.dataV, src.strideV, dst.dataV, dst.strideV, cw, ch, null)
            val processed = VideoFrame(dst, frame.rotation, frame.timestampNs)
            // Ownership transferred to the new frame, released by the plugin.
            output = null
            report("enhanced", "${w}x$h strength=$step/16")
            processed
        } catch (_: Exception) {
            report("processing_error")
            policy.reset()
            bypassUntil = started + 10_000
            frame
        } finally {
            output?.release()
            input?.release()
            if (SystemClock.elapsedRealtime() - started > 35) {
                if (++slowFrames >= 3) {
                    policy.reset()
                    bypassUntil = SystemClock.elapsedRealtime() + 10_000
                    slowFrames = 0
                    report("performance_bypass", "10s")
                }
            } else {
                slowFrames = 0
            }
        }
    }

    private fun copyPlane(src: ByteBuffer, srcStride: Int, dst: ByteBuffer, dstStride: Int,
        width: Int, height: Int, table: ByteArray?) {
        for (r in 0 until height) {
            src.position(r * srcStride)
            src.get(row, 0, width)
            if (table != null) {
                for (x in 0 until width) row[x] = table[row[x].toInt() and 255]
            }
            dst.position(r * dstStride)
            dst.put(row, 0, width)
        }
    }
}
