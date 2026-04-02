package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service

import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Context
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.App
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.AppCategory
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.NetworkType
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import kotlin.test.Ignore
import kotlin.test.Test
import kotlin.test.assertEquals

@Ignore("This will be tested in the compose app itself, because mockk is too complicated to be used here")
class NetworkUsageDataSourceTest {

    private val installedAppProvider = mockk<InstalledAppProvider>()
    private val context = mockk<Context>()
    private val networkStateManager = mockk<NetworkStatsManager>()
    private val networkStats = mockk<NetworkStats>()
    private val bucket = mockk<NetworkStats.Bucket>()

    @Test
    fun testGetUsageBytes() = runTest {
        setUpMocks()
        val networkUsageDataSource = NetworkUsageDataSource(context)
        val totalBytes = networkUsageDataSource.getUsageBytes(
            networkType = NetworkType.WIFI,
            subscriberId = null,
            startTime = 1682222222,
            endTime = 1682222222,
            uid = 1233
        )

        assertEquals(2000000L, totalBytes)
    }

    private fun setUpMocks(
        rxByte: Long = 1000000L,
        txByte: Long = 1000000L
    ) {
        every { installedAppProvider.getInstalledLauncherApps(context) } returns generateApps
        every { context.getSystemService(Context.NETWORK_STATS_SERVICE)} returns networkStateManager
        every {
            networkStateManager.queryDetailsForUid(
                any(),
                any(),
                any(),
                any(),
                any())
        } returns networkStats

        every { networkStats.hasNextBucket() } returns true
        every { networkStats.getNextBucket(bucket) } returns true
        every { bucket.rxBytes } returns rxByte
        every { bucket.txBytes } returns txByte
    }

    private val generateApps = listOf(
        App(
            uid = 1233,
            name = "Youtube",
            category = AppCategory.VIDEO_STREAMING
        ),
        App(
            uid = 1234,
            name = "Instagram",
            category = AppCategory.SOCIAL_MEDIA
        )
    )

}