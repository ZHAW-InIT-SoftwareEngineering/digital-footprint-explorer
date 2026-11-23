package ch.zhaw.digitalfootprintexplorer.study

import ch.zhaw.digitalfootprintexplorer.model.GardenState
import kotlinx.datetime.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class StudyPhaseTest {
    private val start = LocalDate(2026, 12, 1)

    // The study uses 7 days; StudyConfig may hold a shorter value for local tests.
    private val studyDays = 7

    @Test
    fun feedbackStartsOnDayEight() = assertEquals(LocalDate(2026, 12, 8), StudyPhase.feedbackStartDate(start, studyDays))

    @Test
    fun dayOneIsBaseline() = assertTrue(StudyPhase.isBaseline(LocalDate(2026, 12, 1), start, studyDays))

    @Test
    fun daySevenIsBaseline() = assertTrue(StudyPhase.isBaseline(LocalDate(2026, 12, 7), start, studyDays))

    @Test
    fun dayEightIsNotBaseline() = assertFalse(StudyPhase.isBaseline(LocalDate(2026, 12, 8), start, studyDays))

    @Test
    fun daysBeforeTheStartAreBaseline() = assertTrue(StudyPhase.isBaseline(LocalDate(2026, 11, 28), start, studyDays))

    @Test
    fun baselineShowsStable() =
        assertEquals(GardenState.STABLE, StudyPhase.displayedGardenState(GardenState.WITHERED, baseline = true))

    @Test
    fun baselineShowsStableBeforeTheFirstCalculation() =
        assertEquals(GardenState.STABLE, StudyPhase.displayedGardenState(null, baseline = true))

    @Test
    fun afterBaselineShowsCalculatedState() =
        assertEquals(GardenState.WILTING, StudyPhase.displayedGardenState(GardenState.WILTING, baseline = false))

    @Test
    fun afterBaselineKeepsMissingState() = assertNull(StudyPhase.displayedGardenState(null, baseline = false))
}
