/*
 * Copyright (C) 2026 Zurich University of Applied Sciences, Switzerland
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package ch.zhaw.digitalfootprintexplorer.study

import kotlinx.datetime.LocalDate

/**
 * Fixed values of the user study 2026. Everything study-specific lives in this package,
 * see README.md here for how to remove it after the study.
 */
object StudyConfig {

    /**
     * Day 1 of the study. All participants start on the same day.
     * TODO(study): set the real start date before the release.
     */
    val START_DATE: LocalDate = LocalDate(2026, 11, 24)

    /**
     * Days 1–7 are the baseline phase: the app records but shows no feedback.
     * TODO(study): local test with 2 days (24.–25.11.2026), set back to 7 before the release.
     */
    const val BASELINE_DAYS = 2

    /** Recipient of the exported study data, as stated in the participant information sheet. */
    const val RECIPIENT = "digital-footprint-explorer.init@zhaw.ch"

    /** The daily check runs at 00:30, so the widget switches right at the start of day 8. */
    const val DAILY_CHECK_HOUR = 0
    const val DAILY_CHECK_MINUTE = 30

    /** Unique WorkManager name of the daily widget / notification check. */
    const val DAILY_CHECK_WORK_NAME = "study_daily_check"
}
