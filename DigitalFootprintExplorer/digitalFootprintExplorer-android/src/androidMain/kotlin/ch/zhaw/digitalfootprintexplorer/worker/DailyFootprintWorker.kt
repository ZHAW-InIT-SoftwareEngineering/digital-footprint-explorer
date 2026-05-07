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
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
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

    override suspend fun doWork(): Result = try {
        doWorkInternal()
    } catch (e: Exception) {
        Log.e(TAG, "❌ Worker failed with exception", e)
        Result.failure(
            workDataOf(KEY_DEBUG_SUMMARY to "❌ ERROR: ${e::class.simpleName}: ${e.message}\n\n${e.stackTraceToString().take(800)}")
        )
    }

    private suspend fun doWorkInternal(): Result {
        val workerStartedAt = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())
            .format(java.util.Date())
        Log.d(TAG, "▶ Worker started at $workerStartedAt")
        val app = appContext.applicationContext as DFEApplication

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
        val now = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
        val yesterday = now.date.minus(DatePeriod(days = 1))
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
            categoryBreakdown = emissionResult.categoryBreakdown
        )
        Log.d(TAG, "🌱 GardenState → $gardenState (${f(emissionResult.ghgTotal * 1000)} gCO₂e today, baseline ${f(baseline * 1000)} gCO₂e, measured at $now)")

        GardenWidget.updateState(appContext, gardenState)
        Log.d(TAG, "✅ Worker finished — widget updated")

        val textForNotification = when(gardenState) {
            GardenState.FLOURISHING -> appContext.getString(R.string.notification_state_flourishing)
            GardenState.GROWING    -> appContext.getString(R.string.notification_state_growing)
            GardenState.STABLE    -> appContext.getString(R.string.notification_state_stable)
            GardenState.WILTING    -> appContext.getString(R.string.notification_state_wilting)
            GardenState.WITHERED   -> appContext.getString(R.string.notification_state_withered)
        }

        showDailyFootprintNotification(textForNotification)

        //reschedule the next worker
        scheduleNext(appContext)

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

    private fun showDailyFootprintNotification(text: String) {
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

        val notification = NotificationCompat.Builder(appContext, channelId)
            .setContentTitle(appContext.getString(R.string.notification_title))
            .setContentText(text)
            .setSmallIcon(R.drawable.garden_widget_preview)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        NotificationManagerCompat.from(appContext).notify(1001, notification)
    }

    companion object {
        const val TAG = "DFE_Worker"

        fun scheduleNext(context: Context) {
            val now = Calendar.getInstance()

            val next3am = Calendar.getInstance().apply {
                timeInMillis = now.timeInMillis
                set(Calendar.HOUR_OF_DAY, 3)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)

                if (!after(now)) {
                    add(Calendar.DAY_OF_YEAR, 1)
                }
            }

            var delayMs = next3am.timeInMillis - now.timeInMillis

            // Sanity check: the delay should be between 0 and 24h, but in case of any clock issues we clamp it to 25h to avoid scheduling a worker far in the future or with a negative delay.
            val maxDelayMs = TimeUnit.HOURS.toMillis(25)
            if (delayMs !in 1..maxDelayMs) {
                Log.w(TAG, "Computed delay $delayMs ms looks wrong — clamping to 24h")
                delayMs = TimeUnit.HOURS.toMillis(24)
            }

            Log.d(TAG, "Rescheduling worker: delay=${delayMs}ms until 3 AM next time")

            val request = OneTimeWorkRequestBuilder<DailyFootprintWorker>()
                .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                NEW_WORKER_NAME,
                ExistingWorkPolicy.KEEP,
                request
            )
        }
    }
}
