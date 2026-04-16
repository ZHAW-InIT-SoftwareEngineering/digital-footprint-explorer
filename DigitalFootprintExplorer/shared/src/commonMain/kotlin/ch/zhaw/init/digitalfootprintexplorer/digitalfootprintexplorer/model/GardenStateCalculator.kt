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
     * @param date           The calendar day of the measurement.
     * @param kgCO2e         Total footprint used for baseline comparisons.
     * @param ghgAppUsage    CO₂e from app network/device usage [kgCO₂e].
     * @param ghgDisplay     CO₂e from screen energy [kgCO₂e].
     * @param ghgBackground  CO₂e from background processes [kgCO₂e].
     * @param measuredAt     ISO-8601 timestamp of when the measurement was taken.
     */
    fun recordDailyFootprint(
        date: LocalDate,
        kgCO2e: Double,
        ghgAppUsage: Double,
        ghgDisplay: Double,
        ghgBackground: Double,
        measuredAt: String
    ) {
        database.dailyFootprintQueries.insert(
            date.toString(), kgCO2e, ghgAppUsage, ghgDisplay, ghgBackground, measuredAt
        )
        val count = database.dailyFootprintQueries.count().executeAsOne()
        if (count > 7L) {
            database.dailyFootprintQueries.deleteOldest()
        }
    }

    /**
     * Returns the [GardenState] for [todayFootprint] relative to the stored baseline.
     * Must be called *before* [recordDailyFootprint] for the same day so that
     * today's value is never included in its own baseline.
     */
    fun calculateGardenState(todayFootprint: Double): GardenState {
        val entries = database.dailyFootprintQueries.selectAll().executeAsList()
        if (entries.isEmpty()) return GardenState.STABLE
        val baseline = entries.map { it.kgCO2e }.average()
        return fromDeviation(todayFootprint, baseline)
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

    /**
     * Demo-mode variant: evaluates [kgCO2e] against absolute thresholds calibrated for a
     * 30-second measurement window instead of comparing against a 7-day baseline.
     *
     * Does not read from or write to the database.
     *
     * Thresholds may need calibration by observing the values printed in the demo summary
     * on the target device and adjusting accordingly.
     */
    fun calculateDemoGardenState(kgCO2e: Double): GardenState = when {
        kgCO2e < DEMO_THRESHOLD_FLOURISHING -> GardenState.FLOURISHING
        kgCO2e < DEMO_THRESHOLD_GROWING     -> GardenState.GROWING
        kgCO2e < DEMO_THRESHOLD_STABLE      -> GardenState.STABLE
        kgCO2e < DEMO_THRESHOLD_WILTING     -> GardenState.WILTING
        else                                -> GardenState.WITHERED
    }

    companion object {
        // Demo thresholds [kgCO2e per 30-second window].
        // Calibrate by running the demo and checking the emitted kgCO2e in the summary card.
        private const val DEMO_THRESHOLD_FLOURISHING = 5e-6   // screen off / near-idle
        private const val DEMO_THRESHOLD_GROWING     = 2e-5   // screen on, dim, no apps
        private const val DEMO_THRESHOLD_STABLE      = 3.5e-5 // screen on, light use
        private const val DEMO_THRESHOLD_WILTING     = 5.5e-5 // active app / AI use
        // > DEMO_THRESHOLD_WILTING → WITHERED
    }
}
