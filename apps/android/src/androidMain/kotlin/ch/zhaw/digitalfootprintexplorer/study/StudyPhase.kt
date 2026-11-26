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

import ch.zhaw.digitalfootprintexplorer.model.GardenState
import kotlinx.datetime.Clock
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.todayIn

/**
 * Survey mode (baseline phase): the app records but shows no feedback. It is switched on the server,
 * see [StudyRemoteConfig]. Only what is displayed changes. Calculation, storage and the garden baseline
 * run as usual.
 */
object StudyPhase {

    /** In survey mode every screen shows the neutral STABLE garden instead of the calculated one. */
    fun displayedGardenState(calculated: GardenState?, survey: Boolean): GardenState? =
        if (survey) GardenState.STABLE else calculated

    fun today(): LocalDate = Clock.System.todayIn(TimeZone.currentSystemDefault())
}
