package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model

import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.database.DFEDatabase
import kotlinx.datetime.LocalDate

/**
 * Stores up to 7 days of daily footprint history and calculates [GardenState]
 * by comparing today's value against the rolling baseline.
 *
 * Intended usage per day:
 *  1. Call [calculateGardenState] with today's kgCO₂e to get the state.
 *  2. Call [recordDailyFootprint] to persist today's value into the rolling window.
 *
 * Phase logic:
 *  - 0 entries stored  → Day 1, no comparison possible → STABLE
 *  - 1–6 entries stored → compare against average of all stored entries
 *  - 7 entries stored   → compare against rolling 7-day average (window maintained automatically)
 */
class GardenStateCalculator(private val database: DFEDatabase) {

    /**
     * Persists a daily footprint entry and trims the window to the 7 most recent days.
     *
     * @param date              The calendar day of the measurement.
     * @param kgCO2e            Total footprint used for baseline comparisons.
     * @param ghgAppUsage       CO₂e from app network/device usage [kgCO₂e].
     * @param ghgDisplay        CO₂e from screen energy [kgCO₂e].
     * @param ghgBackground     CO₂e from background processes [kgCO₂e].
     * @param measuredAt        ISO-8601 timestamp of when the measurement was taken.
     * @param gardenState       The garden state derived from this day's footprint.
     * @param baselineKgCO2e    The rolling baseline used to derive the garden state.
     */
    fun recordDailyFootprint(
        date: LocalDate,
        kgCO2e: Double,
        ghgAppUsage: Double,
        ghgDisplay: Double,
        ghgBackground: Double,
        measuredAt: String,
        gardenState: GardenState,
        baselineKgCO2e: Double
    ) {
        database.dailyFootprintQueries.insert(
            date.toString(), kgCO2e, ghgAppUsage, ghgDisplay, ghgBackground, measuredAt,
            gardenState.name, baselineKgCO2e
        )
        val count = database.dailyFootprintQueries.count().executeAsOne()
        if (count > 7L) {
            database.dailyFootprintQueries.deleteOldest()
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
        val entries = database.dailyFootprintQueries.selectAll().executeAsList()
        if (entries.isEmpty()) return GardenState.STABLE to 0.0
        val baseline = entries.map { it.kgCO2e }.average()
        return fromDeviation(todayFootprint, baseline) to baseline
    }

    /**
     * Returns the [GardenState] stored for the most recent day, or null if no entries exist.
     * Used to restore the widget state after demo mode is deactivated.
     */
    fun getLatestGardenState(): GardenState? {
        val latest = database.dailyFootprintQueries.selectLatest().executeAsOneOrNull()
        return latest?.gardenState?.let { runCatching { GardenState.valueOf(it) }.getOrNull() }
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
