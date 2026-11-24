package ch.zhaw.digitalfootprintexplorer.study

import kotlin.test.Test
import kotlin.test.assertEquals

class StudyExportFormatTest {

    @Test
    fun zipIsNamedAfterTheCode() = assertEquals("dfe-MA0732.zip", StudyExportFormat.zipFileName("MA0732"))

    @Test
    fun entriesGetTheCodeBeforeTheExtension() {
        assertEquals("daily_values-MA0732.csv", StudyExportFormat.entryFileName(StudyExportFormat.DAILY_VALUES_FILE, "MA0732"))
        assertEquals("app_opens_per_day-MA0732.csv", StudyExportFormat.entryFileName(StudyExportFormat.APP_OPENS_FILE, "MA0732"))
        assertEquals("study_log-MA0732.txt", StudyExportFormat.entryFileName(StudyExportFormat.STUDY_LOG_FILE, "MA0732"))
        assertEquals("notes-MA0732", StudyExportFormat.entryFileName("notes", "MA0732"))
    }

    @Test
    fun dailyValuesHaveOneSortedRowPerDayWithPlainNumbers() {
        val csv = StudyExportFormat.dailyValuesCsv(
            listOf(
                ExportDay("2026-12-02", 0.02, 0.005, 0.0001, 0.0251, "WILTING", 0.02, "2026-12-03T03:00:12.5"),
                ExportDay("2026-12-01", 0.01, 0.004, 0.0, 0.014, "STABLE", 0.0, "2026-12-02T05:16:26.1")
            )
        )
        assertEquals(
            "date,app_usage_kg,display_kg,background_kg,total_kg,garden_state,baseline_kg,calculated_at\n" +
                "2026-12-01,0.01,0.004,0,0.014,STABLE,0,2026-12-02T05:16:26.1\n" +
                "2026-12-02,0.02,0.005,0.0001,0.0251,WILTING,0.02,2026-12-03T03:00:12.5\n",
            csv
        )
    }

    @Test
    fun appOpensAreCountedPerDayFromTheLog() {
        val log = listOf(
            StudyLog.formatLine("2026-12-01 08:00:00", StudyLog.EVENT_APP_OPEN, "first_of_day=true"),
            StudyLog.formatLine("2026-12-01 09:30:00", StudyLog.EVENT_DAILY_CHECK, "widgets=1"),
            StudyLog.formatLine("2026-12-01 12:00:00", StudyLog.EVENT_APP_OPEN, "first_of_day=false"),
            StudyLog.formatLine("2026-12-03 07:10:00", StudyLog.EVENT_APP_OPEN, "first_of_day=true"),
            StudyLog.formatLine("2026-12-03 07:11:00", StudyLog.EVENT_CALCULATION, "day=2026-12-02 trigger=app_open")
        )
        assertEquals(
            "date,opens\n2026-12-01,2\n2026-12-03,1\n",
            StudyExportFormat.appOpensPerDayCsv(log)
        )
    }

    @Test
    fun emptyLogGivesHeaderOnly() = assertEquals("date,opens\n", StudyExportFormat.appOpensPerDayCsv(emptyList()))
}
