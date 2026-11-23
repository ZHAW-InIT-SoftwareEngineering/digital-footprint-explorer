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

import android.Manifest
import android.app.NotificationManager
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import ch.zhaw.digitalfootprintexplorer.DFEApplication
import ch.zhaw.digitalfootprintexplorer.widget.GardenWidget
import ch.zhaw.digitalfootprintexplorer.widget.GardenWidgetReceiver
import android.util.Log
import androidx.work.WorkInfo
import java.util.Calendar
import kotlin.concurrent.thread
import java.util.concurrent.TimeUnit

/**
 * Once per day: is the garden widget on the home screen, and may the app post notifications?
 * Runs as its own periodic work, independent of the nightly footprint worker, and also when the app
 * is opened on a day without a check yet.
 */
object StudyDailyCheck {

    private const val TAG = "DFE_StudyCheck"
    private const val PREFS = "dfe_study"
    private const val KEY_LAST_CHECK_DAY = "last_daily_check_day"

    /** The notification channel the nightly worker posts its result to. */
    private const val FOOTPRINT_CHANNEL_ID = "daily_footprint"

    /**
     * First run at the next 00:30, so the widget switches right at the start of the first feedback day.
     * Work that already exists but is not planned for 00:30 is moved there. Queries WorkManager, so it
     * runs on its own thread.
     */
    fun schedule(context: Context) {
        val appContext = context.applicationContext
        thread(name = "study-check-schedule") {
            try {
                val workManager = WorkManager.getInstance(appContext)
                val existing = workManager.getWorkInfosForUniqueWork(StudyConfig.DAILY_CHECK_WORK_NAME).get()
                    .filter { it.state == WorkInfo.State.ENQUEUED }
                if (existing.isEmpty()) {
                    val nowMs = System.currentTimeMillis()
                    val request = PeriodicWorkRequestBuilder<StudyDailyCheckWorker>(24, TimeUnit.HOURS)
                        .setInitialDelay(nextRunAfter(nowMs) - nowMs, TimeUnit.MILLISECONDS)
                        .build()
                    workManager.enqueueUniquePeriodicWork(
                        StudyConfig.DAILY_CHECK_WORK_NAME,
                        ExistingPeriodicWorkPolicy.KEEP,
                        request
                    )
                } else {
                    existing.filterNot { isPlannedAtCheckTime(it.nextScheduleTimeMillis) }
                        .forEach { pinNextRun(appContext, it.id, earliestMs = System.currentTimeMillis()) }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Could not schedule the daily check", e)
            }
        }
    }

    internal fun isPlannedAtCheckTime(timeMs: Long): Boolean = Calendar.getInstance().run {
        timeInMillis = timeMs
        get(Calendar.HOUR_OF_DAY) == StudyConfig.DAILY_CHECK_HOUR && get(Calendar.MINUTE) == StudyConfig.DAILY_CHECK_MINUTE
    }

    /**
     * WorkManager counts the 24 h from the end of the last run, so a run delayed by doze would push all
     * later ones. Same fix as the nightly worker: after every run the next one is set to 00:30 again.
     * By default at least an hour ahead, so a run shortly before 00:30 is not repeated the same night.
     */
    fun pinNextRun(
        context: Context,
        workId: java.util.UUID,
        earliestMs: Long = System.currentTimeMillis() + TimeUnit.HOURS.toMillis(1)
    ) {
        try {
            val nextRunMs = nextRunAfter(earliestMs)
            val request = PeriodicWorkRequestBuilder<StudyDailyCheckWorker>(24, TimeUnit.HOURS)
                .setId(workId)
                .setNextScheduleTimeOverride(nextRunMs)
                .build()
            WorkManager.getInstance(context).updateWork(request).get()
        } catch (e: Exception) {
            Log.e(TAG, "Could not pin the next daily check", e)
        }
    }

    /** The first [StudyConfig.DAILY_CHECK_HOUR]:[StudyConfig.DAILY_CHECK_MINUTE] local time strictly after [afterMs]. */
    internal fun nextRunAfter(afterMs: Long): Long = Calendar.getInstance().apply {
        timeInMillis = afterMs
        set(Calendar.HOUR_OF_DAY, StudyConfig.DAILY_CHECK_HOUR)
        set(Calendar.MINUTE, StudyConfig.DAILY_CHECK_MINUTE)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
        if (timeInMillis <= afterMs) add(Calendar.DAY_OF_YEAR, 1)
    }.timeInMillis

    fun runIfNotDoneToday(context: Context, source: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (prefs.getString(KEY_LAST_CHECK_DAY, null) == StudyPhase.today().toString()) return
        run(context, source)
    }

    fun run(context: Context, source: String) {
        val widgets = widgetCount(context)
        val notificationsEnabled = NotificationManagerCompat.from(context).areNotificationsEnabled()
        StudyLog.append(
            context, StudyLog.EVENT_DAILY_CHECK,
            "source=$source widgets=$widgets widget_installed=${widgets > 0} " +
                "notifications_enabled=$notificationsEnabled " +
                "notification_permission=${notificationPermission(context)} " +
                "footprint_channel=${footprintChannelImportance(context)}"
        )
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit { putString(KEY_LAST_CHECK_DAY, StudyPhase.today().toString()) }
    }

    private fun widgetCount(context: Context): Int = try {
        AppWidgetManager.getInstance(context)
            .getAppWidgetIds(ComponentName(context, GardenWidgetReceiver::class.java)).size
    } catch (_: Exception) {
        -1
    }

    private fun notificationPermission(context: Context): String =
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) "not_required"
        else if (ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED) "granted"
        else "denied"

    /** "missing" until the worker posted its first notification, the channel is created there. */
    private fun footprintChannelImportance(context: Context): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return "not_required"
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = manager.getNotificationChannel(FOOTPRINT_CHANNEL_ID) ?: return "missing"
        return if (channel.importance == NotificationManager.IMPORTANCE_NONE) "blocked"
        else "importance_${channel.importance}"
    }
}

class StudyDailyCheckWorker(
    private val appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        StudyDailyCheck.run(appContext, source = "worker")
        // Redraws the widget so it switches from the neutral baseline garden on day 8 without opening the app.
        val app = appContext.applicationContext as DFEApplication
        app.gardenStateCalculator.getLatestGardenState()?.let { GardenWidget.updateState(appContext, it) }
        StudyDailyCheck.pinNextRun(appContext, id)
        return Result.success()
    }
}
