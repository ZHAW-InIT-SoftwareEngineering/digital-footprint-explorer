package ch.zhaw.digitalfootprintexplorer.study

import kotlinx.datetime.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals

class StudyRemoteConfigTest {

    @Test
    fun readsTheFileOnTheServer() = assertEquals(
        RemoteValues(survey = true, uploadDate = null),
        StudyRemoteConfig.parse(
            "# Should DFE go into survey mode? If true, show the garden in a neutral state.\n" +
                "# Possible values: true, false\n" +
                "survey: true"
        )
    )

    @Test
    fun readsFalseAndTheUploadDate() = assertEquals(
        RemoteValues(survey = false, uploadDate = LocalDate(2026, 12, 29)),
        StudyRemoteConfig.parse("survey: false\nupload_date: 2026-12-29\n")
    )

    @Test
    fun toleratesQuotesCaseCommentsAndWindowsLineEnds() = assertEquals(
        RemoteValues(survey = false, uploadDate = LocalDate(2026, 12, 29)),
        StudyRemoteConfig.parse("Survey: \"False\"  # switched on day 8\r\nupload_date: '2026-12-29'\r\n")
    )

    @Test
    fun unreadableValuesAreIgnored() = assertEquals(
        RemoteValues(survey = null, uploadDate = null),
        StudyRemoteConfig.parse("survey: yes\nupload_date: 29.12.2026\n")
    )

    @Test
    fun emptyOrHtmlGivesNothing() {
        assertEquals(RemoteValues(null, null), StudyRemoteConfig.parse(""))
        assertEquals(RemoteValues(null, null), StudyRemoteConfig.parse("<html><body>404</body></html>"))
    }
}
