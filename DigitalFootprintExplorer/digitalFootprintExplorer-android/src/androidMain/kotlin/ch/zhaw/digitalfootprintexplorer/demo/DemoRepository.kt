package ch.zhaw.digitalfootprintexplorer.demo

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import ch.zhaw.digitalfootprintexplorer.DFEApplication
import ch.zhaw.digitalfootprintexplorer.model.GardenState
import ch.zhaw.digitalfootprintexplorer.model.output.EmissionResult
import ch.zhaw.digitalfootprintexplorer.widget.GardenWidget
import kotlinx.coroutines.CancellationException

/**
 * Single source of truth for demo mode UI state.
 *
 * Owns all SharedPreferences access for the demo UI (active flag, last garden state,
 * last summary text) and delegates measurement logic to [DemoCalculator].
 *
 * Intended to be created once per [androidx.compose.runtime.Composable] lifetime via
 * `remember { DemoRepository(context) }`.
 */
class DemoRepository(private val appContext: Context) {

    private val prefs: SharedPreferences =
        appContext.getSharedPreferences(DemoPreferences.PREFS_STATE_FILE, Context.MODE_PRIVATE)

    /** True if demo was already active when this repository was created (e.g. after app restart). */
    val wasActiveOnStart: Boolean = prefs.getBoolean(DemoPreferences.KEY_ACTIVE, false)

    /** Last persisted summary text, or null if no result has been calculated yet. */
    fun loadSummary(): String? = prefs.getString(DemoPreferences.KEY_SUMMARY, null)

    /**
     * Activates demo mode: takes a fresh traffic baseline and clears any previous result.
     * Call when the user toggles demo ON.
     */
    fun activate() {
        DemoCalculator.resetBaseline(appContext)
        prefs.edit {
            putBoolean(DemoPreferences.KEY_ACTIVE, true)
            remove(DemoPreferences.KEY_GARDEN_STATE)
            remove(DemoPreferences.KEY_SUMMARY)
        }
    }

    /**
     * Deactivates demo mode: clears the baseline and all persisted results, then restores
     * the widget to the last garden state recorded by the real daily worker (if available).
     * Call when the user toggles demo OFF.
     */
    suspend fun deactivate() {
        DemoCalculator.clearBaseline(appContext)
        prefs.edit {
            putBoolean(DemoPreferences.KEY_ACTIVE, false)
            remove(DemoPreferences.KEY_GARDEN_STATE)
            remove(DemoPreferences.KEY_SUMMARY)
        }
        val app = appContext.applicationContext as DFEApplication
        val realState = app.gardenStateCalculator.getLatestGardenState()
        if (realState != null) GardenWidget.updateState(appContext, realState)
    }

    /**
     * Calculates emissions since the last baseline, updates the widget, and persists
     * the result so it survives activity restarts.
     *
     * @return Pair of the raw [EmissionResult] and the derived [GardenState].
     * @throws CancellationException if the coroutine is cancelled (never swallowed).
     * @throws Exception for any other calculation failure (caller should handle/log).
     */
    suspend fun refresh(): Pair<EmissionResult, GardenState> {
        val (result, gardenState) = DemoCalculator.calculate(appContext)
        GardenWidget.updateState(appContext, gardenState)
        prefs.edit {
            putString(DemoPreferences.KEY_GARDEN_STATE, gardenState.name)
            putString(DemoPreferences.KEY_SUMMARY, buildSummary(result, gardenState.name))
        }
        return result to gardenState
    }

    /**
     * Builds the monospace summary string shown below the refresh button.
     * Display is excluded from the demo calculation (always-on screen is constant
     * noise that masks the app-usage signal), so it is not shown here.
     */
    fun buildSummary(result: EmissionResult, stateName: String): String {
        fun f(v: Double) = "%.6f".format(v)
        return """
app  : ${f(result.ghgAppUsage   * 1000)} gCO₂e
bg   : ${f(result.ghgBackground * 1000)} gCO₂e
total: ${f(result.ghgTotal      * 1000)} gCO₂e
state: $stateName
        """.trimIndent()
    }
}
