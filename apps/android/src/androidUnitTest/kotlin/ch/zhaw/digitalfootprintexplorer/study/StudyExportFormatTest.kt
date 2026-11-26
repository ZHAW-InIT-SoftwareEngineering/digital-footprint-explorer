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

    private val categoryHeader =
        "video_streaming_kg,audio_streaming_kg,social_media_kg,messaging_kg,artificial_intelligence_kg," +
            "e_mail_kg,video_call_kg,gaming_kg,navigation_kg,miscellaneous_kg"

    @Test
    fun dailyValuesHaveOneSortedRowPerDayWithPlainNumbers() {
        val csv = StudyExportFormat.dailyValuesCsv(
            listOf(
                ExportDay("2026-12-02", 0.02, 0.005, 0.0001, 0.0251, "WILTING", 0.02, "2026-12-03T03:00:12.5"),
                ExportDay("2026-12-01", 0.01, 0.004, 0.0, 0.014, "STABLE", 0.0, "2026-12-02T05:16:26.1")
            )
        )
        assertEquals(
            "date,app_usage_kg,display_kg,background_kg,total_kg,garden_state,baseline_kg,calculated_at,$categoryHeader\n" +
                "2026-12-01,0.01,0.004,0,0.014,STABLE,0,2026-12-02T05:16:26.1,0,0,0,0,0,0,0,0,0,0\n" +
                "2026-12-02,0.02,0.005,0.0001,0.0251,WILTING,0.02,2026-12-03T03:00:12.5,0,0,0,0,0,0,0,0,0,0\n",
            csv
        )
    }

    @Test
    fun categoriesGoInTheirColumnAndMissingOnesAreZero() {
        val csv = StudyExportFormat.dailyValuesCsv(
            listOf(
                ExportDay(
                    "2026-12-01", 0.015, 0.004, 0.0, 0.019, "STABLE", 0.0, "2026-12-02T03:00:00",
                    mapOf("VIDEO_STREAMING" to 0.0125, "MISCELLANEOUS" to 0.0025)
                )
            )
        )
        assertEquals(
            "2026-12-01,0.015,0.004,0,0.019,STABLE,0,2026-12-02T03:00:00,0.0125,0,0,0,0,0,0,0,0,0.0025",
            csv.lines()[1]
        )
    }

    @Test
    fun unknownStoredCategoriesGetAnExtraColumnAtTheEnd() {
        val csv = StudyExportFormat.dailyValuesCsv(
            listOf(ExportDay("2026-12-01", 0.0, 0.0, 0.0, 0.0, "STABLE", 0.0, "t", mapOf("OLD_CATEGORY" to 0.001)))
        )
        assertEquals(true, csv.lines()[0].endsWith(",miscellaneous_kg,old_category_kg"))
        assertEquals(true, csv.lines()[1].endsWith(",0,0.001"))
    }

    @Test
    fun noDaysGivesHeaderOnlyWithAllCategoryColumns() = assertEquals(
        "date,app_usage_kg,display_kg,background_kg,total_kg,garden_state,baseline_kg,calculated_at,$categoryHeader\n",
        StudyExportFormat.dailyValuesCsv(emptyList())
    )

    @Test
    fun everyDayFromTheFirstOpenToExportHasItsNumberOfOpens() = assertEquals(
        "date,opens\n2026-12-01,3\n2026-12-02,0\n2026-12-03,1\n2026-12-04,0\n",
        StudyExportFormat.appOpensPerDayCsv(
            mapOf(LocalDate(2026, 12, 3) to 1, LocalDate(2026, 12, 1) to 3),
            LocalDate(2026, 12, 4)
        )
    )

    @Test
    fun exportOnTheDayOfTheLastOpenEndsThere() = assertEquals(
        "date,opens\n2026-11-29,2\n2026-11-30,0\n2026-12-01,1\n",
        StudyExportFormat.appOpensPerDayCsv(
            mapOf(LocalDate(2026, 11, 29) to 2, LocalDate(2026, 12, 1) to 1), LocalDate(2026, 12, 1)
        )
    )

    @Test
    fun noOpensGivesHeaderOnly() = assertEquals(
        "date,opens\n",
        StudyExportFormat.appOpensPerDayCsv(emptyMap(), LocalDate(2026, 12, 2))
    )
}
