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

import ch.zhaw.digitalfootprintexplorer.BuildConfig
import kotlinx.datetime.LocalDate

/**
 * Fixed values of the user study 2026. Everything study-specific lives in this package,
 * see README.md here for how to remove it after the study.
 *
 * What changes during the study (survey mode on/off, upload day) is not fixed here but read from
 * [CONFIG_URL], so the team can switch it without a new release.
 */
object StudyConfig {

    /**
     * Day 1 of the study. Only used for the app-opens export (one row per day from here on).
     * TODO(study): set the real start date before the release.
     */
    val START_DATE: LocalDate = LocalDate(2026, 12, 1)

    // Server values come from local.properties (not in git) via BuildConfig, see README.md "Vor dem Release".

    /** Remote switches `dfe_config.yaml`, see [StudyRemoteConfig]. Key STUDY_CONFIG_URL. */
    val CONFIG_URL: String = BuildConfig.STUDY_CONFIG_URL

    /** Upload endpoint `fileupload/upload.php`, see fileupload/README.md. Key STUDY_UPLOAD_URL. */
    val UPLOAD_URL: String = BuildConfig.STUDY_UPLOAD_URL

    /** Shared secret for [UPLOAD_URL]. Key STUDY_UPLOAD_SECRET. */
    val UPLOAD_SECRET: String = BuildConfig.STUDY_UPLOAD_SECRET

    /** The daily check runs at 00:30: reloads the config, checks widget/notifications, starts a due upload. */
    const val DAILY_CHECK_HOUR = 0
    const val DAILY_CHECK_MINUTE = 30

    /** Unique WorkManager name of the daily widget / notification check. */
    const val DAILY_CHECK_WORK_NAME = "study_daily_check"

    /** Unique WorkManager name of the automatic upload on the upload day. */
    const val UPLOAD_WORK_NAME = "study_upload"
}
