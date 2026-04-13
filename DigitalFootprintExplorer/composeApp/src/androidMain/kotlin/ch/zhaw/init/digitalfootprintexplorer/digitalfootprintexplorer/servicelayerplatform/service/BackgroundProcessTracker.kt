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
 * Active durations are accumulated in SharedPreferences so intervals survive app restarts.
 * No BATTERY_STATS permission is needed — on/off state is enough to estimate durations,
 * which are then fed into [EmissionsCalculator] using the power constants in ModelConstants.
 *
 * Lifecycle:
 *  - Call [register] in Application.onCreate.
 *  - Call [collectAndReset] from [DailyFootprintWorker] to get today's [BackgroundInput].
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
     * Returns accumulated active durations for each [BackgroundProcess] since the last reset
     * and clears the stored state for the next day.
     */
    fun collectAndReset(): BackgroundInput {
        val now = System.currentTimeMillis()
        val processes = BackgroundProcess.entries.mapNotNull { process ->
            val accumulatedMs = prefs.getLong(durationKey(process), 0L)
            val isActive      = prefs.getBoolean(activeKey(process), false)
            val startMs       = prefs.getLong(startKey(process), now)

            val totalMs = if (isActive) accumulatedMs + (now - startMs) else accumulatedMs
            val totalH  = (totalMs / 3_600_000.0).toFloat()

            // Reset accumulated duration; keep active state, restart start-timestamp
            prefs.edit()
                .putLong(durationKey(process), 0L)
                .putLong(startKey(process), now)
                .apply()

            if (totalH > 0f) ProcessUsage(process = process, durationH = totalH) else null
        }
        return BackgroundInput(activeProcesses = processes)
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    /** Called once on startup to seed the initial state without double-counting. */
    private fun initState(process: BackgroundProcess, isActive: Boolean) {
        if (!prefs.contains(activeKey(process))) {
            prefs.edit()
                .putBoolean(activeKey(process), isActive)
                .putLong(startKey(process), System.currentTimeMillis())
                .putLong(durationKey(process), 0L)
                .apply()
        }
    }

    private fun updateState(process: BackgroundProcess, isNowActive: Boolean) {
        val now       = System.currentTimeMillis()
        val wasActive = prefs.getBoolean(activeKey(process), false)
        val editor    = prefs.edit().putBoolean(activeKey(process), isNowActive)

        if (wasActive && !isNowActive) {
            val start       = prefs.getLong(startKey(process), now)
            val accumulated = prefs.getLong(durationKey(process), 0L)
            editor.putLong(durationKey(process), accumulated + (now - start))
        } else if (!wasActive && isNowActive) {
            editor.putLong(startKey(process), now)
        }
        editor.apply()
    }

    private fun isGpsEnabled(): Boolean {
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return lm.isProviderEnabled(LocationManager.GPS_PROVIDER)
    }

    private fun isBluetoothEnabled(): Boolean {
        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return manager?.adapter?.isEnabled == true
    }

    private fun activeKey(p: BackgroundProcess)   = "active_${p.name}"
    private fun durationKey(p: BackgroundProcess) = "duration_${p.name}"
    private fun startKey(p: BackgroundProcess)    = "start_${p.name}"

    companion object {
        private const val PREFS_NAME = "background_process_tracker"
    }
}
