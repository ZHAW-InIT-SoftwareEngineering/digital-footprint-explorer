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

package ch.zhaw.digitalfootprintexplorer.model

import kotlinx.datetime.DatePeriod
import kotlinx.datetime.LocalDate
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.minus

/** Emission of one app within a category [kgCO2e]. */
data class AppHistory(val appName: String, val totalKg: Double)

/** Emission of one category incl. the apps it consists of (may be empty for days recorded before app tracking). */
data class CategoryHistory(
    val category: AppCategory,
    val totalKg: Double,
    val apps: List<AppHistory>
)

/** One recorded calendar day. */
data class DayHistory(
    val date: LocalDate,
    val totalKg: Double,
    val appUsageKg: Double,
    val displayKg: Double,
    val backgroundKg: Double,
    val categories: List<CategoryHistory>
)

/** Sum of one or more [DayHistory] entries (a single day or a whole week). */
data class HistorySummary(
    val totalKg: Double,
    val appUsageKg: Double,
    val displayKg: Double,
    val backgroundKg: Double,
    val categories: List<CategoryHistory>
)

/** Monday of the week that contains this date. */
fun LocalDate.startOfWeek(): LocalDate = minus(DatePeriod(days = dayOfWeek.isoDayNumber - 1))

/**
 * Sums the given days. Categories and apps are merged and sorted by descending emission.
 */
fun List<DayHistory>.summarize(): HistorySummary {
    val categories = flatMap { it.categories }
        .groupBy { it.category }
        .map { (category, entries) ->
            CategoryHistory(
                category = category,
                totalKg = entries.sumOf { it.totalKg },
                apps = entries.flatMap { it.apps }
                    .groupBy { it.appName }
                    .map { (name, apps) -> AppHistory(name, apps.sumOf { it.totalKg }) }
                    .filter { it.totalKg > 0.0 }
                    .sortedByDescending { it.totalKg }
            )
        }
        .filter { it.totalKg > 0.0 }
        .sortedByDescending { it.totalKg }

    return HistorySummary(
        totalKg = sumOf { it.totalKg },
        appUsageKg = sumOf { it.appUsageKg },
        displayKg = sumOf { it.displayKg },
        backgroundKg = sumOf { it.backgroundKg },
        categories = categories
    )
}

/**
 * Average per recorded day (days without data do not count), or null for an empty list.
 * The categories are not part of the average.
 */
fun List<DayHistory>.dailyAverage(): HistorySummary? {
    if (isEmpty()) return null
    return HistorySummary(
        totalKg = sumOf { it.totalKg } / size,
        appUsageKg = sumOf { it.appUsageKg } / size,
        displayKg = sumOf { it.displayKg } / size,
        backgroundKg = sumOf { it.backgroundKg } / size,
        categories = emptyList()
    )
}
