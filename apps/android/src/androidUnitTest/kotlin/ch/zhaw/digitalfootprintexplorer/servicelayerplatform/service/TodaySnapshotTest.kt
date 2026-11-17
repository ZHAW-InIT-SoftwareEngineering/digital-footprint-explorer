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

package ch.zhaw.digitalfootprintexplorer.servicelayerplatform.service

import ch.zhaw.digitalfootprintexplorer.model.DayHistory
import kotlinx.datetime.LocalDate
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TodaySnapshotTest {
    private val date = LocalDate(2026, 10, 25)
    private val snapshot = TodaySnapshot(
        day = DayHistory(
            date = date,
            totalKg = 0.02,
            appUsageKg = 0.01,
            displayKg = 0.005,
            backgroundKg = 0.005,
            categories = emptyList()
        ),
        calculatedAtMs = 0L
    )

    @Test
    fun `shows the current day's estimate before it is saved`() {
        assertTrue(snapshot.isCurrentUnsavedDay(date, emptySet()))
    }

    @Test
    fun `keeps the saved day instead of the partial estimate`() {
        assertFalse(snapshot.isCurrentUnsavedDay(date, setOf(date)))
    }

    @Test
    fun `hides yesterday's partial estimate even if history is missing`() {
        assertFalse(snapshot.isCurrentUnsavedDay(LocalDate(2026, 10, 26), emptySet()))
    }
}
