package ch.zhaw.digitalfootprintexplorer.study

import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ParticipantCodeTest {

    @Test
    fun generatedCodesHaveSixReadableCharacters() {
        val random = Random(42)
        repeat(1000) {
            val code = ParticipantCode.generate(random)
            assertEquals(6, code.length, code)
            assertTrue(ParticipantCode.isValid(code), code)
        }
    }

    @Test
    fun alphabetHasNoLookAlikes() {
        listOf('0', 'O', '1', 'I', 'L').forEach { assertFalse(it in ParticipantCode.ALPHABET, "$it") }
    }

    @Test
    fun codesDiffer() {
        val random = Random(7)
        val codes = List(1000) { ParticipantCode.generate(random) }.toSet()
        assertEquals(1000, codes.size)
    }

    @Test
    fun oldHandWrittenCodesAreInvalidAndGetReplaced() {
        assertFalse(ParticipantCode.isValid("MA0732"))
        assertFalse(ParticipantCode.isValid("k7rx4m"))
        assertFalse(ParticipantCode.isValid("../K7R"))
    }
}
