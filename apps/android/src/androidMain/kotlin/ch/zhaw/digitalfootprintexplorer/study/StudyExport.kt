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

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import ch.zhaw.digitalfootprintexplorer.DFEApplication
import ch.zhaw.digitalfootprintexplorer.R
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * Packs the study data into `dfe-<code>.zip` and hands it to a mail app, addressed to the study team.
 * The participant still taps "send" in the mail app: the app never sends anything by itself.
 */
object StudyExport {

    private const val EXPORT_DIR = "study_export"

    /** Reads database, log and open counts, so call it off the main thread. */
    fun createZip(context: Context, code: String): File {
        val days = readDays(context)
        val logLines = StudyLog.readLines(context)

        val dir = File(context.cacheDir, EXPORT_DIR).apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val zip = File(dir, StudyExportFormat.zipFileName(code))

        ZipOutputStream(zip.outputStream()).use { out ->
            fun entry(baseName: String, text: String) {
                out.putNextEntry(ZipEntry(StudyExportFormat.entryFileName(baseName, code)))
                out.write(text.toByteArray(Charsets.UTF_8))
                out.closeEntry()
            }
            entry(StudyExportFormat.DAILY_VALUES_FILE, StudyExportFormat.dailyValuesCsv(days))
            entry(
                StudyExportFormat.APP_OPENS_FILE,
                StudyExportFormat.appOpensPerDayCsv(Study.appOpensPerDay(context), StudyConfig.START_DATE, StudyPhase.today())
            )
            entry(StudyExportFormat.STUDY_LOG_FILE, logLines.joinToString("\n", postfix = "\n"))
        }
        return zip
    }

    /** Opens a mail app with recipient, subject, text and the ZIP attached; falls back to the share sheet. */
    fun sendByMail(context: Context, zip: File, code: String) {
        val uri: Uri = FileProvider.getUriForFile(context, authority(context), zip)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/zip"
            putExtra(Intent.EXTRA_EMAIL, arrayOf(StudyConfig.RECIPIENT))
            putExtra(Intent.EXTRA_SUBJECT, context.getString(R.string.study_mail_subject, code))
            putExtra(Intent.EXTRA_TEXT, context.getString(R.string.study_mail_body, code))
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri(zip.name, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        // The selector limits the choice to mail apps, the attachment travels with the ACTION_SEND intent.
        val mailOnly = Intent(send).apply { selector = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:")) }
        try {
            context.startActivity(mailOnly.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: ActivityNotFoundException) {
            val chooser = Intent.createChooser(send, context.getString(R.string.study_share_chooser))
            context.startActivity(chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    fun authority(context: Context) = "${context.packageName}.study.fileprovider"

    private fun readDays(context: Context): List<ExportDay> {
        val app = context.applicationContext as DFEApplication
        return app.database.dailyFootprintQueries.selectAll { date, total, appUsage, display, background,
                                                             calculatedAt, gardenState, baseline ->
            ExportDay(date, appUsage, display, background, total, gardenState, baseline, calculatedAt)
        }.executeAsList()
    }
}
