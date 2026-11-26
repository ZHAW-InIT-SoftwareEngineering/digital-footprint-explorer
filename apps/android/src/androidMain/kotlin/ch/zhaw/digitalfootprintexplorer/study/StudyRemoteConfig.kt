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
import androidx.core.content.edit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.datetime.LocalDate
import java.net.HttpURLConnection
import java.net.URL

/** Values of `dfe_config.yaml`. `null` = key missing or not readable. */
data class RemoteValues(val survey: Boolean?, val uploadDate: LocalDate?)

/**
 * Remote switches in the file at [StudyConfig.CONFIG_URL], so the team changes the phase on the server, not with a release:
 *
 * ```yaml
 * survey: true            # true: statistics tab hidden, no push notification, garden fixed STABLE
 * upload_date: 2026-12-29 # from this day on the app uploads the export once by itself
 * ```
 *
 * The last loaded values are kept, so offline the app keeps its last state. Before the first successful
 * load the app runs in survey mode (this build is only rolled out for the study) and does not upload by itself.
 */
object StudyRemoteConfig {

    private const val TAG = "DFE_StudyConfig"
    private const val PREFS = "dfe_study"
    private const val KEY_SURVEY = "config_survey"
    private const val KEY_UPLOAD_DATE = "config_upload_date"
    private const val TIMEOUT_MS = 10_000

    /** Survey mode before the config was ever loaded: on, the study build starts without feedback. */
    internal const val SURVEY_DEFAULT = true

    @Volatile
    private var surveyFlow: MutableStateFlow<Boolean>? = null

    /** Survey mode as last loaded; the UI collects it so a change shows up without restarting the app. */
    fun surveyMode(context: Context): StateFlow<Boolean> = flow(context).asStateFlow()

    fun isSurveyMode(context: Context): Boolean = flow(context).value

    fun uploadDate(context: Context): LocalDate? =
        prefs(context).getString(KEY_UPLOAD_DATE, null)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }

    /**
     * Loads the file and stores the values. Returns true if survey mode changed. Never throws: offline or a
     * broken file only keeps the last values. A key missing in the file keeps its last value as well.
     */
    suspend fun refresh(context: Context): Boolean = withContext(Dispatchers.IO) {
        val values = try {
            parse(download())
        } catch (e: Exception) {
            Log.w(TAG, "Could not load the remote config: ${e.message}")
            return@withContext false
        }
        val before = isSurveyMode(context)
        val beforeUploadDate = uploadDate(context)
        val firstLoad = !prefs(context).contains(KEY_SURVEY)
        prefs(context).edit(commit = true) {
            values.survey?.let { putBoolean(KEY_SURVEY, it) }
            values.uploadDate?.let { putString(KEY_UPLOAD_DATE, it.toString()) }
        }
        val after = values.survey ?: before
        val uploadDate = values.uploadDate ?: beforeUploadDate
        // Logged on the first load and on every change, so the log shows when each device switched phase.
        if (firstLoad || after != before || uploadDate != beforeUploadDate) {
            StudyLog.append(context, StudyLog.EVENT_CONFIG, "survey=$after upload_date=${uploadDate ?: "none"}")
        }
        flow(context).value = after
        after != before
    }

    /**
     * Minimal reader for flat `key: value` lines, enough for this file. `#` starts a comment, values may be
     * quoted. Unknown keys and unreadable values are ignored.
     */
    internal fun parse(text: String): RemoteValues {
        val map = text.lineSequence()
            .map { it.substringBefore('#').trim() }
            .filter { ':' in it }
            .associate { line ->
                line.substringBefore(':').trim().lowercase() to line.substringAfter(':').trim().trim('"', '\'')
            }
        val survey = when (map["survey"]?.lowercase()) {
            "true" -> true
            "false" -> false
            else -> null
        }
        val uploadDate = map["upload_date"]?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
        return RemoteValues(survey, uploadDate)
    }

    private fun download(): String {
        if (StudyConfig.CONFIG_URL.isBlank()) error("no config URL in this build")
        val connection = URL(StudyConfig.CONFIG_URL).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.useCaches = false
            connection.setRequestProperty("Cache-Control", "no-cache")
            val code = connection.responseCode
            if (code != HttpURLConnection.HTTP_OK) error("HTTP $code")
            return connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }

    private fun flow(context: Context): MutableStateFlow<Boolean> =
        surveyFlow ?: synchronized(this) {
            surveyFlow ?: MutableStateFlow(prefs(context).getBoolean(KEY_SURVEY, SURVEY_DEFAULT)).also { surveyFlow = it }
        }

    private fun prefs(context: Context) = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
