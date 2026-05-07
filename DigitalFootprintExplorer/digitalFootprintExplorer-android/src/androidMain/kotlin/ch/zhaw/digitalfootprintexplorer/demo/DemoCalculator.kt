package ch.zhaw.digitalfootprintexplorer.demo

import android.content.Context
import android.net.TrafficStats
import androidx.core.content.edit
import ch.zhaw.digitalfootprintexplorer.DFEApplication
import ch.zhaw.digitalfootprintexplorer.model.AppCategory
import ch.zhaw.digitalfootprintexplorer.model.DataPoint
import ch.zhaw.digitalfootprintexplorer.model.EmissionsCalculator
import ch.zhaw.digitalfootprintexplorer.model.GardenState
import ch.zhaw.digitalfootprintexplorer.model.input.AppUsageInput
import ch.zhaw.digitalfootprintexplorer.model.input.DisplayInput
import ch.zhaw.digitalfootprintexplorer.model.output.EmissionResult
import ch.zhaw.digitalfootprintexplorer.servicelayerplatform.service.BackgroundProcessTracker

/**
 * Demo-mode emissions calculator.
 *
 * Uses [TrafficStats.getTotalRxBytes] / [TrafficStats.getTotalTxBytes] for network tracking.
 * Note: since Android 10, per-UID traffic stats ([TrafficStats.getUidRxBytes]) are restricted
 * for foreign UIDs via SELinux — they return [TrafficStats.UNSUPPORTED]. Total device bytes
 * are still accessible and give a reliable real-time delta.
 *
 * Workflow:
 *  1. Demo activated → [resetBaseline] snapshots current total byte-count.
 *  2. User presses "Gartenzustand aktualisieren" → [calculate] computes the delta
 *     since the last baseline, evaluates emissions, and immediately stores a new
 *     baseline for the next press.
 *
 * This means each button press answers the question:
 * "What did the phone emit since I last pressed this button?"
 *
 * **Baseline persistence:** the three baseline values are saved to SharedPreferences
 * so they survive process restarts (e.g. the app being opened via widget click).
 * Opening the app does NOT reset the baseline — only toggling demo OFF→ON does.
 * There is no in-memory mirror; every operation reads directly from SharedPreferences
 * so the object is stateless and process-restart safe.
 *
 * Display is intentionally excluded from the demo calculation: during a live demo
 * the screen is always on, making the display a constant background noise that
 * drowns out the app-usage effect the demo is meant to illustrate.
 * Background processes (GPS/BT) are still included — they are small compared to
 * network traffic and can genuinely be caused by the apps being demonstrated.
 *
 */
object DemoCalculator {

    /**
     * Snapshots the current byte-counts as the new baseline and persists them.
     * Call this when the user actively toggles demo ON (not on app open).
     */
    fun resetBaseline(context: Context) {
        val ts    = System.currentTimeMillis()
        val total = totalDeviceBytes()
        val dfe   = ownAppBytes(context)
        context.getSharedPreferences(DemoPreferences.PREFS_CALCULATOR_FILE, Context.MODE_PRIVATE)
            .edit {
                putLong(DemoPreferences.KEY_BASELINE_TS, ts)
                putLong(DemoPreferences.KEY_BASELINE_TOTAL, total)
                putLong(DemoPreferences.KEY_BASELINE_DFE, dfe)
            }
    }

    /**
     * Clears the persisted baseline.
     * Call this when demo is toggled OFF so the next activation starts clean.
     */
    fun clearBaseline(context: Context) {
        context.getSharedPreferences(DemoPreferences.PREFS_CALCULATOR_FILE, Context.MODE_PRIVATE)
            .edit {
                remove(DemoPreferences.KEY_BASELINE_TS)
                remove(DemoPreferences.KEY_BASELINE_TOTAL)
                remove(DemoPreferences.KEY_BASELINE_DFE)
            }
    }

    /**
     * Calculates emissions for the period since the last [resetBaseline] / [calculate] call:
     *  - Network:     total device [TrafficStats] delta (real-time, works on all Android versions)
     *  - Display:     excluded — always-on screen during demo would mask the app-usage signal
     *  - Background:  GPS/BT intervals via [BackgroundProcessTracker.peek]
     *
     * After the calculation a new baseline is stored automatically so the next
     * button press measures a fresh delta.
     */
    suspend fun calculate(context: Context): Pair<EmissionResult, GardenState> {
        val dfeApp            = context.applicationContext as DFEApplication
        val backgroundTracker: BackgroundProcessTracker = dfeApp.backgroundProcessTracker

        val prefs = context.getSharedPreferences(DemoPreferences.PREFS_CALCULATOR_FILE, Context.MODE_PRIVATE)
        val baselineTs    = prefs.getLong(DemoPreferences.KEY_BASELINE_TS,    0L)
        val baselineTotal = prefs.getLong(DemoPreferences.KEY_BASELINE_TOTAL, 0L)
        val baselineDfe   = prefs.getLong(DemoPreferences.KEY_BASELINE_DFE,   0L)

        val toMs   = System.currentTimeMillis()
        val fromMs = if (baselineTs > 0L) baselineTs else toMs - 30_000L

        val currentTotal = totalDeviceBytes()
        val currentDfe   = ownAppBytes(context)
        val totalDelta   = maxOf(0L, currentTotal - baselineTotal)
        val dfeDelta     = maxOf(0L, currentDfe   - baselineDfe)
        val deltaBytes   = maxOf(0L, totalDelta   - dfeDelta)
        val networkMetrics: List<AppUsageInput> = if (deltaBytes > 0L) listOf(
            AppUsageInput(
                appName       = "Device total",
                appCategory   = AppCategory.MISCELLANEOUS,
                wifiBytes     = DataPoint.Measured(deltaBytes.toDouble()),
                cellularBytes = DataPoint.Unavailable("not tracked in demo mode")
            )
        ) else emptyList()

        prefs.edit {
            putLong(DemoPreferences.KEY_BASELINE_TS, toMs)
            putLong(DemoPreferences.KEY_BASELINE_TOTAL, currentTotal)
            putLong(DemoPreferences.KEY_BASELINE_DFE, currentDfe)
        }
        val backgroundInput = backgroundTracker.peek(fromMs, toMs)

        val result = EmissionsCalculator().calculate(
            appUsage   = networkMetrics,
            display    = DisplayInput(intervals = emptyList()),
            background = backgroundInput
        )
        val gardenState = calculateDemoGardenState(result.ghgTotal)

        return result to gardenState
    }

    private fun totalDeviceBytes(): Long {
        val rx = TrafficStats.getTotalRxBytes()
        val tx = TrafficStats.getTotalTxBytes()
        val validRx = if (rx == TrafficStats.UNSUPPORTED.toLong()) 0L else maxOf(0L, rx)
        val validTx = if (tx == TrafficStats.UNSUPPORTED.toLong()) 0L else maxOf(0L, tx)
        return validRx + validTx
    }

    private fun ownAppBytes(context: Context): Long {
        val uid = context.applicationInfo.uid
        val rx  = TrafficStats.getUidRxBytes(uid)
        val tx  = TrafficStats.getUidTxBytes(uid)
        val validRx = if (rx == TrafficStats.UNSUPPORTED.toLong()) 0L else maxOf(0L, rx)
        val validTx = if (tx == TrafficStats.UNSUPPORTED.toLong()) 0L else maxOf(0L, tx)
        return validRx + validTx
    }

    /**
     * Evaluates [kgCO2e] against absolute thresholds calibrated for a short
     * measurement window instead of comparing against the 7-day baseline used in
     * production.
     */
    private fun calculateDemoGardenState(kgCO2e: Double): GardenState = when {
        kgCO2e < 5e-6   -> GardenState.FLOURISHING
        kgCO2e < 2e-5   -> GardenState.GROWING
        kgCO2e < 3.5e-5 -> GardenState.STABLE
        kgCO2e < 5.5e-5 -> GardenState.WILTING
        else            -> GardenState.WITHERED
    }
}
