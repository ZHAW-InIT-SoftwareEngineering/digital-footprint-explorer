package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.LocationManager
import android.os.Build
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.BackgroundProcess
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.ProcessUsage
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input.BackgroundInput

/**
 * Tracks GPS and Bluetooth active-time by listening to system broadcast events.
 *
 * Each on/off transition is stored as a timestamped interval ("startMs:endMs") in
 * SharedPreferences so that [collectAndReset] can clip the data to any arbitrary
 * calendar-day window — ensuring the daily emissions calculation always covers exactly
 * 24 h regardless of when the [DailyFootprintWorker] happens to run.
 *
 * No BATTERY_STATS permission is needed — on/off state is enough to estimate durations,
 * which are then fed into [EmissionsCalculator] using the power constants in ModelConstants.
 *
 * Lifecycle (managed by [TrackingService]):
 *  - Call [register] when the service starts.
 *  - Call [unregister] when the service is destroyed.
 *  - Call [collectAndReset] from [DailyFootprintWorker] with yesterday's boundaries.
 */
class BackgroundProcessTracker(private val context: Context) {

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                LocationManager.PROVIDERS_CHANGED_ACTION ->
                    updateState(BackgroundProcess.GPS, isGpsEnabled())
                BluetoothAdapter.ACTION_STATE_CHANGED -> {
                    val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                    updateState(BackgroundProcess.BLUETOOTH, state == BluetoothAdapter.STATE_ON)
                }
            }
        }
    }

    fun register() {
        initState(BackgroundProcess.GPS, isGpsEnabled())
        initState(BackgroundProcess.BLUETOOTH, isBluetoothEnabled())

        val filter = IntentFilter().apply {
            addAction(LocationManager.PROVIDERS_CHANGED_ACTION)
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }
    }

    fun unregister() {
        runCatching { context.unregisterReceiver(receiver) }
    }

    /**
     * Returns accumulated active durations for each [BackgroundProcess] clipped to
     * [fromMs]..[toMs] without resetting stored state. Used by [DemoFootprintWorker]
     * to read recent data non-destructively.
     */
    fun peek(fromMs: Long, toMs: Long): BackgroundInput {
        val now = System.currentTimeMillis()
        val processes = BackgroundProcess.entries.mapNotNull { process ->
            val isActive = prefs.getBoolean(activeKey(process), false)
            val startMs  = prefs.getLong(startKey(process), now)

            val raw = prefs.getString(intervalsKey(process), "") ?: ""
            val completedMs = parseAndClip(raw, fromMs, toMs).sum()

            /* Also include the currently open (active) interval clipped to the window */
            val openMs = if (isActive) {
                val clippedStart = maxOf(startMs, fromMs)
                val clippedEnd   = minOf(now, toMs)
                if (clippedEnd > clippedStart) clippedEnd - clippedStart else 0L
            } else 0L

            val totalH = ((completedMs + openMs) / MILLIS_PER_HOUR).toFloat()
            if (totalH > 0f) ProcessUsage(process = process, durationH = totalH) else null
        }
        return BackgroundInput(activeProcesses = processes)
    }

    /**
     * Flushes any currently active interval, returns accumulated active durations for each
     * [BackgroundProcess] clipped to [fromMs]..[toMs] (yesterday midnight → today midnight),
     * and clears stored intervals for the next day.
     */
    fun collectAndReset(fromMs: Long, toMs: Long): BackgroundInput {
        val now = System.currentTimeMillis()
        val processes = BackgroundProcess.entries.mapNotNull { process ->
            val isActive = prefs.getBoolean(activeKey(process), false)
            val startMs  = prefs.getLong(startKey(process), now)

            /* Flush the currently open (active) interval up to the end of the window */
            if (isActive) {
                val flushEnd = minOf(now, toMs)
                if (flushEnd > startMs) appendInterval(process, startMs, flushEnd)
            }

            val raw    = prefs.getString(intervalsKey(process), "") ?: ""
            val totalMs = parseAndClip(raw, fromMs, toMs).sum()
            val totalH  = (totalMs / MILLIS_PER_HOUR).toFloat()

            /* Clear completed intervals; keep active state; restart start-timestamp */
            prefs.edit()
                .remove(intervalsKey(process))
                .putLong(startKey(process), now)
                .apply()

            if (totalH > 0f) ProcessUsage(process = process, durationH = totalH) else null
        }
        return BackgroundInput(activeProcesses = processes)
    }

    /** Seeds initial state on first ever registration without double-counting. */
    private fun initState(process: BackgroundProcess, isActive: Boolean) {
        if (!prefs.contains(activeKey(process))) {
            prefs.edit()
                .putBoolean(activeKey(process), isActive)
                .putLong(startKey(process), System.currentTimeMillis())
                .apply()
        }
    }

    private fun updateState(process: BackgroundProcess, isNowActive: Boolean) {
        val now      = System.currentTimeMillis()
        val wasActive = prefs.getBoolean(activeKey(process), false)
        val editor   = prefs.edit().putBoolean(activeKey(process), isNowActive)

        if (wasActive && !isNowActive) {
            /* Process just turned off → close the interval */
            val start = prefs.getLong(startKey(process), now)
            appendInterval(process, start, now)
        } else if (!wasActive && isNowActive) {
            /* Process just turned on → record start timestamp */
            editor.putLong(startKey(process), now)
        }
        editor.apply()
    }

    /** Appends one entry in the format "startMs:endMs" to SharedPreferences. */
    private fun appendInterval(process: BackgroundProcess, startMs: Long, endMs: Long) {
        val existing = prefs.getString(intervalsKey(process), "") ?: ""
        val entry    = "$startMs:$endMs"
        val updated  = if (existing.isEmpty()) entry else "$existing,$entry"
        prefs.edit().putString(intervalsKey(process), updated).apply()
    }

    /**
     * Parses stored intervals, clips each one to [fromMs]..[toMs], and returns the
     * list of clipped durations in milliseconds.
     */
    private fun parseAndClip(raw: String, fromMs: Long, toMs: Long): List<Long> {
        if (raw.isBlank()) return emptyList()
        return raw.split(",").mapNotNull { entry ->
            val parts = entry.split(":")
            if (parts.size == 2) {
                val s = parts[0].toLongOrNull() ?: return@mapNotNull null
                val e = parts[1].toLongOrNull() ?: return@mapNotNull null
                val clippedStart = maxOf(s, fromMs)
                val clippedEnd   = minOf(e, toMs)
                if (clippedEnd > clippedStart) clippedEnd - clippedStart else null
            } else null
        }
    }

    private fun isGpsEnabled(): Boolean {
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return lm.isProviderEnabled(LocationManager.GPS_PROVIDER)
    }

    private fun isBluetoothEnabled(): Boolean {
        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return manager?.adapter?.isEnabled == true
    }

    private fun activeKey(p: BackgroundProcess)    = "active_${p.name}"
    private fun startKey(p: BackgroundProcess)     = "start_${p.name}"
    private fun intervalsKey(p: BackgroundProcess) = "intervals_${p.name}"

    companion object {
        private const val PREFS_NAME      = "background_process_tracker"
        private const val MILLIS_PER_HOUR = 3_600_000.0
    }
}
