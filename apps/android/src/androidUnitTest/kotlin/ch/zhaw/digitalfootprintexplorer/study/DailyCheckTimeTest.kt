package ch.zhaw.digitalfootprintexplorer.study

import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DailyCheckTimeTest {
    private val originalZone = TimeZone.getDefault()
    private val format = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)

    @BeforeTest
    fun useZurichTime() {
        TimeZone.setDefault(TimeZone.getTimeZone("Europe/Zurich"))
        format.timeZone = TimeZone.getDefault()
    }

    @AfterTest
    fun restoreZone() = TimeZone.setDefault(originalZone)

    private fun ms(text: String) = format.parse(text)!!.time
    private fun next(after: String) = format.format(StudyDailyCheck.nextRunAfter(ms(after)))

    @Test
    fun afternoonInstallRunsAtHalfPastMidnight() = assertEquals("2026-11-24 00:30:00", next("2026-11-23 15:53:24"))

    @Test
    fun justAfterMidnightStaysOnTheSameNight() = assertEquals("2026-11-24 00:30:00", next("2026-11-24 00:05:00"))

    @Test
    fun exactlyHalfPastMovesToTheNextNight() = assertEquals("2026-11-25 00:30:00", next("2026-11-24 00:30:00"))

    @Test
    fun keepsLocalTimeAcrossDstChange() = assertEquals("2027-03-28 00:30:00", next("2027-03-27 22:00:00"))

    @Test
    fun recognisesWorkPlannedAtHalfPastMidnight() = assertTrue(StudyDailyCheck.isPlannedAtCheckTime(ms("2026-11-24 00:30:00")))

    @Test
    fun workPlannedInTheAfternoonIsMoved() = assertFalse(StudyDailyCheck.isPlannedAtCheckTime(ms("2026-11-24 15:53:24")))
}
