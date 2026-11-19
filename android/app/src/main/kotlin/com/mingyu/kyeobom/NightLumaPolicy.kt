package com.mingyu.kyeobom

import kotlin.math.roundToInt

/** Same signal-based policy as Swift. Statistics are decoded luma, not lux. */
internal class NightLumaPolicy {
    var active = false
        private set
    private var darkSamples = 0
    private var brightSamples = 0
    private var strengthStep = 0
    private var targetStep = 0

    fun shouldBypass(mean: Double, darkFraction: Double, low: Double, high: Double): Boolean =
        !mean.isFinite() || !darkFraction.isFinite() || !low.isFinite() || !high.isFinite() ||
            mean >= 0.42 || darkFraction < 0.45 || high < 0.025 ||
            (high < 0.065 && high - low < 0.018)

    fun observe(mean: Double, darkFraction: Double, low: Double, high: Double) {
        if (shouldBypass(mean, darkFraction, low, high)) { reset(); return }
        val dark = mean <= 0.29 && darkFraction >= 0.70
        val bright = mean >= 0.35 || darkFraction < 0.60
        if (!active) {
            darkSamples = if (dark) darkSamples + 1 else 0
            if (darkSamples >= 3) {
                active = true
                brightSamples = 0
            }
        } else {
            brightSamples = if (bright) brightSamples + 1 else 0
            if (brightSamples >= 2) { reset(); return }
        }
        if (active) {
            val illumination = ((0.34 - mean) / 0.26).coerceIn(0.0, 1.0)
            val signal = ((high - 0.025) / 0.055).coerceIn(0.0, 1.0)
            targetStep = (16 * illumination * signal).roundToInt().coerceIn(1, 16)
        }
    }

    fun nextStrengthStep(): Int {
        if (!active) { strengthStep = 0; return 0 }
        strengthStep += (targetStep - strengthStep).coerceIn(-1, 1)
        return strengthStep
    }

    fun reset() {
        active = false
        darkSamples = 0
        brightSamples = 0
        strengthStep = 0
        targetStep = 0
    }

    companion object {
        // Monotonic curve, true black and near-black floor, soft highlight rolloff.
        private val knots = doubleArrayOf(0.0, 0.01, 0.03, 0.06, 0.12, 0.22, 0.35, 0.55, 0.75, 0.90, 1.0)
        private val lifted = doubleArrayOf(0.0, 0.01, 0.075, 0.19, 0.34, 0.48, 0.60, 0.70, 0.80, 0.91, 1.0)

        fun lut(step: Int, low: Int = 16, high: Int = 235): ByteArray {
            val amount = step.coerceIn(0, 16) / 16.0
            return ByteArray(256) { value ->
                if (value <= low || value >= high || amount == 0.0) value.toByte()
                else {
                    val x = (value - low).toDouble() / (high - low)
                    val segment = (1 until knots.size).first { x <= knots[it] }
                    val t = (x - knots[segment - 1]) / (knots[segment] - knots[segment - 1])
                    val target = lifted[segment - 1] + t * (lifted[segment] - lifted[segment - 1])
                    (low + (x + (target - x) * amount) * (high - low))
                        .roundToInt().coerceIn(value, high).toByte()
                }
            }
        }

        fun percentile(histogram: IntArray, count: Int, percentile: Int): Int {
            val rank = ((count * percentile + 99) / 100).coerceAtLeast(1)
            var cumulative = 0
            for (i in histogram.indices) {
                cumulative += histogram[i]
                if (cumulative >= rank) return i
            }
            return 0
        }
    }
}
