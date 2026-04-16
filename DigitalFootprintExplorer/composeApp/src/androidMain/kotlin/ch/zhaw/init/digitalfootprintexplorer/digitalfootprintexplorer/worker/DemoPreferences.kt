package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker

/**
 * Central definitions for all SharedPreferences file names and keys used by the demo mode.
 *
 * Both [DemoCalculator] (baseline tracking) and [DemoRepository] (UI state) use these
 * constants to avoid magic strings scattered across multiple files.
 */
internal object DemoPreferences {

    /** SharedPreferences file that holds UI-level demo state (active flag, last result). */
    const val PREFS_STATE_FILE      = "demo_prefs"

    /** SharedPreferences file that holds the traffic baseline snapshot. */
    const val PREFS_CALCULATOR_FILE = "demo_calculator_prefs"

    // ── UI state keys (in PREFS_STATE_FILE) ──────────────────────────────────
    const val KEY_ACTIVE            = "demo_active"
    const val KEY_GARDEN_STATE      = "demo_garden_state"
    const val KEY_SUMMARY           = "demo_summary"

    // ── Baseline keys (in PREFS_CALCULATOR_FILE) ─────────────────────────────
    const val KEY_BASELINE_TS       = "baseline_ts"
    const val KEY_BASELINE_TOTAL    = "baseline_total"
    const val KEY_BASELINE_DFE      = "baseline_dfe"
}
