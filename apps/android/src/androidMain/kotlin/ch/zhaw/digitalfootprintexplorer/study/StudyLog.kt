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
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Study log, exported with the study data. Separate from the debug log `worker_log.txt`:
 * it stays in release builds and is never pruned during the study.
 *
 * One line per event: `yyyy-MM-dd HH:mm:ss | EVENT | key=value ...`
 *  - APP_OPEN          the app came to the foreground for the first time on that calendar day
 *  - DAILY_CHECK       widget and notification status, once per day
 *  - WIDGET_ADDED      the first garden widget was placed on the home screen
 *  - WIDGET_REMOVED    a garden widget was removed
 *  - CALCULATION       the worker stored a day (day, calculated_at, trigger=periodic|app_open)
 *  - CONFIG            remote config loaded the first time or changed (survey, upload_date)
 *  - CODE_CREATED      the participant code was generated
 *  - UPLOAD            the export was uploaded (source=auto|manual, server_file)
 *  - UPLOAD_FAILED     an upload attempt failed (source, reason)
 *  - WORKER_*          copy of every line of the worker debug log, e.g. WORKER_RUN_START, WORKER_RUN_SKIPPED,
 *                      WORKER_RUN_STOPPED, WORKER_RUN_FAILED, WORKER_RUN_DONE, WORKER_NEXT_RUN_PINNED,
 *                      WORKER_PROCESS_START, WORKER_PROCESS_EXIT, WORKER_WORK_STATE, with the device state
 */
object StudyLog {

    const val SEPARATOR = " | "
    const val EVENT_APP_OPEN = "APP_OPEN"
    const val EVENT_DAILY_CHECK = "DAILY_CHECK"
    const val EVENT_WIDGET_ADDED = "WIDGET_ADDED"
    const val EVENT_WIDGET_REMOVED = "WIDGET_REMOVED"
    const val EVENT_CALCULATION = "CALCULATION"
    const val EVENT_CONFIG = "CONFIG"
    const val EVENT_CODE_CREATED = "CODE_CREATED"
    const val EVENT_UPLOAD = "UPLOAD"
    const val EVENT_UPLOAD_FAILED = "UPLOAD_FAILED"
    const val WORKER_PREFIX = "WORKER_"

    private const val TAG = "DFE_StudyLog"
    private const val FILE_NAME = "study_log.txt"
    private const val TIMESTAMP_PATTERN = "yyyy-MM-dd HH:mm:ss"
    private val lock = Any()

    /** Appends one line. Never throws, a missing line must not break the app. */
    fun append(context: Context, event: String, details: String = "") {
        try {
            val timestamp = SimpleDateFormat(TIMESTAMP_PATTERN, Locale.US).format(Date())
            val line = formatLine(timestamp, event, details)
            synchronized(lock) { logFile(context).appendText(line + "\n") }
        } catch (e: Exception) {
            Log.e(TAG, "Could not write study log", e)
        }
    }

    fun readLines(context: Context): List<String> = synchronized(lock) {
        val file = logFile(context)
        if (file.exists()) file.readLines().filter { it.isNotBlank() } else emptyList()
    }

    internal fun formatLine(timestamp: String, event: String, details: String): String =
        listOf(timestamp, event, details).joinToString(SEPARATOR)

    private fun logFile(context: Context): File = File(context.filesDir, FILE_NAME)
}
