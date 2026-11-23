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

package ch.zhaw.digitalfootprintexplorer.worker

import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals

class NextRunTest {
    private val originalZone = TimeZone.getDefault()
    private val format = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)

    @BeforeTest
    fun useZurichTime() {
        TimeZone.setDefault(TimeZone.getTimeZone("Europe/Zurich"))
        format.timeZone = TimeZone.getDefault()
    }

    @AfterTest
    fun restoreZone() = TimeZone.setDefault(originalZone)

    private fun next(after: String) = format.format(DailyFootprintWorker.next3amAfter(format.parse(after)!!.time))

    @Test
    fun lateRunPinsTomorrowAt3am() = assertEquals("2026-11-20 03:00:00", next("2026-11-19 07:57:51"))

    @Test
    fun beforeThreeStaysOnTheSameNight() = assertEquals("2026-11-19 03:00:00", next("2026-11-19 01:30:00"))

    @Test
    fun exactlyThreeMovesToTheNextNight() = assertEquals("2026-11-20 03:00:00", next("2026-11-19 03:00:00"))

    @Test
    fun keepsLocalThreeAcrossDstChange() = assertEquals("2027-03-28 03:00:00", next("2027-03-27 22:00:00"))
}
