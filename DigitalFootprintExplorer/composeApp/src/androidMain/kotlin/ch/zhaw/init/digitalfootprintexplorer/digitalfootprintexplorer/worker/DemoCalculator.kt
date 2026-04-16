package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker

import android.content.Context
import android.net.TrafficStats
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.DFEApplication
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.DataPoint
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.EmissionsCalculator
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.GardenState
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input.AppUsageInput
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.output.EmissionResult
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service.BackgroundProcessTracker
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service.DisplayBrightnessObserver
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service.InstalledAppProvider

/**
 * Demo-mode emissions calculator.
 *
 * Instead of querying [NetworkStatsManager] (which has a 2-5 min aggregation delay),
 * this uses [TrafficStats] which reads directly from the Linux kernel and is
 * near-real-time.
 *
 * Workflow:
 *  1. Demo activated → [resetBaseline] stores current byte-counts per app UID.
 *  2. User presses "Gartenzustand aktualisieren" → [calculate] computes the delta
 *     since the last baseline, evaluates emissions, updates the widget, and
 *     immediately stores a new baseline for the next press.
 *
 * This means each button press answers the question:
 * "What did the phone emit since I last pressed this button?"
 *
 * Display and background-process data use the same time window as the network
 * baseline so all three components are measured consistently.
 *
 * Does NOT write to the database — the daily [DailyFootprintWorker] continues
 * to run unaffected in parallel.
 */
object DemoCalculator {

    // Baseline state — reset on demo activation and after each calculation
    private var baselineTimestampMs: Long = 0L
    private var baselineBytes: Map<Int, Long> = emptyMap()  // uid → total bytes at baseline

    /**
     * Captures the current [TrafficStats] byte-counts for all installed apps.
     * Call this when the demo toggle is turned ON.
     */
    fun resetBaseline(context: Context) {
        val apps = InstalledAppProvider().getInstalledLauncherApps(context)
        baselineTimestampMs = System.currentTimeMillis()
        baselineBytes = apps.associate { it.uid to totalBytesForUid(it.uid) }
    }

    /**
     * Calculates emissions for the period since the last [resetBaseline] / [calculate] call:
     *  - Network: [TrafficStats] delta per app UID (real-time, no aggregation delay)
     *  - Display:  brightness intervals via [DisplayBrightnessObserver.peek]
     *  - Background: GPS/BT intervals via [BackgroundProcessTracker.peek]
     *
     * After the calculation a new baseline is stored automatically so the next
     * button press measures a fresh delta.
     */
    suspend fun calculate(context: Context): Pair<EmissionResult, GardenState> {
        val dfeApp              = context.applicationContext as DFEApplication
        val brightnessObserver: DisplayBrightnessObserver = dfeApp.displayBrightnessObserver
        val backgroundTracker:  BackgroundProcessTracker  = dfeApp.backgroundProcessTracker

        val toMs   = System.currentTimeMillis()
        val fromMs = if (baselineTimestampMs > 0L) baselineTimestampMs
                     else toMs - DEFAULT_WINDOW_MS

        // ── 1. Network delta via TrafficStats ─────────────────────────────────
        val apps = InstalledAppProvider().getInstalledLauncherApps(context)
        val networkMetrics: List<AppUsageInput> = apps.mapNotNull { app ->
            val currentBytes = totalBytesForUid(app.uid)
            val baseBytes    = baselineBytes[app.uid] ?: currentBytes
            val deltaBytes   = maxOf(0L, currentBytes - baseBytes)
            if (deltaBytes == 0L) return@mapNotNull null
            AppUsageInput(
                appName            = app.name,
                appCategory        = app.category,
                // TrafficStats does not distinguish WiFi vs. cellular;
                // attribute all bytes to WiFi (conservative, lower emission factor)
                wifiBytes          = DataPoint.Measured(deltaBytes.toDouble()),
                cellularBytes      = DataPoint.Unavailable("not tracked in demo mode")
            )
        }

        // ── 2. Reset baseline immediately so the next press measures a fresh delta
        baselineTimestampMs = toMs
        baselineBytes = apps.associate { it.uid to totalBytesForUid(it.uid) }

        // ── 3. Display brightness (non-destructive peek, same window as network)
        val displayInput    = brightnessObserver.peek(fromMs, toMs)

        // ── 4. Background processes (non-destructive peek, same window)
        val backgroundInput = backgroundTracker.peek(fromMs, toMs)

        // ── 5. Emissions + demo garden state ──────────────────────────────────
        val result = EmissionsCalculator().calculate(
            appUsage   = networkMetrics,
            display    = displayInput,
            background = backgroundInput
        )
        val gardenState = dfeApp.gardenStateCalculator.calculateDemoGardenState(result.ghgTotal)
        return result to gardenState
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    /**
     * Returns total bytes (rx + tx) for [uid] from the kernel traffic table.
     * Returns 0 for UIDs not tracked by the kernel ([TrafficStats.UNSUPPORTED]).
     */
    private fun totalBytesForUid(uid: Int): Long {
        val rx = TrafficStats.getUidRxBytes(uid)
        val tx = TrafficStats.getUidTxBytes(uid)
        val validRx = if (rx == TrafficStats.UNSUPPORTED.toLong()) 0L else maxOf(0L, rx)
        val validTx = if (tx == TrafficStats.UNSUPPORTED.toLong()) 0L else maxOf(0L, tx)
        return validRx + validTx
    }

    private const val DEFAULT_WINDOW_MS = 30_000L  // fallback if baseline was never set
}
