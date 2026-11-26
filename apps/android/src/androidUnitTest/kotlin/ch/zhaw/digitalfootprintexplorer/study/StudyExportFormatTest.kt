package ch.zhaw.digitalfootprintexplorer.study

import kotlinx.datetime.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals

class StudyExportFormatTest {

    @Test
    fun zipNameIsRandomWithoutTheCode() = assertEquals(
        "123e4567e89b12d3a456426614174000.zip",
        StudyExportFormat.randomZipFileName(java.util.UUID.fromString("123e4567-e89b-12d3-a456-426614174000"))
    )

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
    fun everyDayFromStartToExportHasItsNumberOfOpens() = assertEquals(
        "date,opens\n2026-12-01,3\n2026-12-02,0\n2026-12-03,1\n2026-12-04,0\n",
        StudyExportFormat.appOpensPerDayCsv(
            mapOf(LocalDate(2026, 12, 3) to 1, LocalDate(2026, 12, 1) to 3),
            LocalDate(2026, 12, 1), LocalDate(2026, 12, 4)
        )
    )

    @Test
    fun opensBeforeTheStudyStartAreIncluded() = assertEquals(
        "date,opens\n2026-11-29,2\n2026-11-30,0\n2026-12-01,0\n",
        StudyExportFormat.appOpensPerDayCsv(
            mapOf(LocalDate(2026, 11, 29) to 2), LocalDate(2026, 12, 1), LocalDate(2026, 12, 1)
        )
    )

    @Test
    fun noOpensGivesZeroForEveryStudyDay() = assertEquals(
        "date,opens\n2026-12-01,0\n2026-12-02,0\n",
        StudyExportFormat.appOpensPerDayCsv(emptyMap(), LocalDate(2026, 12, 1), LocalDate(2026, 12, 2))
    )

    @Test
    fun exportBeforeTheStudyStartGivesHeaderOnly() = assertEquals(
        "date,opens\n",
        StudyExportFormat.appOpensPerDayCsv(emptyMap(), LocalDate(2026, 12, 1), LocalDate(2026, 11, 30))
    )
}
