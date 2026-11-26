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
import java.security.SecureRandom
import kotlin.random.Random
import kotlin.random.asKotlinRandom

/**
 * Personal participant code, generated once per installation, e.g. K7RX4M. It links questionnaires and
 * data file without a name: the app shows it on the Info tab and participants enter it in the questionnaires.
 * It is also the suffix of every file in the export ZIP.
 */
object ParticipantCode {

    /** No 0/O, 1/I/L, so the code can be read and typed without mix-ups. */
    internal const val ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    internal const val LENGTH = 6

    private const val PREFS = "dfe_study"
    private const val KEY_CODE = "participant_code"
    private val FORMAT = Regex("^[$ALPHABET]{$LENGTH}$")

    internal fun generate(random: Random = SecureRandom().asKotlinRandom()): String =
        String(CharArray(LENGTH) { ALPHABET[random.nextInt(ALPHABET.length)] })

    internal fun isValid(code: String): Boolean = FORMAT.matches(code)

    /** The stored code; creates and stores one on the first call. */
    @Synchronized
    fun getOrCreate(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.getString(KEY_CODE, null)?.takeIf { isValid(it) }?.let { return it }
        val code = generate()
        prefs.edit(commit = true) { putString(KEY_CODE, code) }
        StudyLog.append(context, StudyLog.EVENT_CODE_CREATED, "code=$code")
        return code
    }
}
