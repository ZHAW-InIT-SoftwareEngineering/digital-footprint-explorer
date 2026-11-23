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

import android.app.Activity
import android.content.Context
import androidx.core.content.edit
import ch.zhaw.digitalfootprintexplorer.model.GardenState
import kotlin.concurrent.thread

/**
 * The only entry point the rest of the app calls. Every call site is marked with `// STUDY:`,
 * README.md in this package lists them and explains how to remove the study features.
 */
object Study {

    private const val PREFS = "dfe_study"
    private const val KEY_LAST_OPEN_DAY = "last_open_day"

    /** Set when the activity is only recreated (rotation, dark mode, language), which is no new open. */
    @Volatile
    private var restartingForConfigChange = false

    /** DFEApplication.onCreate: keeps the daily check scheduled. */
    fun onProcessStart(context: Context) {
        StudyDailyCheck.schedule(context)
    }

    /** MainActivity.onStart: the app came to the foreground. */
    fun onActivityStarted(activity: Activity) {
        if (restartingForConfigChange) {
            restartingForConfigChange = false
            return
        }
        val context = activity.applicationContext
        thread(name = "study-open") {
            recordAppOpen(context)
            StudyDailyCheck.runIfNotDoneToday(context, source = "app_open")
        }
    }

    /** MainActivity.onStop */
    fun onActivityStopped(activity: Activity) {
        restartingForConfigChange = activity.isChangingConfigurations
    }

    /** DailyFootprintWorker, after a day was stored. Logs only, the calculation itself is untouched. */
    fun onCalculationStored(context: Context, day: String, calculatedAt: String, trigger: String) {
        StudyLog.append(context, StudyLog.EVENT_CALCULATION, "day=$day calculated_at=$calculatedAt trigger=$trigger")
    }

    /** False during the baseline phase: no push notification with the daily result. */
    fun isFeedbackActive(): Boolean = !StudyPhase.isBaseline()

    /** Garden state to show on the home screen and in the widget: STABLE during the baseline phase. */
    fun displayedGardenState(calculated: GardenState?, baseline: Boolean = StudyPhase.isBaseline()): GardenState? =
        StudyPhase.displayedGardenState(calculated, baseline)

    fun onWidgetAdded(context: Context) = StudyLog.append(context, StudyLog.EVENT_WIDGET_ADDED)

    fun onWidgetRemoved(context: Context, count: Int) =
        StudyLog.append(context, StudyLog.EVENT_WIDGET_REMOVED, "count=$count")

    private fun recordAppOpen(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val today = StudyPhase.today().toString()
        val firstOfDay = prefs.getString(KEY_LAST_OPEN_DAY, null) != today
        prefs.edit { putString(KEY_LAST_OPEN_DAY, today) }
        StudyLog.append(context, StudyLog.EVENT_APP_OPEN, "first_of_day=$firstOfDay")
    }
}
