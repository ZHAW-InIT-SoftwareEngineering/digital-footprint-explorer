package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service

import android.app.usage.UsageStatsManager
import android.content.Context
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input.AppUsageInput
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.DataPoint
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.NetworkType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

class MetricCollector(
    private val installedAppProvider: InstalledAppProvider,
    private val networkUsageDataSource: NetworkUsageDataSource,
    private val usageStatsManager: UsageStatsManager
) {

    suspend fun collectNetworkMetrics(
        context: Context,
        startTime: Long,
        endTime: Long,
        mobileSubscriberId: String?
    ): List<AppUsageInput> = coroutineScope {
        if (startTime > endTime) throw IllegalArgumentException("Start time must be before end time.")

        val apps = installedAppProvider.getInstalledLauncherApps(context)
        val dispatcher = Dispatchers.IO.limitedParallelism(3)

        val foregroundMap: Map<String, Long> = usageStatsManager
            .queryUsageStats(UsageStatsManager.INTERVAL_DAILY, startTime, endTime)
            .associate { it.packageName to it.totalTimeInForeground }

        apps.map { app ->
            async(dispatcher) {
                val wifiBytes: DataPoint = networkUsageDataSource.getUsageBytes(
                    networkType = NetworkType.WIFI,
                    subscriberId = null,
                    startTime = startTime,
                    endTime = endTime,
                    uid = app.uid
                )?.let { DataPoint.Measured(it.toDouble()) }
                    ?: DataPoint.Unavailable("permission denied")

                val cellularBytes: DataPoint = networkUsageDataSource.getUsageBytes(
                    networkType = NetworkType.CELLULAR,
                    subscriberId = mobileSubscriberId,
                    startTime = startTime,
                    endTime = endTime,
                    uid = app.uid
                )?.let { DataPoint.Measured(it.toDouble()) }
                    ?: DataPoint.Unavailable("permission denied")

                AppUsageInput(
                    appName             = app.name,
                    wifiBytes           = wifiBytes,
                    cellularBytes       = cellularBytes,
                    appCategory         = app.category,
                    totalForegroundTime = ((foregroundMap[app.packageName] ?: 0L) / 1_000L).toInt()
                )
            }
        }.awaitAll()
    }

}