package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service

import android.content.Context
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.AppMetric
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.NetworkType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

class MetricCollector(
    private val installedAppProvider: InstalledAppProvider,
    private val networkUsageDataSource: NetworkUsageDataSource
) {

    suspend fun collectNetworkMetrics(
        context: Context,
        startTime: Long,
        endTime: Long,
        mobileSubscriberId: String?
    ): List<AppMetric> = coroutineScope {
        val apps = installedAppProvider.getInstalledLauncherApps(context)
        val dispatcher = Dispatchers.IO.limitedParallelism(3)

        apps.map { app ->
            async(dispatcher) {
                val wifiBytes: Long = networkUsageDataSource.getUsageBytes(
                    networkType = NetworkType.WIFI,
                    subscriberId = null,
                    startTime = startTime,
                    endTime = endTime,
                    uid = app.uid
                ) ?: 0L

                val mobileNetworkBytes: Long = networkUsageDataSource.getUsageBytes(
                    networkType = NetworkType.MOBILE,
                    subscriberId = mobileSubscriberId,
                    startTime = startTime,
                    endTime = endTime,
                    uid = app.uid
                ) ?: 0L

                AppMetric(
                    appName = app.name,
                    wifiBytes = wifiBytes,
                    mobileBytes = mobileNetworkBytes,
                    appCategory = app.category,
                    //todo calculate total foreground time
                    totalForegroundTime = 0
                )
            }

        }.awaitAll()
    }

}