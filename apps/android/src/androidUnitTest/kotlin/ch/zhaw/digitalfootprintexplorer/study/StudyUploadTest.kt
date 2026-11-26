package ch.zhaw.digitalfootprintexplorer.study

import kotlinx.datetime.LocalDate
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class StudyUploadTest {

    private val uploadDay = LocalDate(2026, 12, 29)

    @Test
    fun notDueBeforeTheUploadDay() = assertFalse(StudyUpload.isDue(LocalDate(2026, 12, 28), uploadDay, doneFor = null))

    @Test
    fun dueOnTheUploadDay() = assertTrue(StudyUpload.isDue(uploadDay, uploadDay, doneFor = null))

    @Test
    fun stillDueLaterIfItHasNotWorkedYet() = assertTrue(StudyUpload.isDue(LocalDate(2027, 1, 5), uploadDay, doneFor = null))

    @Test
    fun notDueAgainAfterASuccessfulUpload() = assertFalse(StudyUpload.isDue(LocalDate(2026, 12, 30), uploadDay, doneFor = uploadDay))

    @Test
    fun aNewUploadDayInTheConfigStartsANewUpload() =
        assertTrue(StudyUpload.isDue(LocalDate(2027, 1, 10), LocalDate(2027, 1, 10), doneFor = uploadDay))
}
