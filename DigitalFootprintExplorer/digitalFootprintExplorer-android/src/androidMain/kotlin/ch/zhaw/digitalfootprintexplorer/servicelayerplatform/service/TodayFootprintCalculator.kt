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

package ch.zhaw.digitalfootprintexplorer.servicelayerplatform.service

import android.app.usage.UsageStatsManager
import android.content.Context
import android.telephony.TelephonyManager
import android.util.Log
import ch.zhaw.digitalfootprintexplorer.model.DayHistory
import ch.zhaw.digitalfootprintexplorer.model.EmissionsCalculator
import ch.zhaw.digitalfootprintexplorer.model.toDayHistory
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.datetime.Clock
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.toLocalDateTime

/** Footprint of the current day from midnight until [calculatedAtMs]. */
data class TodaySnapshot(val day: DayHistory, val calculatedAtMs: Long)

/**
 * Calculates the footprint of the current, not yet finished day (midnight → now) for the
 * statistics. It only reads the trackers ([DisplayBrightnessObserver.peek],
 * [BackgroundProcessTracker.peek]) and never writes to the database, so neither the stored
 * history nor the garden state / baseline are influenced. The garden is still only updated by
 * [ch.zhaw.digitalfootprintexplorer.worker.DailyFootprintWorker] once the day is over.
 */
class TodayFootprintCalculator(
    private val context: Context,
    private val displayObserver: DisplayBrightnessObserver,
    private val backgroundTracker: BackgroundProcessTracker
) {
    private val _snapshot = MutableStateFlow<TodaySnapshot?>(null)
    val snapshot: StateFlow<TodaySnapshot?> = _snapshot.asStateFlow()

    private val mutex = Mutex()

    /** Recalculates midnight → now. Keeps the previous snapshot if the calculation fails. */
    suspend fun refresh() = mutex.withLock {
        val zone = TimeZone.currentSystemDefault()
        val now = Clock.System.now()
        val today = now.toLocalDateTime(zone).date
        val startMs = today.atStartOfDayIn(zone).toEpochMilliseconds()
        val endMs = now.toEpochMilliseconds()
        if (endMs <= startMs) return@withLock

        try {
            val result = withContext(Dispatchers.Default) {
                val usageStatsManager =
                    context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                val networkMetrics = MetricCollector(
                    installedAppProvider = InstalledAppProvider(),
                    networkUsageDataSource = NetworkUsageDataSource(context),
                    usageStatsManager = usageStatsManager
                ).collectNetworkMetrics(context, startMs, endMs, readSubscriberId())

                EmissionsCalculator().calculate(
                    appUsage = networkMetrics,
                    display = displayObserver.peek(startMs, endMs),
                    background = backgroundTracker.peek(startMs, endMs)
                )
            }
            _snapshot.value = TodaySnapshot(result.toDayHistory(today), endMs)
            Log.d(TAG, "Today so far: ${"%.2f".format(result.ghgTotal * 1000)} gCO₂e")
        } catch (e: Exception) {
            Log.e(TAG, "Could not calculate today's footprint", e)
        }
    }

    @Suppress("DEPRECATION", "MissingPermission")
    private fun readSubscriberId(): String? = try {
        (context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager).subscriberId
    } catch (_: SecurityException) {
        null
    }

    private companion object {
        const val TAG = "TodayFootprint"
    }
}
