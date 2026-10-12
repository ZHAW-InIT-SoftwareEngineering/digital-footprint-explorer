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

import ch.zhaw.digitalfootprintexplorer.model.input.AppUsageInput
import ch.zhaw.digitalfootprintexplorer.model.input.BackgroundInput
import ch.zhaw.digitalfootprintexplorer.model.input.DisplayInput
import kotlinx.datetime.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals

class FootprintHistoryTest {

    @Test
    fun `week starts on monday`() {
        // 2026-10-05 is a Monday, 2026-10-11 a Sunday
        assertEquals(LocalDate(2026, 10, 5), LocalDate(2026, 10, 5).startOfWeek())
        assertEquals(LocalDate(2026, 10, 5), LocalDate(2026, 10, 11).startOfWeek())
        assertEquals(LocalDate(2026, 9, 28), LocalDate(2026, 10, 4).startOfWeek())
    }

    @Test
    fun `app breakdown adds up to category and total app usage`() {
        val apps = listOf(
            AppUsageInput("YouTube", AppCategory.VIDEO_STREAMING, 1800, 1_000_000_000.0.let { DataPoint.Measured(it) }, DataPoint.Measured(0.0)),
            AppUsageInput("Netflix", AppCategory.VIDEO_STREAMING, 3600, DataPoint.Measured(2_000_000_000.0), DataPoint.Measured(5e8)),
            AppUsageInput("Signal", AppCategory.MESSAGING, 600, DataPoint.Measured(1e7), DataPoint.Measured(0.0))
        )
        val result = EmissionsCalculator().calculate(apps, DisplayInput(emptyList()), BackgroundInput(emptyList()))

        assertEquals(3, result.appBreakdown.size)
        assertEquals(result.ghgAppUsage, result.appBreakdown.sumOf { it.ghgTotal }, 1e-12)
        result.categoryBreakdown.forEach { c ->
            assertEquals(c.ghgTotal, result.appBreakdown.filter { it.category == c.category }.sumOf { it.ghgTotal }, 1e-12)
        }
    }

    @Test
    fun `summarize merges categories and apps across days`() {
        fun day(d: Int, yt: Double, signal: Double) = DayHistory(
            date = LocalDate(2026, 10, d), totalKg = yt + signal + 1.0, appUsageKg = yt + signal,
            displayKg = 0.5, backgroundKg = 0.5,
            categories = listOf(
                CategoryHistory(AppCategory.VIDEO_STREAMING, yt, listOf(AppHistory("YouTube", yt))),
                CategoryHistory(AppCategory.MESSAGING, signal, listOf(AppHistory("Signal", signal)))
            )
        )

        val summary = listOf(day(5, 1.0, 0.25), day(6, 3.0, 0.25)).summarize()

        assertEquals(6.5, summary.totalKg, 1e-12)
        assertEquals(4.5, summary.appUsageKg, 1e-12)
        assertEquals(AppCategory.VIDEO_STREAMING, summary.categories.first().category)
        assertEquals(4.0, summary.categories.first().totalKg, 1e-12)
        assertEquals(listOf(AppHistory("YouTube", 4.0)), summary.categories.first().apps)
    }

    @Test
    fun `daily average only counts recorded days`() {
        fun day(d: Int, usage: Double) = DayHistory(
            date = LocalDate(2026, 10, d), totalKg = usage + 1.0, appUsageKg = usage,
            displayKg = 0.5, backgroundKg = 0.5, categories = emptyList()
        )
        assertEquals(null, emptyList<DayHistory>().dailyAverage())

        val average = listOf(day(5, 2.0), day(6, 4.0)).dailyAverage()!!
        assertEquals(4.0, average.totalKg, 1e-12)
        assertEquals(3.0, average.appUsageKg, 1e-12)
        assertEquals(0.5, average.displayKg, 1e-12)
        assertEquals(0.5, average.backgroundKg, 1e-12)
    }

    @Test
    fun `summarize drops categories and apps without emission`() {
        val day = DayHistory(
            date = LocalDate(2026, 10, 12), totalKg = 1.0, appUsageKg = 1.0,
            displayKg = 0.0, backgroundKg = 0.0,
            categories = listOf(
                CategoryHistory(AppCategory.MESSAGING, 1.0, listOf(AppHistory("Signal", 1.0), AppHistory("Telegram", 0.0))),
                CategoryHistory(AppCategory.E_MAIL, 0.0, listOf(AppHistory("Gmail", 0.0)))
            )
        )

        val summary = listOf(day).summarize()

        assertEquals(listOf(AppCategory.MESSAGING), summary.categories.map { it.category })
        assertEquals(listOf("Signal"), summary.categories.single().apps.map { it.appName })
    }
}
