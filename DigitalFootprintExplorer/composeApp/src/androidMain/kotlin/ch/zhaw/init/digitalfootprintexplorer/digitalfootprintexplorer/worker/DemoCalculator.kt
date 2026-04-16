package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker

import android.content.Context
import android.net.TrafficStats
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.DFEApplication
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.AppCategory
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.DataPoint
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.EmissionsCalculator
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.GardenState
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input.AppUsageInput
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input.DisplayInput
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.output.EmissionResult
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service.BackgroundProcessTracker

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
 * Display is intentionally excluded from the demo calculation: during a live demo
 * the screen is always on, making the display a constant background noise that
 * drowns out the app-usage effect the demo is meant to illustrate.
 * Background processes (GPS/BT) are still included — they are small compared to
 * network traffic and can genuinely be caused by the apps being demonstrated.
 *
 * Does NOT write to the database — the daily [DailyFootprintWorker] continues
 * to run unaffected in parallel.
 */
object DemoCalculator {

    // Baseline state — reset on demo activation and after each calculation
    private var baselineTimestampMs: Long = 0L
    private var baselineTotalBytes: Long  = 0L

    /**
     * Snapshots the current total device byte-count.
     * Call this when the demo toggle is turned ON.
     */
    fun resetBaseline(context: Context) {
        baselineTimestampMs = System.currentTimeMillis()
        baselineTotalBytes  = totalDeviceBytes()
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

        val toMs   = System.currentTimeMillis()
        val fromMs = if (baselineTimestampMs > 0L) baselineTimestampMs
                     else toMs - DEFAULT_WINDOW_MS

        // ── 1. Total-device network delta via TrafficStats ────────────────────
        // Per-UID access is blocked on Android 10+ for foreign UIDs (SELinux);
        // total bytes are still reliable and sufficient for demo purposes.
        val currentTotal = totalDeviceBytes()
        val deltaBytes   = maxOf(0L, currentTotal - baselineTotalBytes)
        val networkMetrics: List<AppUsageInput> = if (deltaBytes > 0L) listOf(
            AppUsageInput(
                appName       = "Gerät gesamt",
                appCategory   = AppCategory.MISCELLANEOUS,
                // TrafficStats does not distinguish WiFi vs. cellular;
                // attribute all bytes to WiFi (conservative, lower emission factor)
                wifiBytes     = DataPoint.Measured(deltaBytes.toDouble()),
                cellularBytes = DataPoint.Unavailable("not tracked in demo mode")
            )
        ) else emptyList()

        // ── 2. Reset baseline immediately so the next press measures a fresh delta
        baselineTimestampMs = toMs
        baselineTotalBytes  = currentTotal

        // ── 3. Background processes (non-destructive peek, same window)
        val backgroundInput = backgroundTracker.peek(fromMs, toMs)

        // ── 4. Emissions + demo garden state ──────────────────────────────────
        // Display is passed as empty — see class KDoc for the reasoning.
        val result = EmissionsCalculator().calculate(
            appUsage   = networkMetrics,
            display    = DisplayInput(intervals = emptyList()),
            background = backgroundInput
        )
        val gardenState = dfeApp.gardenStateCalculator.calculateDemoGardenState(result.ghgTotal)
        return result to gardenState
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    /**
     * Returns total device bytes (rx + tx across all interfaces).
     * Falls back to 0 if [TrafficStats] is not supported on this device.
     */
    private fun totalDeviceBytes(): Long {
        val rx = TrafficStats.getTotalRxBytes()
        val tx = TrafficStats.getTotalTxBytes()
        val validRx = if (rx == TrafficStats.UNSUPPORTED.toLong()) 0L else maxOf(0L, rx)
        val validTx = if (tx == TrafficStats.UNSUPPORTED.toLong()) 0L else maxOf(0L, tx)
        return validRx + validTx
    }

    private const val DEFAULT_WINDOW_MS = 30_000L  // fallback if baseline was never set
}
