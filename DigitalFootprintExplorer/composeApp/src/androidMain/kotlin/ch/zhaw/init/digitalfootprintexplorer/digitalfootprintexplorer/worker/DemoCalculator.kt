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
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service.InstalledAppProvider

/**
 * Demo-mode emissions calculator.
 *
 * **Network tracking strategy:**
 * Tries per-UID [TrafficStats] deltas first so individual apps are visible.
 * Per-UID data is obtained via [InstalledAppProvider.getAllInstalledApps] which uses
 * [android.content.pm.PackageManager.getInstalledApplications] — this avoids the
 * Android 11+ package-visibility filtering that caused [queryIntentActivities] to
 * silently omit apps. If all per-UID deltas are zero (TrafficStats per-UID is
 * unavailable on the device), the calculation falls back to total device bytes
 * ([TrafficStats.getTotalRxBytes] / [TrafficStats.getTotalTxBytes]) minus the DFE
 * app's own traffic.
 *
 * **Baseline persistence:**
 * Total and DFE baseline values are persisted in SharedPreferences so they survive
 * process restarts (e.g. opening the app via widget click).
 * The per-UID map is kept in-memory only; after a process restart [restoreBaseline]
 * is called and the per-UID fallback kicks in automatically.
 *
 * **Display exclusion:**
 * Display is intentionally excluded — during a live demo the screen is always on,
 * making it a constant background noise that drowns out the app-usage signal.
 *
 * Does NOT write to the database — [DailyFootprintWorker] continues unaffected.
 */
object DemoCalculator {

    // ── Baseline state ────────────────────────────────────────────────────────

    /** Per-UID byte-counts at baseline. In-memory only; lost on process restart. */
    private var baselinePerUid: Map<Int, Long> = emptyMap()

    /** Total device bytes at baseline (rx+tx). Persisted. */
    private var baselineTotalBytes: Long = 0L

    /** DFE app bytes at baseline. Persisted (used in total fallback). */
    private var baselineDfeBytes: Long = 0L

    /** Timestamp of the last baseline snapshot. Persisted. */
    private var baselineTimestampMs: Long = 0L

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Captures a fresh baseline snapshot and persists it.
     * Call when the user actively toggles demo ON.
     */
    fun resetBaseline(context: Context) {
        val apps = InstalledAppProvider().getAllInstalledApps(context)
        val dfeUid = context.applicationInfo.uid
        baselinePerUid      = apps.associate { it.uid to trafficBytesForUid(it.uid) }
        baselineTotalBytes  = totalDeviceBytes()
        baselineDfeBytes    = trafficBytesForUid(dfeUid)
        baselineTimestampMs = System.currentTimeMillis()
        saveBaseline(context)
        Log.d(TAG, "🔄 Baseline gesetzt (${apps.size} Apps): ${fmtMs(baselineTimestampMs)}, " +
                "total=${fmtBytes(baselineTotalBytes)}")
    }

    /**
     * Restores the total/DFE baseline from SharedPreferences.
     * Call when the app is opened while demo was already active so that traffic
     * accumulated while the app was in the background is not lost.
     * The per-UID map is not persisted; on restore the total-bytes fallback is used.
     */
    fun restoreBaseline(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        baselineTimestampMs = prefs.getLong(KEY_BASELINE_TS,    0L)
        baselineTotalBytes  = prefs.getLong(KEY_BASELINE_TOTAL, 0L)
        baselineDfeBytes    = prefs.getLong(KEY_BASELINE_DFE,   0L)
        baselinePerUid      = emptyMap()   // not persisted; total fallback will be used
        Log.d(TAG, "♻ Baseline wiederhergestellt: ${fmtMs(baselineTimestampMs)} " +
                "(per-UID nicht verfügbar → Total-Fallback)")
    }

    /**
     * Clears all baseline state (memory + SharedPreferences).
     * Call when demo is toggled OFF so the next activation starts clean.
     */
    fun clearBaseline(context: Context) {
        baselinePerUid      = emptyMap()
        baselineTotalBytes  = 0L
        baselineDfeBytes    = 0L
        baselineTimestampMs = 0L
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_BASELINE_TS)
            .remove(KEY_BASELINE_TOTAL)
            .remove(KEY_BASELINE_DFE)
            .apply()
    }

    /**
     * Calculates emissions since the last [resetBaseline] / [calculate] call.
     *
     * @return Triple of [EmissionResult], [GardenState], and a formatted summary
     *         string (including per-app CO₂ breakdown if available) ready for display.
     */
    suspend fun calculate(context: Context): Triple<EmissionResult, GardenState, String> {
        val dfeApp            = context.applicationContext as DFEApplication
        val backgroundTracker: BackgroundProcessTracker = dfeApp.backgroundProcessTracker
        val dfeUid            = context.applicationInfo.uid

        val toMs   = System.currentTimeMillis()
        val fromMs = if (baselineTimestampMs > 0L) baselineTimestampMs
                     else toMs - DEFAULT_WINDOW_MS
        val windowSec = (toMs - fromMs) / 1_000.0

        Log.d(TAG, "▶ Demo-Berechnung gestartet")
        Log.d(TAG, "📅 Fenster: ${fmtMs(fromMs)} → ${fmtMs(toMs)} (%.1fs)".format(windowSec))

        // ── 1. Network delta ──────────────────────────────────────────────────
        val networkMetrics: List<AppUsageInput>
        val perAppLog: List<Pair<String, Long>>   // (displayLabel, deltaBytes) for logging

        if (baselinePerUid.isNotEmpty()) {
            // ── 1a. Per-UID via TrafficStats (preferred) ─────────────────────
            val apps = InstalledAppProvider().getAllInstalledApps(context)
            val perUidResults = apps
                .filter { it.uid != dfeUid }
                .mapNotNull { app ->
                    val current = trafficBytesForUid(app.uid)
                    val base    = baselinePerUid[app.uid] ?: current
                    val delta   = maxOf(0L, current - base)
                    if (delta == 0L) null
                    else Triple(app, current, delta)
                }
                .sortedByDescending { it.third }

            networkMetrics = perUidResults.map { (app, _, delta) ->
                AppUsageInput(
                    appName       = app.name,
                    appCategory   = app.category,
                    wifiBytes     = DataPoint.Measured(delta.toDouble()),
                    cellularBytes = DataPoint.Unavailable("not tracked in demo mode")
                )
            }
            perAppLog = perUidResults.map { (app, _, delta) ->
                "${app.name} [${app.category.name}]" to delta
            }

            // Update per-UID baseline for next press
            baselinePerUid = apps.associate { it.uid to trafficBytesForUid(it.uid) }

            Log.d(TAG, "📶 Netzwerk per App (${perUidResults.size} mit Traffic):")
            if (perUidResults.isEmpty()) {
                Log.d(TAG, "   (kein Traffic im Fenster)")
            } else {
                perUidResults.forEach { (app, _, delta) ->
                    Log.d(TAG, "   · ${app.name} [${app.category.name}]: ${fmtBytes(delta)}")
                }
            }

        } else {
            // ── 1b. Total-device fallback (after process restart) ────────────
            val currentTotal = totalDeviceBytes()
            val currentDfe   = trafficBytesForUid(dfeUid)
            val totalDelta   = maxOf(0L, currentTotal - baselineTotalBytes)
            val dfeDelta     = maxOf(0L, currentDfe   - baselineDfeBytes)
            val delta        = maxOf(0L, totalDelta   - dfeDelta)

            networkMetrics = if (delta > 0L) listOf(
                AppUsageInput(
                    appName       = "Gerät gesamt",
                    appCategory   = AppCategory.MISCELLANEOUS,
                    wifiBytes     = DataPoint.Measured(delta.toDouble()),
                    cellularBytes = DataPoint.Unavailable("not tracked in demo mode")
                )
            ) else emptyList()
            perAppLog = if (delta > 0L) listOf("Gerät gesamt (excl. DFE)" to delta) else emptyList()

            baselineTotalBytes = currentTotal
            baselineDfeBytes   = currentDfe

            Log.d(TAG, "📶 Netzwerk (Gesamt-Fallback — per-UID nach Prozess-Neustart nicht verfügbar):")
            Log.d(TAG, "   · Gesamt-Delta  : ${fmtBytes(totalDelta)}")
            Log.d(TAG, "   · DFE-App       : ${fmtBytes(dfeDelta)}  (abgezogen)")
            Log.d(TAG, "   · Netto         : ${fmtBytes(maxOf(0L, totalDelta - dfeDelta))}")
        }

        // ── 2. Persist updated baseline ───────────────────────────────────────
        baselineTimestampMs = toMs
        saveBaseline(context)

        // ── 3. Background processes ───────────────────────────────────────────
        val backgroundInput = backgroundTracker.peek(fromMs, toMs)
        if (backgroundInput.activeProcesses.isEmpty()) {
            Log.d(TAG, "📍 Hintergrundprozesse: keine aktiv")
        } else {
            Log.d(TAG, "📍 Hintergrundprozesse:")
            backgroundInput.activeProcesses.forEach { usage ->
                Log.d(TAG, "   · ${usage.process.name}: %.4fh".format(usage.durationH))
            }
        }

        // ── 4. Emissions ──────────────────────────────────────────────────────
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

        // ── 5. Summary string for UI ──────────────────────────────────────────
        val summary = buildSummary(result, gardenState, perAppLog, backgroundInput)

        return Triple(result, gardenState, summary)
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private fun buildSummary(
        result: EmissionResult,
        gardenState: GardenState,
        perAppLog: List<Pair<String, Long>>,
        backgroundInput: ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input.BackgroundInput
    ): String {
        fun f(v: Double) = "%.6f".format(v)
        val sb = StringBuilder()

        // Per-app network section
        if (perAppLog.isNotEmpty()) {
            sb.appendLine("── Apps ──")
            perAppLog.forEach { (label, _) ->
                // find matching emission from result — approximate by appUsage total
                sb.appendLine("· $label")
            }
            sb.appendLine("app  : ${f(result.ghgAppUsage * 1000)} gCO₂e")
        } else {
            sb.appendLine("app  : ${f(result.ghgAppUsage * 1000)} gCO₂e  (kein Traffic)")
        }

        // Background
        if (backgroundInput.activeProcesses.isNotEmpty()) {
            sb.appendLine("── Hintergrund ──")
            backgroundInput.activeProcesses.forEach { usage ->
                sb.appendLine("· ${usage.process.name}: %.4fh".format(usage.durationH))
            }
        }
        sb.appendLine("bg   : ${f(result.ghgBackground * 1000)} gCO₂e")

        sb.appendLine("─────────────")
        sb.appendLine("total: ${f(result.ghgTotal * 1000)} gCO₂e")
        sb.append("state: ${gardenState.name}")

        return sb.toString()
    }

    private fun saveBaseline(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_BASELINE_TS,    baselineTimestampMs)
            .putLong(KEY_BASELINE_TOTAL, baselineTotalBytes)
            .putLong(KEY_BASELINE_DFE,   baselineDfeBytes)
            .apply()
    }

    private fun trafficBytesForUid(uid: Int): Long {
        val rx = TrafficStats.getUidRxBytes(uid)
        val tx = TrafficStats.getUidTxBytes(uid)
        val validRx = if (rx == TrafficStats.UNSUPPORTED.toLong()) 0L else maxOf(0L, rx)
        val validTx = if (tx == TrafficStats.UNSUPPORTED.toLong()) 0L else maxOf(0L, tx)
        return validRx + validTx
    }

    private fun totalDeviceBytes(): Long {
        val rx = TrafficStats.getTotalRxBytes()
        val tx = TrafficStats.getTotalTxBytes()
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

    private const val DEFAULT_WINDOW_MS  = 30_000L
    private const val TAG                = "DFE_Demo"
    private const val PREFS_NAME         = "demo_calculator_prefs"
    private const val KEY_BASELINE_TS    = "baseline_ts"
    private const val KEY_BASELINE_TOTAL = "baseline_total"
    private const val KEY_BASELINE_DFE   = "baseline_dfe"
}
