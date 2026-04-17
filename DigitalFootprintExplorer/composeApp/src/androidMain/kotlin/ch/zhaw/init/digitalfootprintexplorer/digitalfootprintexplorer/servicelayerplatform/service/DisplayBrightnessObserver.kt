package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service

import android.content.Context
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import java.util.Locale
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input.BrightnessInterval
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input.DisplayInput

/**
 * Observes [Settings.System.SCREEN_BRIGHTNESS] changes and Screen On/Off events,
 * accumulating timestamped [BrightnessInterval]s for use in [EmissionsCalculator.calculate].
 *
 * Each interval stores the normalized brightness and a start/end timestamp so that
 * [collectAndReset] can clip intervals to any arbitrary calendar-day window — ensuring
 * the daily emissions calculation always covers exactly 24 h regardless of when the
 * [DailyFootprintWorker] happens to run.
 *
 * When the display is off the brightness is recorded as 0.0, which correctly contributes
 * zero display energy to the formula E_Display = P_Display * Σ(B̃_i * Δt_i).
 *
 * Intervals are persisted in SharedPreferences so they survive app restarts.
 *
 * Lifecycle (managed by [TrackingService]):
 *  - Call [register] when the service starts.
 *  - Call [onScreenOff] / [onScreenOn] from a BroadcastReceiver in the service.
 *  - Call [unregister] when the service is destroyed.
 *  - Call [collectAndReset] from [DailyFootprintWorker] with yesterday's boundaries.
 */
class DisplayBrightnessObserver(private val context: Context) {

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /* In-memory state of the currently open interval */
    private var currentBrightness: Double = 0.0
    private var intervalStartMs: Long = System.currentTimeMillis()
    private var screenOn: Boolean = true

    private val contentObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            if (!screenOn) return          /* ignore changes while screen is off */
            val now = System.currentTimeMillis()
            flushInterval(now)
            currentBrightness = readCurrentBrightness()
            intervalStartMs = now
        }
    }

    fun register() {
        screenOn = isScreenOn()
        currentBrightness = if (screenOn) readCurrentBrightness() else 0.0
        intervalStartMs = System.currentTimeMillis()
        context.contentResolver.registerContentObserver(
            Settings.System.getUriFor(Settings.System.SCREEN_BRIGHTNESS),
            false,
            contentObserver
        )
    }

    fun unregister() {
        context.contentResolver.unregisterContentObserver(contentObserver)
    }

    /** Called by [TrackingService] when it receives [android.content.Intent.ACTION_SCREEN_OFF]. */
    fun onScreenOff() {
        val now = System.currentTimeMillis()
        flushInterval(now)
        currentBrightness = 0.0
        intervalStartMs = now
        screenOn = false
    }

    /** Called by [TrackingService] when it receives [android.content.Intent.ACTION_SCREEN_ON]. */
    fun onScreenOn() {
        val now = System.currentTimeMillis()
        flushInterval(now)          /* flush the 0.0 (screen-off) interval */
        currentBrightness = readCurrentBrightness()
        intervalStartMs = now
        screenOn = true
    }

    /**
     * Flushes the current open interval, returns all [BrightnessInterval]s clipped to
     * [fromMs]..[toMs] (yesterday midnight → today midnight), and clears stored state
     * for the next day.
     *
     * Falls back to a single 24-hour interval at [DEFAULT_BRIGHTNESS] when no intervals
     * are found within the window (e.g. first ever run, or observer was not running).
     */
    fun collectAndReset(fromMs: Long, toMs: Long): DisplayInput {
        val now = System.currentTimeMillis()

        /* Flush the currently open interval up to the end of the collection window */
        val flushEnd = minOf(now, toMs)
        if (flushEnd > intervalStartMs) {
            appendInterval(currentBrightness, intervalStartMs, flushEnd)
        }
        /* Restart the open interval from now (belongs to the next day) */
        intervalStartMs = now

        val raw = prefs.getString(KEY_INTERVALS, "") ?: ""
        prefs.edit().remove(KEY_INTERVALS).apply()

        val intervals = parseAndClip(raw, fromMs, toMs)
        return DisplayInput(
            intervals = intervals.ifEmpty {
                listOf(BrightnessInterval(normalizedBrightness = DEFAULT_BRIGHTNESS, durationH = 24.0))
            }
        )
    }

    /** Writes the current open interval [intervalStartMs, endMs) to SharedPreferences. */
    private fun flushInterval(endMs: Long) {
        if (endMs > intervalStartMs) {
            appendInterval(currentBrightness, intervalStartMs, endMs)
        }
    }

    /**
     * Appends one entry in the format "brightness:startMs:endMs" to SharedPreferences.
     * Locale.ROOT is used explicitly so the brightness Double is always serialised with
     * a dot as decimal separator, regardless of the device locale (e.g. German uses comma).
     */
    private fun appendInterval(brightness: Double, startMs: Long, endMs: Long) {
        val existing = prefs.getString(KEY_INTERVALS, "") ?: ""
        val entry    = String.format(Locale.ROOT, "%.10f:%d:%d", brightness, startMs, endMs)
        val updated  = if (existing.isEmpty()) entry else "$existing,$entry"
        prefs.edit().putString(KEY_INTERVALS, updated).apply()
    }

    /**
     * Parses stored intervals and clips each one to [fromMs]..[toMs].
     * Entries that fall entirely outside the window are dropped.
     */
    private fun parseAndClip(raw: String, fromMs: Long, toMs: Long): List<BrightnessInterval> {
        if (raw.isBlank()) return emptyList()
        return raw.split(",").mapNotNull { entry ->
            val parts = entry.split(":")
            if (parts.size == 3) {
                val b = parts[0].toDoubleOrNull() ?: return@mapNotNull null
                val s = parts[1].toLongOrNull()   ?: return@mapNotNull null
                val e = parts[2].toLongOrNull()   ?: return@mapNotNull null
                val clippedStart = maxOf(s, fromMs)
                val clippedEnd   = minOf(e, toMs)
                if (clippedEnd <= clippedStart) return@mapNotNull null
                val durationH = (clippedEnd - clippedStart) / MILLIS_PER_HOUR
                BrightnessInterval(normalizedBrightness = b, durationH = durationH)
            } else null
        }
    }

    private fun readCurrentBrightness(): Double {
        val raw = Settings.System.getInt(
            context.contentResolver,
            Settings.System.SCREEN_BRIGHTNESS,
            DEFAULT_RAW_BRIGHTNESS
        )
        return raw / MAX_BRIGHTNESS
    }

    private fun isScreenOn(): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isInteractive
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
