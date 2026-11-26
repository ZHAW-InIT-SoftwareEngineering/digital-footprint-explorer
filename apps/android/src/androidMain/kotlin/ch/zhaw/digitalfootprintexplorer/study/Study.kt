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
import ch.zhaw.digitalfootprintexplorer.widget.GardenWidget
import androidx.glance.appwidget.updateAll
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.datetime.LocalDate

/**
 * The only entry point the rest of the app calls. Every call site is marked with `// STUDY:`,
 * README.md in this package lists them and explains how to remove the study features.
 */
object Study {

    /** Separate file: one key per calendar day ("2026-11-24"), the value is the number of opens that day. */
    private const val PREFS_OPENS = "dfe_study_opens"

    /** Set when the activity is only recreated (rotation, dark mode, language), which is no new open. */
    @Volatile
    private var restartingForConfigChange = false

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** DFEApplication.onCreate: keeps the daily check scheduled and creates the participant code. */
    fun onProcessStart(context: Context) {
        StudyDailyCheck.schedule(context)
        scope.launch { ParticipantCode.getOrCreate(context.applicationContext) }
    }

    /** MainActivity.onStart: the app came to the foreground. */
    fun onActivityStarted(activity: Activity) {
        if (restartingForConfigChange) {
            restartingForConfigChange = false
            return
        }
        val context = activity.applicationContext
        scope.launch {
            recordAppOpen(context)
            refreshConfig(context)
            StudyUpload.scheduleIfDue(context)
            StudyDailyCheck.runIfNotDoneToday(context, source = "app_open")
        }
    }

    /**
     * Loads the remote config. If survey mode changed, the widget is redrawn; the app UI follows by itself
     * through [surveyMode].
     */
    suspend fun refreshConfig(context: Context) {
        if (StudyRemoteConfig.refresh(context)) GardenWidget().updateAll(context)
    }

    /** True while the server says survey mode: no statistics tab, no push notification, garden fixed STABLE. */
    fun surveyMode(context: Context): StateFlow<Boolean> = StudyRemoteConfig.surveyMode(context)

    fun isSurveyMode(context: Context): Boolean = StudyRemoteConfig.isSurveyMode(context)

    /** MainActivity.onStop */
    fun onActivityStopped(activity: Activity) {
        restartingForConfigChange = activity.isChangingConfigurations
    }

    /** Number of app opens per calendar day, for the export. */
    fun appOpensPerDay(context: Context): Map<LocalDate, Int> =
        context.getSharedPreferences(PREFS_OPENS, Context.MODE_PRIVATE).all
            .mapNotNull { (day, count) ->
                val date = runCatching { LocalDate.parse(day) }.getOrNull()
                if (date != null && count is Int) date to count else null
            }
            .toMap()

    /** DailyFootprintWorker, after a day was stored. Logs only, the calculation itself is untouched. */
    fun onCalculationStored(context: Context, day: String, calculatedAt: String, trigger: String) {
        StudyLog.append(context, StudyLog.EVENT_CALCULATION, "day=$day calculated_at=$calculatedAt trigger=$trigger")
    }

    /**
     * DailyFootprintWorker, before the push notification: false in survey mode. Reloads the config first,
     * so a switch on the server counts the same night.
     */
    suspend fun isFeedbackActive(context: Context): Boolean {
        refreshConfig(context)
        return !isSurveyMode(context)
    }

    /** Garden state to show on the home screen and in the widget: STABLE in survey mode. */
    fun displayedGardenState(calculated: GardenState?, survey: Boolean): GardenState? =
        StudyPhase.displayedGardenState(calculated, survey)

    /**
     * WorkerRunLog.append: every line of the debug log `worker_log.txt` (runs, skips, stops, failures, pinned
     * next run, process starts and exits, WorkManager state, each with the device state) also goes into the
     * study log. The debug log keeps only 30 days and is not exported, the study log keeps everything.
     */
    fun onWorkerLog(context: Context, event: String, details: String, deviceState: String) =
        StudyLog.append(context, StudyLog.WORKER_PREFIX + event, listOf(details, deviceState).filter { it.isNotBlank() }.joinToString(" "))

    fun onWidgetAdded(context: Context) = StudyLog.append(context, StudyLog.EVENT_WIDGET_ADDED)

    fun onWidgetRemoved(context: Context, count: Int) =
        StudyLog.append(context, StudyLog.EVENT_WIDGET_REMOVED, "count=$count")

    /** Counts every open; only the first open of a calendar day goes into the study log as APP_OPEN. */
    @Synchronized
    private fun recordAppOpen(context: Context) {
        val opens = context.getSharedPreferences(PREFS_OPENS, Context.MODE_PRIVATE)
        val today = StudyPhase.today().toString()
        val count = opens.getInt(today, 0) + 1
        opens.edit(commit = true) { putInt(today, count) }
        if (count == 1) StudyLog.append(context, StudyLog.EVENT_APP_OPEN)
    }
}
