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

package ch.zhaw.digitalfootprintexplorer.study

import kotlinx.datetime.DatePeriod
import kotlinx.datetime.LocalDate
import kotlinx.datetime.plus
import java.math.BigDecimal

/** One stored day as it is exported. Per-category and per-app values are deliberately not exported. */
data class ExportDay(
    val date: String,
    val appUsageKg: Double,
    val displayKg: Double,
    val backgroundKg: Double,
    val totalKg: Double,
    val gardenState: String,
    val baselineKg: Double,
    val calculatedAt: String
)

/** Builds the text files of the export. Pure functions, so they are unit tested without a device. */
object StudyExportFormat {

    const val DAILY_VALUES_FILE = "daily_values.csv"
    const val APP_OPENS_FILE = "app_opens_per_day.csv"
    const val STUDY_LOG_FILE = "study_log.txt"

    fun zipFileName(code: String) = "dfe-$code.zip"

    /** Adds the code before the extension, `daily_values.csv` becomes `daily_values-MA0732.csv`. */
    fun entryFileName(baseName: String, code: String): String {
        val dot = baseName.lastIndexOf('.')
        return if (dot < 0) "$baseName-$code" else "${baseName.substring(0, dot)}-$code${baseName.substring(dot)}"
    }

    /** garden_state is the calculated state, also during the baseline phase when the app shows STABLE. */
    fun dailyValuesCsv(days: List<ExportDay>): String = buildString {
        appendLine("date,app_usage_kg,display_kg,background_kg,total_kg,garden_state,baseline_kg,calculated_at")
        days.sortedBy { it.date }.forEach { d ->
            appendLine(
                listOf(
                    d.date, number(d.appUsageKg), number(d.displayKg), number(d.backgroundKg),
                    number(d.totalKg), d.gardenState, number(d.baselineKg), d.calculatedAt
                ).joinToString(",")
            )
        }
    }

    /**
     * One row per calendar day from [from] to [to] (both included) with the number of app opens, 0 if not opened.
     * Days before [from] with opens (e.g. a test before the study start) are included as well.
     */
    fun appOpensPerDayCsv(opensPerDay: Map<LocalDate, Int>, from: LocalDate, to: LocalDate): String = buildString {
        appendLine("date,opens")
        val first = (opensPerDay.keys + from).min()
        val last = (opensPerDay.keys + to).max()
        var day = first
        while (day <= last) {
            appendLine("$day,${opensPerDay[day] ?: 0}")
            day = day.plus(DatePeriod(days = 1))
        }
    }

    /** Full precision, a dot as decimal separator and no exponent (0.0001, not 1.0E-4). */
    private fun number(value: Double): String = BigDecimal.valueOf(value).stripTrailingZeros().toPlainString()
}
