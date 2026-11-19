package com.mingyu.kyeobom

import kotlin.math.pow
import kotlin.math.roundToInt

/** Pure luminance policy shared in behavior with the iOS implementation.
 * All measurements are normalized to 0..1, not lux or exposure metadata.
 */
internal class NightLumaPolicy {
    var active = false
        private set
    private var darkSamples = 0
    private var brightSamples = 0
    private var strengthStep = 0

    fun observe(mean: Double, darkFraction: Double) {
        if (!mean.isFinite() || !darkFraction.isFinite()) { reset(); return }
        // Already bright, backlit, or nearly signal-free: bypass immediately.
        if (mean >= 0.42 || darkFraction < 0.45 || mean < 0.012) {
            reset()
            return
        }
        val dark = mean <= 0.23 && darkFraction >= 0.80
        val bright = mean >= 0.32 || darkFraction < 0.65
        if (!active) {
            darkSamples = if (dark) darkSamples + 1 else 0
            if (darkSamples >= 3) {
                active = true
                brightSamples = 0
            }
        } else {
            brightSamples = if (bright) brightSamples + 1 else 0
            if (brightSamples >= 2) reset()
        }
    }

    fun nextStrengthStep(): Int {
        if (!active) { strengthStep = 0; return 0 }
        strengthStep = (strengthStep + 1).coerceAtMost(8)
        return strengthStep
    }

    fun reset() {
        active = false
        darkSamples = 0
        brightSamples = 0
        strengthStep = 0
    }

    companion object {
        fun lut(step: Int, low: Int = 16, high: Int = 235): ByteArray {
            val amount = step.coerceIn(0, 8) / 8.0
            return ByteArray(256) { value ->
                if (value <= low || value >= high || amount == 0.0) value.toByte()
                else {
                    val x = (value - low).toDouble() / (high - low)
                    // Keep true black, taper near black (avoid lifting read noise),
                    // and protect mid/highlight detail. Maximum lift is 18%.
                    val lift = ((x.pow(0.65) - x) * (x / 0.035).coerceIn(0.0, 1.0))
                        .coerceIn(0.0, 0.18)
                    val taper = ((0.72 - x) / 0.32).coerceIn(0.0, 1.0)
                    (low + (x + lift * taper * amount) * (high - low))
                        .roundToInt().coerceIn(value, high).toByte()
                }
            }
        }
    }
}
