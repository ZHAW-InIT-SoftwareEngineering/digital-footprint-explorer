package ch.zhaw.digitalfootprintexplorer.model

/**
 * Represents an input value with its data quality.
 * Measured: directly measured by the OS.
 * Estimated: scientifically justified estimate as fallback.
 * Unavailable: value cannot be determined, no fallback available → treated as 0.0.
 */
sealed class DataPoint {
    data class Measured(val value: Double) : DataPoint()
    data class Estimated(val value: Double, val reason: String) : DataPoint()
    data class Unavailable(val reason: String) : DataPoint()

    fun valueOrDefault(default: Double = 0.0): Double = when (this) {
        is Measured -> value
        is Estimated -> value
        is Unavailable -> default
    }
}
