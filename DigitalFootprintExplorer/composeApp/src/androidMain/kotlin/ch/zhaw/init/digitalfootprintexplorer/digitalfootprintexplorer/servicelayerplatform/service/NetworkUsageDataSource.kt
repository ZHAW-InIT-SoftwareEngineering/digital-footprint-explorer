package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service

import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Context
import android.net.NetworkCapabilities
import android.os.RemoteException
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.NetworkType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class NetworkUsageDataSource(
    private val context: Context
) {

    suspend fun getUsageBytes(
        networkType: NetworkType,
        subscriberId: String?,
        startTime: Long,
        endTime: Long,
        uid: Int
    ): Long? = withContext(Dispatchers.IO) {
        if (startTime > endTime) throw IllegalArgumentException("Start time must be before end time.")

        val networkStatsManager = context.getSystemService(Context.NETWORK_STATS_SERVICE) as NetworkStatsManager

        val androidNetworkType = when(networkType) {
            NetworkType.WIFI -> NetworkCapabilities.TRANSPORT_WIFI
            NetworkType.CELLULAR -> NetworkCapabilities.TRANSPORT_CELLULAR
        }

        try {
            val stats = networkStatsManager.queryDetailsForUid(
                androidNetworkType,
                subscriberId,
                startTime,
                endTime,
                uid
            )

            try {
                var rxBytes = 0L
                var txBytes = 0L
                val bucket = NetworkStats.Bucket()

                while(stats.hasNextBucket()) {
                    stats.getNextBucket(bucket)
                    rxBytes += bucket.rxBytes
                    txBytes += bucket.txBytes
                }
                rxBytes + txBytes
            } catch (e: RemoteException) {
                e.printStackTrace()
                null
            }
        } catch (e: SecurityException) {
            e.printStackTrace()
            null
        }
    }

}