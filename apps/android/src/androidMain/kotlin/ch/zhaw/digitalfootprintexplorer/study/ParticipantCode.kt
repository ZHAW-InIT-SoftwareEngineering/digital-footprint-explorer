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

import android.content.Context
import androidx.core.content.edit

/**
 * Personal participant code: first two letters of the mother's first name, day of birth (two digits),
 * last two digits of the phone number, e.g. MA0732. It links questionnaires and data file without a name.
 */
object ParticipantCode {

    private val FORMAT = Regex("^[A-Z]{2}[0-9]{4}$")
    private const val PREFS = "dfe_study"
    private const val KEY_CODE = "participant_code"

    /** Upper case without spaces, so "ma 0732" and "MA0732" are the same code. */
    fun normalize(input: String): String = input.filterNot { it.isWhitespace() }.uppercase()

    /** Only A–Z and digits, the code is also used as file name. */
    fun isValid(code: String): Boolean = FORMAT.matches(code)

    /** True while typing a code that can still become valid ("M", "MA0"), so no error is shown yet. */
    fun canBecomeValid(input: String): Boolean = PREFIX.matches(input)

    private val PREFIX = Regex("^([A-Z]{0,2}|[A-Z]{2}[0-9]{0,4})$")

    fun load(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_CODE, "") ?: ""

    fun save(context: Context, code: String) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit { putString(KEY_CODE, code) }
}
