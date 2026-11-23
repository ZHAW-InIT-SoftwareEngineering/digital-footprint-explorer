package ch.zhaw.digitalfootprintexplorer.study

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ParticipantCodeTest {

    @Test
    fun exampleFromTheDescriptionIsValid() = assertTrue(ParticipantCode.isValid("MA0732"))

    @Test
    fun normalizeUppercasesAndDropsSpaces() = assertEquals("MA0732", ParticipantCode.normalize(" ma 0732 "))

    @Test
    fun lowercaseIsOnlyValidAfterNormalizing() {
        assertFalse(ParticipantCode.isValid("ma0732"))
        assertTrue(ParticipantCode.isValid(ParticipantCode.normalize("ma0732")))
    }

    @Test
    fun tooShortIsInvalid() = assertFalse(ParticipantCode.isValid("MA073"))

    @Test
    fun tooLongIsInvalid() = assertFalse(ParticipantCode.isValid("MA07321"))

    @Test
    fun digitsAndLettersSwappedIsInvalid() = assertFalse(ParticipantCode.isValid("0732MA"))

    @Test
    fun umlautIsInvalidBecauseTheCodeIsAFileName() = assertFalse(ParticipantCode.isValid("ÜL0732"))

    @Test
    fun pathCharactersAreInvalid() = assertFalse(ParticipantCode.isValid("../073"))

    @Test
    fun emptyAndCorrectStartsShowNoErrorWhileTyping() {
        listOf("", "M", "MA", "MA0", "MA073", "MA0732").forEach {
            assertTrue(ParticipantCode.canBecomeValid(it), it)
        }
    }

    @Test
    fun wrongCharacterAtItsPositionIsAnErrorRightAway() {
        listOf("1", "M1", "MA0X", "MAB", "ÜL").forEach {
            assertFalse(ParticipantCode.canBecomeValid(it), it)
        }
    }
}
