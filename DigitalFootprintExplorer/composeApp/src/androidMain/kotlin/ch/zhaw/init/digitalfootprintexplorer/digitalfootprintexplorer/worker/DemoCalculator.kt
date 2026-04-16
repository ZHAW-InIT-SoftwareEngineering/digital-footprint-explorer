package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker

import android.content.Context
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.DFEApplication
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.EmissionsCalculator
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.GardenState
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.output.EmissionResult
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service.InstalledAppProvider
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service.MetricCollector
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service.NetworkUsageDataSource

/**
 * Performs a single demo-mode emissions calculation over a rolling [WINDOW_MS]-window.
 *
 * Unlike [DailyFootprintWorker], this:
 *  - reads brightness and background data non-destructively via [peek] (no reset)
 *  - does NOT write to the database
 *  - uses [GardenStateCalculator.calculateDemoGardenState] with absolute thresholds
 *    calibrated for a short time window instead of the 7-day baseline comparison
 *
 * Call [calculate] from a coroutine loop in the UI (e.g. every 10 seconds) to
 * continuously update the garden widget during a demo session.
 */
object DemoCalculator {

    const val WINDOW_MS = 30_000L   // 30-second rolling window
    const val POLL_MS   = 10_000L   // recalculate every 10 seconds

    /**
     * Runs the full emissions calculation for the last [WINDOW_MS] milliseconds and
     * returns the result together with the corresponding [GardenState].
     *
     * Does not modify any stored state — safe to call repeatedly.
     */
    suspend fun calculate(context: Context): Pair<EmissionResult, GardenState> {
        val app   = context.applicationContext as DFEApplication
        val toMs  = System.currentTimeMillis()
        val fromMs = toMs - WINDOW_MS

        // ── Network metrics (last 30 s) ───────────────────────────────────────
        val networkMetrics = MetricCollector(
            installedAppProvider   = InstalledAppProvider(),
            networkUsageDataSource = NetworkUsageDataSource(context)
        ).collectNetworkMetrics(context, fromMs, toMs, mobileSubscriberId = null)

        // ── Display brightness (non-destructive peek) ─────────────────────────
        val displayInput = app.displayBrightnessObserver.peek(fromMs, toMs)

        // ── Background processes (non-destructive peek) ───────────────────────
        val backgroundInput = app.backgroundProcessTracker.peek(fromMs, toMs)

        // ── Emissions (raw, not scaled — demo thresholds are calibrated for 30 s)
        val result = EmissionsCalculator().calculate(
            appUsage   = networkMetrics,
            display    = displayInput,
            background = backgroundInput
        )

        val gardenState = app.gardenStateCalculator.calculateDemoGardenState(result.ghgTotal)
        return result to gardenState
    }
}
