package ch.zhaw.digitalfootprintexplorer.study

import ch.zhaw.digitalfootprintexplorer.model.GardenState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class StudyPhaseTest {

    @Test
    fun surveyShowsStable() =
        assertEquals(GardenState.STABLE, StudyPhase.displayedGardenState(GardenState.WITHERED, survey = true))

    @Test
    fun surveyShowsStableBeforeTheFirstCalculation() =
        assertEquals(GardenState.STABLE, StudyPhase.displayedGardenState(null, survey = true))

    @Test
    fun withoutSurveyShowsCalculatedState() =
        assertEquals(GardenState.WILTING, StudyPhase.displayedGardenState(GardenState.WILTING, survey = false))

    @Test
    fun withoutSurveyKeepsMissingState() = assertNull(StudyPhase.displayedGardenState(null, survey = false))
}
