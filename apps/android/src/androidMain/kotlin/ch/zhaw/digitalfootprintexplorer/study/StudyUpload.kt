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
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.datetime.LocalDate
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import java.util.concurrent.TimeUnit

/** [permanent]: retrying does not help (wrong secret, file too large, not a ZIP). */
class StudyUploadException(message: String, val permanent: Boolean) : IOException(message)

/**
 * Uploads the export ZIP to [StudyConfig.UPLOAD_URL] (`fileupload/upload.php` on main): multipart POST,
 * file in the field `file`, shared secret in the header `X-API-Key`.
 *
 * - Automatically: from `upload_date` in the remote config on, once, as WorkManager job that waits for a
 *   network connection and retries ([StudyUploadWorker]).
 * - Manually: button in the box "Share Data", as backup. Can be used any number of times.
 */
object StudyUpload {

    const val SOURCE_AUTO = "auto"
    const val SOURCE_MANUAL = "manual"

    internal const val TAG = "DFE_StudyUpload"
    private const val PREFS = "dfe_study"
    private const val KEY_LAST_UPLOAD_AT = "last_upload_at"
    private const val KEY_AUTO_UPLOAD_DONE_FOR = "auto_upload_done_for"
    private const val MAX_BYTES = 10L * 1024 * 1024

    /** Creates the ZIP, uploads it and deletes it again. Throws [IOException] on failure. */
    suspend fun uploadNow(context: Context, source: String): Unit = withContext(Dispatchers.IO) {
        val code = ParticipantCode.getOrCreate(context)
        val zip = StudyExport.createZip(context, code)
        try {
            val serverName = post(zip)
            StudyLog.append(context, StudyLog.EVENT_UPLOAD, "source=$source bytes=${zip.length()} server_file=$serverName")
            val uploadDate = StudyRemoteConfig.uploadDate(context)
            prefs(context).edit(commit = true) {
                putString(KEY_LAST_UPLOAD_AT, SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(Date()))
                // An upload on or after the upload day, also a manual one, is the one the study needs.
                if (uploadDate != null && isDue(StudyPhase.today(), uploadDate, doneFor = null)) {
                    putString(KEY_AUTO_UPLOAD_DONE_FOR, uploadDate.toString())
                }
            }
        } catch (e: IOException) {
            StudyLog.append(context, StudyLog.EVENT_UPLOAD_FAILED, "source=$source reason=${e.message}")
            throw e
        } finally {
            zip.delete()
        }
    }

    /** Local time of the last successful upload, "yyyy-MM-dd HH:mm", or null. */
    fun lastUploadAt(context: Context): String? = prefs(context).getString(KEY_LAST_UPLOAD_AT, null)

    /**
     * Starts the automatic upload if the upload day has come and there was no upload for it yet.
     * Called by the daily check and on every app open, after the remote config was refreshed.
     */
    fun scheduleIfDue(context: Context) {
        val uploadDate = StudyRemoteConfig.uploadDate(context) ?: return
        val doneFor = prefs(context).getString(KEY_AUTO_UPLOAD_DONE_FOR, null)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
        if (!isDue(StudyPhase.today(), uploadDate, doneFor)) return
        val request = OneTimeWorkRequestBuilder<StudyUploadWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.MINUTES)
            .build()
        // KEEP: a job that waits for the network or a retry is not replaced on every app open.
        WorkManager.getInstance(context)
            .enqueueUniqueWork(StudyConfig.UPLOAD_WORK_NAME, ExistingWorkPolicy.KEEP, request)
    }

    /** Due from [uploadDate] on, unless an upload for this upload day already succeeded. A new date in the config starts a new upload. */
    internal fun isDue(today: LocalDate, uploadDate: LocalDate, doneFor: LocalDate?): Boolean =
        today >= uploadDate && doneFor != uploadDate

    private fun post(zip: File): String {
        if (StudyConfig.UPLOAD_URL.isBlank()) throw StudyUploadException("no upload URL in this build", permanent = true)
        if (StudyConfig.UPLOAD_SECRET.isBlank()) throw StudyUploadException("no upload secret in this build", permanent = true)
        if (zip.length() > MAX_BYTES) throw StudyUploadException("file larger than 10 MB", permanent = true)

        val boundary = "dfe-" + UUID.randomUUID().toString()
        val connection = URL(StudyConfig.UPLOAD_URL).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 30_000
            connection.readTimeout = 120_000
            connection.doOutput = true
            connection.requestMethod = "POST"
            connection.setRequestProperty("X-API-Key", StudyConfig.UPLOAD_SECRET)
            connection.setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
            connection.outputStream.buffered().use { out ->
                out.write(
                    ("--$boundary\r\n" +
                        "Content-Disposition: form-data; name=\"file\"; filename=\"${zip.name}\"\r\n" +
                        "Content-Type: application/zip\r\n\r\n").toByteArray()
                )
                zip.inputStream().use { it.copyTo(out) }
                out.write("\r\n--$boundary--\r\n".toByteArray())
            }
            val status = connection.responseCode
            val body = (if (status < 400) connection.inputStream else connection.errorStream)
                ?.bufferedReader()?.use { it.readText() }.orEmpty()
            return when (status) {
                200 -> Regex("\"file\"\\s*:\\s*\"([^\"]+)\"").find(body)?.groupValues?.get(1) ?: "unknown"
                401 -> throw StudyUploadException("HTTP 401 wrong upload secret", permanent = true)
                413 -> throw StudyUploadException("HTTP 413 file too large", permanent = true)
                415 -> throw StudyUploadException("HTTP 415 not a ZIP", permanent = true)
                else -> throw StudyUploadException("HTTP $status ${body.take(100)}", permanent = false)
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun prefs(context: Context) = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

/** Automatic upload on the upload day. Waits for a network connection, retries server and network errors. */
class StudyUploadWorker(
    private val appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result = try {
        StudyUpload.uploadNow(appContext, StudyUpload.SOURCE_AUTO)
        Result.success()
    } catch (e: CancellationException) {
        throw e
    } catch (e: StudyUploadException) {
        Log.e(StudyUpload.TAG, "Upload failed", e)
        if (e.permanent) Result.failure() else Result.retry()
    } catch (e: Exception) {
        // Network errors, but also a failed export: try again later.
        Log.e(StudyUpload.TAG, "Upload failed", e)
        Result.retry()
    }
}
