package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker

import android.content.Context
import android.net.TrafficStats
import android.util.Log
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
 * **Baseline persistence:** the three baseline values are saved to SharedPreferences
 * so they survive process restarts (e.g. the app being opened via widget click).
 * Opening the app does NOT reset the baseline — only toggling demo OFF→ON does.
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

    // In-memory baseline — mirrors what is persisted in SharedPreferences
    private var baselineTimestampMs: Long = 0L
    private var baselineTotalBytes: Long  = 0L
    private var baselineDfeBytes:   Long  = 0L

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Snapshots the current byte-counts as the new baseline and persists them.
     * Call this when the user actively toggles demo ON (not on app open).
     */
    fun resetBaseline(context: Context) {
        baselineTimestampMs = System.currentTimeMillis()
        baselineTotalBytes  = totalDeviceBytes()
        baselineDfeBytes    = ownAppBytes(context)
        saveBaseline(context)
        Log.d(TAG, "🔄 Baseline gesetzt: ${fmtMs(baselineTimestampMs)}, " +
                "total=${fmtBytes(baselineTotalBytes)}, dfe=${fmtBytes(baselineDfeBytes)}")
    }

    /**
     * Restores the baseline from SharedPreferences without recapturing live counts.
     * Call this when the app is opened while demo was already active, so that
     * traffic accumulated while the app was in the background is not lost.
     */
    fun restoreBaseline(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        baselineTimestampMs = prefs.getLong(KEY_BASELINE_TS,    0L)
        baselineTotalBytes  = prefs.getLong(KEY_BASELINE_TOTAL, 0L)
        baselineDfeBytes    = prefs.getLong(KEY_BASELINE_DFE,   0L)
        Log.d(TAG, "♻ Baseline wiederhergestellt: ${fmtMs(baselineTimestampMs)}")
    }

    /**
     * Clears the persisted baseline.
     * Call this when demo is toggled OFF so the next activation starts clean.
     */
    fun clearBaseline(context: Context) {
        baselineTimestampMs = 0L
        baselineTotalBytes  = 0L
        baselineDfeBytes    = 0L
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_BASELINE_TS)
            .remove(KEY_BASELINE_TOTAL)
            .remove(KEY_BASELINE_DFE)
            .apply()
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

        // Guard: if baseline was never set (shouldn't happen, but just in case),
        // use the last 30 s as fallback window.
        val toMs   = System.currentTimeMillis()
        val fromMs = if (baselineTimestampMs > 0L) baselineTimestampMs
                     else toMs - DEFAULT_WINDOW_MS

        val windowSec = (toMs - fromMs) / 1_000.0
        Log.d(TAG, "▶ Demo-Berechnung gestartet")
        Log.d(TAG, "📅 Fenster: ${fmtMs(fromMs)} → ${fmtMs(toMs)} (%.1fs)".format(windowSec))

        // ── 1. Total-device network delta via TrafficStats ────────────────────
        val currentTotal = totalDeviceBytes()
        val currentDfe   = ownAppBytes(context)
        val totalDelta   = maxOf(0L, currentTotal - baselineTotalBytes)
        val dfeDelta     = maxOf(0L, currentDfe   - baselineDfeBytes)
        val deltaBytes   = maxOf(0L, totalDelta   - dfeDelta)
        val networkMetrics: List<AppUsageInput> = if (deltaBytes > 0L) listOf(
            AppUsageInput(
                appName       = "Gerät gesamt",
                appCategory   = AppCategory.MISCELLANEOUS,
                wifiBytes     = DataPoint.Measured(deltaBytes.toDouble()),
                cellularBytes = DataPoint.Unavailable("not tracked in demo mode")
            )
        ) else emptyList()

        Log.d(TAG, "📶 Netzwerk (Gerät gesamt, excl. DFE-App):")
        Log.d(TAG, "   · Gesamtdelta  : ${fmtBytes(totalDelta)}")
        Log.d(TAG, "   · DFE-App      : ${fmtBytes(dfeDelta)}  (abgezogen)")
        Log.d(TAG, "   · Netto        : ${fmtBytes(deltaBytes)}")
        Log.d(TAG, "   ⚠ Pro-App-Aufschlüsselung nicht verfügbar (Android 10+ SELinux)")

        // ── 2. Reset baseline for the next press and persist ──────────────────
        baselineTimestampMs = toMs
        baselineTotalBytes  = currentTotal
        baselineDfeBytes    = currentDfe
        saveBaseline(context)

        // ── 3. Background processes (non-destructive peek, same window) ───────
        val backgroundInput = backgroundTracker.peek(fromMs, toMs)

        if (backgroundInput.activeProcesses.isEmpty()) {
            Log.d(TAG, "📍 Hintergrundprozesse: keine aktiv")
        } else {
            Log.d(TAG, "📍 Hintergrundprozesse:")
            backgroundInput.activeProcesses.forEach { usage ->
                Log.d(TAG, "   · ${usage.process.name}: %.4fh".format(usage.durationH))
            }
        }

        // ── 4. Emissions + demo garden state ──────────────────────────────────
        val result = EmissionsCalculator().calculate(
            appUsage   = networkMetrics,
            display    = DisplayInput(intervals = emptyList()),
            background = backgroundInput
        )
        val gardenState = dfeApp.gardenStateCalculator.calculateDemoGardenState(result.ghgTotal)

        Log.d(TAG, "🔢 Emissionen:")
        Log.d(TAG, "   · App-Nutzung  : ${"%.6f".format(result.ghgAppUsage   * 1000)} gCO₂e")
        Log.d(TAG, "   · Hintergrund  : ${"%.6f".format(result.ghgBackground * 1000)} gCO₂e")
        Log.d(TAG, "   · TOTAL        : ${"%.6f".format(result.ghgTotal      * 1000)} gCO₂e")
        Log.d(TAG, "🌱 Gartenzustand → $gardenState")

        return result to gardenState
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private fun saveBaseline(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_BASELINE_TS,    baselineTimestampMs)
            .putLong(KEY_BASELINE_TOTAL, baselineTotalBytes)
            .putLong(KEY_BASELINE_DFE,   baselineDfeBytes)
            .apply()
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

    private fun fmtBytes(bytes: Long): String = when {
        bytes >= 1_000_000 -> "%.2f MB".format(bytes / 1_000_000.0)
        bytes >= 1_000     -> "%.1f KB".format(bytes / 1_000.0)
        else               -> "$bytes B"
    }

    private fun fmtMs(ms: Long): String {
        val sdf = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
        return sdf.format(java.util.Date(ms))
    }

    private const val DEFAULT_WINDOW_MS   = 30_000L
    private const val TAG                 = "DFE_Demo"
    private const val PREFS_NAME          = "demo_calculator_prefs"
    private const val KEY_BASELINE_TS     = "baseline_ts"
    private const val KEY_BASELINE_TOTAL  = "baseline_total"
    private const val KEY_BASELINE_DFE    = "baseline_dfe"
}
