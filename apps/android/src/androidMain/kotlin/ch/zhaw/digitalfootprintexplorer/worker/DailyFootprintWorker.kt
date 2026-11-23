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

package ch.zhaw.digitalfootprintexplorer.worker

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.TelephonyManager
import android.util.Log
import kotlinx.coroutines.CancellationException
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import ch.zhaw.digitalfootprintexplorer.DFEApplication
import ch.zhaw.digitalfootprintexplorer.MainActivity
import ch.zhaw.digitalfootprintexplorer.model.DataPoint
import ch.zhaw.digitalfootprintexplorer.model.EmissionsCalculator
import ch.zhaw.digitalfootprintexplorer.model.GardenState
import ch.zhaw.digitalfootprintexplorer.model.input.BackgroundInput
import ch.zhaw.digitalfootprintexplorer.model.input.DisplayInput
import ch.zhaw.digitalfootprintexplorer.model.output.EmissionResult
import ch.zhaw.digitalfootprintexplorer.servicelayerplatform.service.InstalledAppProvider
import ch.zhaw.digitalfootprintexplorer.servicelayerplatform.service.MetricCollector
import ch.zhaw.digitalfootprintexplorer.servicelayerplatform.service.NetworkUsageDataSource
import ch.zhaw.digitalfootprintexplorer.R
import ch.zhaw.digitalfootprintexplorer.study.Study // STUDY:
import ch.zhaw.digitalfootprintexplorer.util.NEW_WORKER_NAME
import ch.zhaw.digitalfootprintexplorer.widget.GardenWidget
import kotlinx.datetime.Clock
import kotlinx.datetime.DatePeriod
import kotlinx.datetime.TimeZone
import kotlinx.datetime.minus
import kotlinx.datetime.toLocalDateTime
import java.util.Calendar
import java.util.concurrent.TimeUnit

const val KEY_DEBUG_SUMMARY = "debug_summary"

class DailyFootprintWorker(
    private val appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        // The periodic request carries no trigger, only runNow marks its runs.
        val trigger = inputData.getString(KEY_TRIGGER) ?: TRIGGER_PERIODIC
        val result = runAndLog(trigger)
        // Not reached when the system stops the run: WorkManager retries it, the pin follows that retry.
        if (trigger == TRIGGER_PERIODIC) pinNextRunTo3am()
        return result
    }

    private suspend fun runAndLog(trigger: String): Result = try {
        WorkerRunLog.append(appContext, "RUN_START", "trigger=$trigger attempt=$runAttemptCount")
        doWorkInternal(trigger)
    } catch (e: CancellationException) {
        // The system stopped the run (constraints, quota, doze, ...): keep the reason, then let it cancel.
        val reason = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) stopReason.toString() else "n/a"
        WorkerRunLog.append(appContext, "RUN_STOPPED", "stopReason=$reason")
        throw e
    } catch (e: Exception) {
        Log.e(TAG, "❌ Worker failed with exception", e)
        WorkerRunLog.append(appContext, "RUN_FAILED", "${e::class.simpleName}: ${e.message}")
        Result.failure(
            workDataOf(KEY_DEBUG_SUMMARY to "❌ ERROR: ${e::class.simpleName}: ${e.message}\n\n${e.stackTraceToString().take(800)}")
        )
    }

    /**
     * WorkManager counts the 24h period from the end of the last run, so every run that doze delayed
     * would push all following nights later (observed: 03:00 drifted to 07:57 within nine days). The
     * override is used for the next run only, hence it is set again after every periodic run.
     */
    private fun pinNextRunTo3am() {
        try {
            // At least an hour ahead, so a run that starts shortly before 3 AM is not repeated the same night.
            val nextRunMs = next3amAfter(System.currentTimeMillis() + TimeUnit.HOURS.toMillis(1))
            val request = PeriodicWorkRequestBuilder<DailyFootprintWorker>(24, TimeUnit.HOURS)
                .setId(id)
                .setNextScheduleTimeOverride(nextRunMs)
                .build()
            val outcome = WorkManager.getInstance(appContext).updateWork(request).get()
            val format = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US)
            WorkerRunLog.append(appContext, "NEXT_RUN_PINNED", "nextRun=${format.format(java.util.Date(nextRunMs))} result=$outcome")
        } catch (e: Exception) {
            Log.e(TAG, "Could not pin the next run to 3 AM", e)
            WorkerRunLog.append(appContext, "NEXT_RUN_PIN_FAILED", "${e::class.simpleName}: ${e.message}")
        }
    }

    private suspend fun doWorkInternal(trigger: String): Result {
        val startedAtMs = System.currentTimeMillis()
        val workerStartedAt = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())
            .format(java.util.Date(startedAtMs))
        Log.d(TAG, "▶ Worker started at $workerStartedAt")
        val app = appContext.applicationContext as DFEApplication

        val now = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
        val yesterday = now.date.minus(DatePeriod(days = 1))

        val alreadyCalculated = app.gardenStateCalculator.isDailyFootprintCalculated(yesterday)

        // do not re-run the calculation if it already calculated the footprint for yesterday
        if (alreadyCalculated) {
            Log.d(TAG, "Worker already ran for yesterday (${yesterday}) — skipping calculation")
            WorkerRunLog.append(appContext, "RUN_SKIPPED", "day=$yesterday already stored")
            return Result.success()
        }

        /* Calendar-day boundaries: yesterday 00:00 → today 00:00 */
        val (startTime, endTime) = yesterdayBoundaries()
        val fmt = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())
        Log.d(TAG, "📅 Calculating emissions for window [${fmt.format(java.util.Date(startTime))} → ${fmt.format(java.util.Date(endTime))}]")

        val subscriberId      = readSubscriberId()
        val usageStatsManager = appContext.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val networkMetrics    = MetricCollector(
            installedAppProvider   = InstalledAppProvider(),
            networkUsageDataSource = NetworkUsageDataSource(appContext),
            usageStatsManager      = usageStatsManager
        ).collectNetworkMetrics(appContext, startTime, endTime, subscriberId)

        val measuredApps  = networkMetrics.count { it.wifiBytes is DataPoint.Measured || it.cellularBytes is DataPoint.Measured }
        val totalWifiMB   = networkMetrics.sumOf { it.wifiBytes.valueOrDefault() } / 1_000_000.0
        val totalCellMB   = networkMetrics.sumOf { it.cellularBytes.valueOrDefault() } / 1_000_000.0
        Log.d(TAG, "📶 Network: ${networkMetrics.size} apps scanned, $measuredApps with data | WiFi ${f(totalWifiMB)} MB | Cellular ${f(totalCellMB)} MB")
        networkMetrics.forEach { app ->
            val wifiBytes  = app.wifiBytes.valueOrDefault()
            val cellBytes  = app.cellularBytes.valueOrDefault()
            val foregroundSec = app.totalForegroundTime
            val foregroundStr = when {
                foregroundSec >= 3600 -> "${foregroundSec / 3600}h ${(foregroundSec % 3600) / 60}min"
                foregroundSec >= 60   -> "${foregroundSec / 60}min ${foregroundSec % 60}s"
                foregroundSec >  0    -> "${foregroundSec}s"
                else                  -> "-"
            }
            Log.d(TAG, "   · ${app.appName} [${app.appCategory}] " +
                "wifi=${bytes(wifiBytes)} cell=${bytes(cellBytes)} total=${bytes(wifiBytes + cellBytes)} | time=$foregroundStr")
        }

        val displayInput = app.displayBrightnessObserver.collectAndReset(startTime, endTime)
        logDisplay(displayInput)

        val backgroundInput = app.backgroundProcessTracker.collectAndReset(startTime, endTime)
        logBackground(backgroundInput)

        val emissionResult = EmissionsCalculator().calculate(
            appUsage   = networkMetrics,
            display    = displayInput,
            background = backgroundInput
        )
        logEmissions(emissionResult)

        /* Garden state */
        val (gardenState, baseline) = app.gardenStateCalculator.calculateGardenState(emissionResult.ghgTotal)
        app.gardenStateCalculator.recordDailyFootprint(
            date              = yesterday,
            kgCO2e            = emissionResult.ghgTotal,
            ghgAppUsage       = emissionResult.ghgAppUsage,
            ghgDisplay        = emissionResult.ghgDisplay,
            ghgBackground     = emissionResult.ghgBackground,
            measuredAt        = now.toString(),
            gardenState       = gardenState,
            baselineKgCO2e    = baseline,
            categoryBreakdown = emissionResult.categoryBreakdown,
            appBreakdown      = emissionResult.appBreakdown
        )
        Log.d(TAG, "🌱 GardenState → $gardenState (${f(emissionResult.ghgTotal * 1000)} gCO₂e today, baseline ${f(baseline * 1000)} gCO₂e, measured at $now)")
        Study.onCalculationStored(appContext, yesterday.toString(), now.toString(), trigger) // STUDY:

        GardenWidget.updateState(appContext, gardenState)
        Log.d(TAG, "✅ Worker finished — widget updated")

        // STUDY: no notification during the baseline phase (days 1–7)
        if (Study.isFeedbackActive()) showDailyFootprintNotification(gardenState)

        WorkerRunLog.append(
            appContext, "RUN_DONE",
            "day=$yesterday total=${f(emissionResult.ghgTotal * 1000)}g " +
                "appUsage=${f(emissionResult.ghgAppUsage * 1000)}g " +
                "display=${f(emissionResult.ghgDisplay * 1000)}g " +
                "background=${f(emissionResult.ghgBackground * 1000)}g " +
                "baseline=${f(baseline * 1000)}g garden=$gardenState " +
                "apps=${networkMetrics.size} appsWithData=$measuredApps " +
                "wifi=${f(totalWifiMB)}MB cellular=${f(totalCellMB)}MB " +
                "displayIntervals=${displayInput.intervals.size} " +
                "backgroundProcesses=${backgroundInput.activeProcesses.size} " +
                "durationMs=${System.currentTimeMillis() - startedAtMs}"
        )

        return Result.success()
    }

    private fun logDisplay(display: DisplayInput) {
        val avgBrightness = if (display.intervals.isEmpty()) 0.0
            else display.intervals.sumOf { it.normalizedBrightness * it.durationH } /
                 display.intervals.sumOf { it.durationH }
        val totalH = display.intervals.sumOf { it.durationH }
        Log.d(TAG, "💡 Display: ${display.intervals.size} intervals, total ${f(totalH)}h, avg brightness ${f(avgBrightness * 100)}%")
        display.intervals.forEachIndexed { i, iv ->
            Log.d(TAG, "   · interval[$i] brightness=${f(iv.normalizedBrightness * 100)}% duration=${f(iv.durationH)}h")
        }
    }

    private fun logBackground(background: BackgroundInput) {
        if (background.activeProcesses.isEmpty()) {
            Log.d(TAG, "📍 Background: no active processes tracked")
        } else {
            background.activeProcesses.forEach { p ->
                Log.d(TAG, "📍 Background: ${p.process} active ${f(p.durationH.toDouble())}h")
            }
        }
    }

    private fun logEmissions(result: EmissionResult) {
        Log.d(TAG, "🔢 Emissions breakdown:")
        Log.d(TAG, "   · App usage : ${f(result.ghgAppUsage * 1000)} gCO₂e")
        Log.d(TAG, "   · Display   : ${f(result.ghgDisplay   * 1000)} gCO₂e")
        Log.d(TAG, "   · Background: ${f(result.ghgBackground * 1000)} gCO₂e")
        Log.d(TAG, "   · TOTAL     : ${f(result.ghgTotal      * 1000)} gCO₂e")
        result.categoryBreakdown.forEach { c ->
            Log.d(TAG, "   · [${c.category}] device=${f(c.ghgDevice*1000)}g net=${f(c.ghgNetwork*1000)}g backend=${f(c.ghgBackend*1000)}g")
        }
    }

    /** Formats with enough precision to show small values (e.g. 0.0024g instead of 0.00g). */
    private fun f(v: Double) = when {
        v == 0.0 -> "0.00"
        v < 0.01 -> "%.5f".format(v)
        v < 1.0  -> "%.4f".format(v)
        else     -> "%.2f".format(v)
    }

    /** Formats a byte count as KB / MB / GB depending on magnitude. */
    private fun bytes(b: Double) = when {
        b >= 1_000_000_000.0 -> "${"%.2f".format(b / 1_000_000_000.0)} GB"
        b >= 1_000_000.0     -> "${"%.2f".format(b / 1_000_000.0)} MB"
        b >= 1_000.0         -> "${"%.1f".format(b / 1_000.0)} KB"
        else                 -> "${b.toLong()} B"
    }

    @Suppress("DEPRECATION", "MissingPermission")
    private fun readSubscriberId(): String? = try {
        val tm = appContext.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        tm.subscriberId
    } catch (_: SecurityException) {
        null
    }

    /**
     * Returns the Unix-ms boundaries for yesterday's full calendar day:
     * yesterday 00:00:00.000 → today 00:00:00.000.
     */
    private fun yesterdayBoundaries(): Pair<Long, Long> {
        val todayMidnight = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val yesterdayMidnight = todayMidnight - TimeUnit.DAYS.toMillis(1)
        return yesterdayMidnight to todayMidnight
    }

    private fun showDailyFootprintNotification(gardenState: GardenState) {
        // Starting with Android 13 (Tiramisu), apps need the POST_NOTIFICATIONS permission to send notifications.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val permissionGranted = ContextCompat.checkSelfPermission(
                appContext,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED

            if (!permissionGranted) {
                Log.d(TAG, "Notification permission not granted")
                return
            }
        }
        val channelId = "daily_footprint"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Daily Footprint",
                NotificationManager.IMPORTANCE_DEFAULT
            )
            val manager = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }

        val intent = Intent(appContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent: PendingIntent = PendingIntent.getActivity(
            appContext,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val text = when(gardenState) {
            GardenState.FLOURISHING -> appContext.getString(R.string.notification_state_flourishing)
            GardenState.GROWING    -> appContext.getString(R.string.notification_state_growing)
            GardenState.STABLE    -> appContext.getString(R.string.notification_state_stable)
            GardenState.WILTING    -> appContext.getString(R.string.notification_state_wilting)
            GardenState.WITHERED   -> appContext.getString(R.string.notification_state_withered)
        }

        val notification = NotificationCompat.Builder(appContext, channelId)
            .setContentTitle(appContext.getString(R.string.notification_title))
            .setContentText(text)
            .setSmallIcon(R.drawable.garden_widget_preview)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        NotificationManagerCompat.from(appContext).notify(1001, notification)
    }

    companion object {
        const val TAG = "DFE_Worker"
        private const val KEY_TRIGGER = "trigger"
        private const val TRIGGER_PERIODIC = "periodic"
        private const val TRIGGER_APP_OPEN = "app_open"

        /**
         * Fallback method to trigger the worker immediately.
         */
        fun runNow(context: Context) {
            Log.d(TAG, "Enqueue immediate daily footprint worker")

            val request = OneTimeWorkRequestBuilder<DailyFootprintWorker>()
                .addTag(TAG)
                .setInputData(workDataOf(KEY_TRIGGER to TRIGGER_APP_OPEN))
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                "${NEW_WORKER_NAME}_IMMEDIATE",
                ExistingWorkPolicy.REPLACE,
                request
            )

        }

        /** [source] only names the caller in the worker log, e.g. "process_start" or "boot". */
        fun scheduleNext(context: Context, source: String) {
            val nowMs = System.currentTimeMillis()
            val delayMs = next3amAfter(nowMs) - nowMs

            Log.d(TAG, "Ensuring periodic worker: first run in ${delayMs}ms (3 AM), then every 24h")
            WorkerRunLog.append(
                context, "SCHEDULE",
                "source=$source policy=KEEP firstRunInMin=${TimeUnit.MILLISECONDS.toMinutes(delayMs)} (only used if no work exists yet)"
            )

            // A periodic request is re-armed by WorkManager itself and survives reboots. The former
            // self-rescheduling one-time chain was a no-op: KEEP ignores new work while the current run is
            // still active, so the chain ended after the first night.
            val request = PeriodicWorkRequestBuilder<DailyFootprintWorker>(24, TimeUnit.HOURS)
                .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                NEW_WORKER_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )
        }

        /** The first 3 AM local time strictly after [afterMs]. */
        internal fun next3amAfter(afterMs: Long): Long = Calendar.getInstance().apply {
            timeInMillis = afterMs
            set(Calendar.HOUR_OF_DAY, 3)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= afterMs) add(Calendar.DAY_OF_YEAR, 1)
        }.timeInMillis
    }
}
