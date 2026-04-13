package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service

import android.content.Context
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input.BrightnessInterval
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input.DisplayInput

/**
 * Observes [Settings.System.SCREEN_BRIGHTNESS] changes and accumulates [BrightnessInterval]s
 * for use in [EmissionsCalculator.calculate].
 *
 * Intervals are persisted in SharedPreferences so they survive app restarts.
 *
 * Lifecycle:
 *  - Call [register] in Application.onCreate to start tracking.
 *  - Call [collectAndReset] from [DailyFootprintWorker] to get today's [DisplayInput] and clear state.
 */
class DisplayBrightnessObserver(private val context: Context) {

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private var lastBrightness: Double = readCurrentBrightness()
    private var lastTimestampMs: Long = System.currentTimeMillis()

    private val contentObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            val now = System.currentTimeMillis()
            val durationH = (now - lastTimestampMs) / MILLIS_PER_HOUR
            if (durationH > 0) {
                appendInterval(lastBrightness, durationH)
            }
            lastBrightness = readCurrentBrightness()
            lastTimestampMs = now
        }
    }

    fun register() {
        lastBrightness = readCurrentBrightness()
        lastTimestampMs = System.currentTimeMillis()
        context.contentResolver.registerContentObserver(
            Settings.System.getUriFor(Settings.System.SCREEN_BRIGHTNESS),
            /* notifyForDescendants = */ false,
            contentObserver
        )
    }

    fun unregister() {
        context.contentResolver.unregisterContentObserver(contentObserver)
    }

    /**
     * Flushes the current open interval, returns all accumulated [BrightnessInterval]s as a
     * [DisplayInput], and clears stored state for the next day.
     *
     * Falls back to a single 24-hour interval at [DEFAULT_BRIGHTNESS] when no changes were
     * recorded (e.g. first day or observer was not running).
     */
    fun collectAndReset(): DisplayInput {
        val now = System.currentTimeMillis()
        val durationH = (now - lastTimestampMs) / MILLIS_PER_HOUR
        if (durationH > 0) {
            appendInterval(lastBrightness, durationH)
        }
        lastTimestampMs = now

        val raw = prefs.getString(KEY_INTERVALS, "") ?: ""
        val intervals = parseIntervals(raw)
        prefs.edit().remove(KEY_INTERVALS).apply()

        return DisplayInput(
            intervals = intervals.ifEmpty {
                listOf(BrightnessInterval(normalizedBrightness = DEFAULT_BRIGHTNESS, durationH = 24.0))
            }
        )
    }

    private fun readCurrentBrightness(): Double {
        val raw = Settings.System.getInt(
            context.contentResolver,
            Settings.System.SCREEN_BRIGHTNESS,
            DEFAULT_RAW_BRIGHTNESS
        )
        return raw / MAX_BRIGHTNESS
    }

    private fun appendInterval(brightness: Double, durationH: Double) {
        val existing = prefs.getString(KEY_INTERVALS, "") ?: ""
        val updated = if (existing.isEmpty()) "$brightness:$durationH"
                      else "$existing,$brightness:$durationH"
        prefs.edit().putString(KEY_INTERVALS, updated).apply()
    }

    private fun parseIntervals(raw: String): List<BrightnessInterval> {
        if (raw.isBlank()) return emptyList()
        return raw.split(",").mapNotNull { entry ->
            val parts = entry.split(":")
            if (parts.size == 2) {
                val b = parts[0].toDoubleOrNull() ?: return@mapNotNull null
                val d = parts[1].toDoubleOrNull() ?: return@mapNotNull null
                BrightnessInterval(normalizedBrightness = b, durationH = d)
            } else null
        }
    }

    companion object {
        private const val PREFS_NAME          = "display_brightness_observer"
        private const val KEY_INTERVALS       = "intervals"
        private const val MAX_BRIGHTNESS      = 255.0
        private const val DEFAULT_RAW_BRIGHTNESS = 128
        private const val DEFAULT_BRIGHTNESS  = 0.5
        private const val MILLIS_PER_HOUR     = 3_600_000.0
    }
}
