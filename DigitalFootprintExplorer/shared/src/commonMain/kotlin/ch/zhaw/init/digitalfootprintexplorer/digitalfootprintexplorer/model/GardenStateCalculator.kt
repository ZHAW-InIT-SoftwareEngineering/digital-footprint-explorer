package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model

import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.database.DFEDatabase
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.output.CategoryEmission
import kotlinx.datetime.LocalDate

/**
 * Stores daily footprint history and calculates [GardenState]
 * by comparing today's value against a rolling baseline.
 *
 * Intended usage per day:
 *  1. Call [calculateGardenState] with today's kgCO₂e to get the state.
 *  2. Call [recordDailyFootprint] to persist today's value.
 *
 * Phase logic:
 *  - 0 entries stored   → Day 1, no comparison possible → STABLE
 *  - 1–6 entries stored → compare against average of all stored entries
 *  - ≥7 entries stored  → compare against average of the last 7 entries only
 */
class GardenStateCalculator(private val database: DFEDatabase) {

    /**
     * Persists a daily footprint entry and its per-category breakdown.
     * All entries are kept permanently — no rolling window deletion.
     *
     * @param date              The calendar day of the measurement.
     * @param kgCO2e            Total footprint used for baseline comparisons.
     * @param ghgAppUsage       CO₂e from app network/device usage [kgCO₂e].
     * @param ghgDisplay        CO₂e from screen energy [kgCO₂e].
     * @param ghgBackground     CO₂e from background processes [kgCO₂e].
     * @param measuredAt        ISO-8601 timestamp of when the measurement was taken.
     * @param gardenState       The garden state derived from this day's footprint.
     * @param baselineKgCO2e    The rolling baseline used to derive the garden state.
     * @param categoryBreakdown Per-category emission breakdown to store in DailyEmissionCategory.
     */
    fun recordDailyFootprint(
        date: LocalDate,
        kgCO2e: Double,
        ghgAppUsage: Double,
        ghgDisplay: Double,
        ghgBackground: Double,
        measuredAt: String,
        gardenState: GardenState,
        baselineKgCO2e: Double,
        categoryBreakdown: List<CategoryEmission>
    ) {
        val dateStr = date.toString()
        database.dailyFootprintQueries.insert(
            dateStr, kgCO2e, ghgAppUsage, ghgDisplay, ghgBackground, measuredAt,
            gardenState.name, baselineKgCO2e
        )
        categoryBreakdown.forEach { c ->
            database.dailyFootprintQueries.insertCategory(dateStr, c.category.name, c.ghgTotal)
        }
    }

    /**
     * Returns the [GardenState] and the baseline used for [todayFootprint].
     * Must be called *before* [recordDailyFootprint] for the same day so that
     * today's value is never included in its own baseline.
     *
     * @return Pair of (state, baselineKgCO2e). Baseline is 0.0 on day 1 (no history).
     */
    fun calculateGardenState(todayFootprint: Double): Pair<GardenState, Double> {
        val count = database.dailyFootprintQueries.count().executeAsOne()
        if (count == 0L) return GardenState.STABLE to 0.0
        val entries = if (count >= 7L) {
            database.dailyFootprintQueries.selectLatest7().executeAsList()
        } else {
            database.dailyFootprintQueries.selectAll().executeAsList()
        }
        val baseline = entries.map { it.total_kg }.average()
        return fromDeviation(todayFootprint, baseline) to baseline
    }

    /**
     * Returns the [GardenState] stored for the most recent day, or null if no entries exist.
     * Used to restore the widget state after demo mode is deactivated.
     */
    fun getLatestGardenState(): GardenState? {
        val latest = database.dailyFootprintQueries.selectLatest().executeAsOneOrNull()
        return latest?.garden_state?.let { runCatching { GardenState.valueOf(it) }.getOrNull() }
    }

    private fun fromDeviation(today: Double, baseline: Double): GardenState {
        val percentage = (today - baseline) / baseline
        return when {
            percentage <= -0.30 -> GardenState.FLOURISHING
            percentage <= -0.10 -> GardenState.GROWING
            percentage <   0.10 -> GardenState.STABLE
            percentage <=  0.40 -> GardenState.WILTING
            else                -> GardenState.WITHERED
        }
    }

}
