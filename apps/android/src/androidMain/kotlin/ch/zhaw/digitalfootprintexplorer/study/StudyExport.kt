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
import ch.zhaw.digitalfootprintexplorer.DFEApplication
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * Packs the study data into a ZIP with a random name. Every file inside carries the participant code before
 * the extension, e.g. `daily_values-K7RX4M.csv`. Uploaded by [StudyUpload].
 */
object StudyExport {

    private const val EXPORT_DIR = "study_export"

    /** Reads database, log and open counts, so call it off the main thread. Removes older export files. */
    fun createZip(context: Context, code: String): File {
        val days = readDays(context)
        val logLines = StudyLog.readLines(context)

        val dir = File(context.cacheDir, EXPORT_DIR).apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val zip = File(dir, StudyExportFormat.randomZipFileName())

        ZipOutputStream(zip.outputStream()).use { out ->
            fun entry(baseName: String, text: String) {
                out.putNextEntry(ZipEntry(StudyExportFormat.entryFileName(baseName, code)))
                out.write(text.toByteArray(Charsets.UTF_8))
                out.closeEntry()
            }
            entry(StudyExportFormat.DAILY_VALUES_FILE, StudyExportFormat.dailyValuesCsv(days))
            entry(
                StudyExportFormat.APP_OPENS_FILE,
                StudyExportFormat.appOpensPerDayCsv(Study.appOpensPerDay(context), StudyPhase.today())
            )
            entry(StudyExportFormat.STUDY_LOG_FILE, logLines.joinToString("\n", postfix = "\n"))
        }
        return zip
    }

    private fun readDays(context: Context): List<ExportDay> {
        val queries = (context.applicationContext as DFEApplication).database.dailyFootprintQueries
        val categoriesByDate = queries.selectAllCategories().executeAsList()
            .groupBy({ it.date }, { it.category to it.total_kg })
            .mapValues { (_, values) -> values.toMap() }
        return queries.selectAll { date, total, appUsage, display, background, calculatedAt, gardenState, baseline ->
            ExportDay(date, appUsage, display, background, total, gardenState, baseline, calculatedAt,
                categoriesByDate[date].orEmpty())
        }.executeAsList()
    }
}
