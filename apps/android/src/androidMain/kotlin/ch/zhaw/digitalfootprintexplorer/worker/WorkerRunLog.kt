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

import android.app.ActivityManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.work.WorkInfo
import androidx.work.WorkManager
import ch.zhaw.digitalfootprintexplorer.util.NEW_WORKER_NAME
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/**
 * Persistent protocol of everything that concerns [DailyFootprintWorker]: process starts, scheduling,
 * every run with its trigger and result. Logcat is a ring buffer and does not survive a night or a
 * reboot, this file does.
 *
 * A run that did not happen cannot log itself: it shows as a night without a RUN_START line. The
 * device state attached to every line and the PROCESS_EXIT / WORK_STATE lines written on the next
 * process start are the hints for why.
 *
 * The file lives in the app specific external directory, so it can be pulled over USB from any build:
 * `adb pull /sdcard/Android/data/ch.zhaw.digitalfootprintexplorer/files/worker_log.txt`
 */
object WorkerRunLog {

    private const val TAG = "DFE_WorkerLog"
    private const val FILE_NAME = "worker_log.txt"
    private const val RETENTION_DAYS = 30L
    private const val SEPARATOR = " | "
    private const val TIMESTAMP_PATTERN = "yyyy-MM-dd HH:mm:ss"
    private const val PREFS_NAME = "dfe_prefs"
    private const val KEY_LAST_EXIT_LOGGED = "worker_log_last_exit_ms"

    private val lock = Any()

    /** Appends one line and drops every line older than [RETENTION_DAYS]. Never throws. */
    fun append(context: Context, event: String, details: String = "") {
        try {
            val format = SimpleDateFormat(TIMESTAMP_PATTERN, Locale.US)
            val now = System.currentTimeMillis()
            val line = listOf(format.format(Date(now)), event, details, deviceState(context))
                .joinToString(SEPARATOR)

            synchronized(lock) {
                val file = logFile(context)
                val cutoff = now - TimeUnit.DAYS.toMillis(RETENTION_DAYS)
                val kept = if (file.exists()) {
                    file.readLines().filter { old ->
                        val writtenAt = runCatching { format.parse(old.substringBefore(SEPARATOR))?.time }.getOrNull()
                        writtenAt != null && writtenAt >= cutoff
                    }
                } else emptyList()
                file.writeText((kept + line).joinToString("\n", postfix = "\n"))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Could not write worker log", e)
        }
    }

    /**
     * Writes what happened while the app was not looked at: why earlier processes of the app died and
     * in which state WorkManager holds the nightly work. Queries WorkManager, so it runs on its own thread.
     */
    fun logProcessStart(context: Context) {
        val appContext = context.applicationContext
        thread(name = "worker-log") {
            append(appContext, "PROCESS_START")
            logProcessExits(appContext)
            logWorkState(appContext)
        }
    }

    /** State of the nightly periodic work as WorkManager sees it, including the next planned run. */
    fun logWorkState(context: Context) {
        try {
            val format = SimpleDateFormat(TIMESTAMP_PATTERN, Locale.US)
            val infos = WorkManager.getInstance(context).getWorkInfosForUniqueWork(NEW_WORKER_NAME).get()
            if (infos.isEmpty()) {
                append(context, "WORK_STATE", "no periodic work enqueued")
                return
            }
            infos.forEach { info ->
                val nextRun = info.nextScheduleTimeMillis
                    .takeIf { it != Long.MAX_VALUE }
                    ?.let { format.format(Date(it)) } ?: "none"
                val lastStop = if (info.stopReason == WorkInfo.STOP_REASON_NOT_STOPPED) "none" else info.stopReason.toString()
                append(
                    context, "WORK_STATE",
                    "state=${info.state} nextRun=$nextRun attempts=${info.runAttemptCount} lastStopReason=$lastStop"
                )
            }
        } catch (e: Exception) {
            append(context, "WORK_STATE", "query failed: ${e::class.simpleName}: ${e.message}")
        }
    }

    /** Process deaths the system recorded since the last call (Android 11+), e.g. force stop or low memory. */
    private fun logProcessExits(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val lastLogged = prefs.getLong(KEY_LAST_EXIT_LOGGED, 0L)
            val format = SimpleDateFormat(TIMESTAMP_PATTERN, Locale.US)
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager

            val exits = activityManager.getHistoricalProcessExitReasons(null, 0, 10)
                .filter { it.timestamp > lastLogged }
                .sortedBy { it.timestamp }
            exits.forEach { exit ->
                append(
                    context, "PROCESS_EXIT",
                    "at=${format.format(Date(exit.timestamp))} reason=${exitReasonName(exit.reason)} " +
                        "description=${exit.description ?: "-"}"
                )
            }
            exits.lastOrNull()?.let { prefs.edit().putLong(KEY_LAST_EXIT_LOGGED, it.timestamp).apply() }
        } catch (e: Exception) {
            append(context, "PROCESS_EXIT", "query failed: ${e::class.simpleName}: ${e.message}")
        }
    }

    private fun logFile(context: Context): File =
        File(context.getExternalFilesDir(null) ?: context.filesDir, FILE_NAME)

    /** Everything the system uses to decide whether background work of this app may run right now. */
    private fun deviceState(context: Context): String = try {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val bucket = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val usageStats = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            standbyBucketName(usageStats.appStandbyBucket)
        } else "n/a"
        "standbyBucket=$bucket batteryOptimized=${!power.isIgnoringBatteryOptimizations(context.packageName)} " +
            "powerSave=${power.isPowerSaveMode} doze=${power.isDeviceIdleMode}"
    } catch (e: Exception) {
        "deviceState=unavailable"
    }

    private fun standbyBucketName(bucket: Int): String = when (bucket) {
        5 -> "EXEMPTED"
        UsageStatsManager.STANDBY_BUCKET_ACTIVE -> "ACTIVE"
        UsageStatsManager.STANDBY_BUCKET_WORKING_SET -> "WORKING_SET"
        UsageStatsManager.STANDBY_BUCKET_FREQUENT -> "FREQUENT"
        UsageStatsManager.STANDBY_BUCKET_RARE -> "RARE"
        UsageStatsManager.STANDBY_BUCKET_RESTRICTED -> "RESTRICTED"
        else -> bucket.toString()
    }

    private fun exitReasonName(reason: Int): String = when (reason) {
        1 -> "EXIT_SELF"
        2 -> "SIGNALED"
        3 -> "LOW_MEMORY"
        4 -> "CRASH"
        5 -> "CRASH_NATIVE"
        6 -> "ANR"
        7 -> "INITIALIZATION_FAILURE"
        8 -> "PERMISSION_CHANGE"
        9 -> "EXCESSIVE_RESOURCE_USAGE"
        10 -> "USER_REQUESTED"
        11 -> "USER_STOPPED"
        12 -> "DEPENDENCY_DIED"
        13 -> "OTHER"
        14 -> "FREEZER"
        15 -> "PACKAGE_STATE_CHANGE"
        16 -> "PACKAGE_UPDATED"
        else -> reason.toString()
    }
}
