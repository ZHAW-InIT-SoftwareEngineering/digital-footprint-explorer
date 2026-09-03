/*
 * Copyright (C) 2026 Zurich University of Applied Sciences, Switzerland
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package ch.zhaw.digitalfootprintexplorer.demo

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

    /** ── UI state keys (in PREFS_STATE_FILE) */
    const val KEY_ACTIVE            = "demo_active"
    const val KEY_GARDEN_STATE      = "demo_garden_state"
    const val KEY_SUMMARY           = "demo_summary"

    /** ── Baseline keys (in PREFS_CALCULATOR_FILE) */
    const val KEY_BASELINE_TS       = "baseline_ts"
    const val KEY_BASELINE_TOTAL    = "baseline_total"
    const val KEY_BASELINE_DFE      = "baseline_dfe"
}
