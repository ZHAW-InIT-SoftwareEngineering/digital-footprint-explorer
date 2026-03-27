package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service

import android.content.Context
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.App
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.AppCategory
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.NetworkType
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Test
import kotlin.test.assertEquals

class MetricCollectorTest {

    private val installedAppProvider = mockk<InstalledAppProvider>()
    private val networkUsageDataSource = mockk<NetworkUsageDataSource>()
    private val context = mockk<Context>()

    @Test
    fun testCollectNetworkMetricsForWifi() = runTest {
        setUpMocks(mobileBytes = 0L)
        val metricCollector = MetricCollector(installedAppProvider, networkUsageDataSource)
        val metrics = metricCollector.collectNetworkMetrics(
            context = context,
            startTime = 1682222222,
            endTime = 1682222222,
            mobileSubscriberId = null
        )
        //the size is 2 because we have 2 apps installed
        assert(metrics.size == 2)
        assertEquals(1000000L, metrics[0].wifiBytes)
        assertEquals(0L, metrics[0].mobileBytes)
        assertEquals(1000000L, metrics[1].wifiBytes)
        assertEquals(0L, metrics[1].mobileBytes)
        assertEquals(1000000L, metrics[0].totalBytes)
        assertEquals(1000000L, metrics[1].totalBytes)
    }

    @Test
    fun testCollectNetworkMetricsForMobile() = runTest {
        setUpMocks(wifiBytes = 0L)
        val metricCollector = MetricCollector(installedAppProvider, networkUsageDataSource)
        val metrics = metricCollector.collectNetworkMetrics(
            context = context,
            startTime = 1682222222,
            endTime = 1682222222,
            mobileSubscriberId = "123456789"
        )
        //the size is 2 because we have 2 apps installed
        assert(metrics.size == 2)
        assertEquals(0L, metrics[0].wifiBytes)
        assertEquals(1000000L, metrics[0].mobileBytes)
        assertEquals(0L, metrics[1].wifiBytes)
        assertEquals(1000000L, metrics[1].mobileBytes)
        assertEquals(1000000L, metrics[0].totalBytes)
        assertEquals(1000000L, metrics[1].totalBytes)
    }

    @Test
    fun testCollectNetworkMetricsForBoth() = runTest {
        setUpMocks()
        val metricCollector = MetricCollector(installedAppProvider, networkUsageDataSource)
        val metrics = metricCollector.collectNetworkMetrics(
            context = context,
            startTime = 1682222222,
            endTime = 1682222222,
            mobileSubscriberId = "123456789"
        )
        //the size is 2 because we have 2 apps installed
        assert(metrics.size == 2)
        assertEquals(1000000L, metrics[0].wifiBytes)
        assertEquals(1000000L, metrics[0].mobileBytes)
        assertEquals(1000000L, metrics[1].wifiBytes)
        assertEquals(1000000L, metrics[1].mobileBytes)
        assertEquals(2000000L, metrics[0].totalBytes)
        assertEquals(2000000L, metrics[1].totalBytes)
    }

    private fun setUpMocks(
        wifiBytes: Long = 1000000L,
        mobileBytes: Long = 1000000L,
    ) {
        every { installedAppProvider.getInstalledLauncherApps(context) } returns generateApps
        coEvery {
            networkUsageDataSource.getUsageBytes(
                networkType = NetworkType.WIFI,
                subscriberId = any(),
                startTime = any(),
                endTime = any(),
                uid = any()
            )
        } returns wifiBytes
        coEvery {
            networkUsageDataSource.getUsageBytes(
                networkType = NetworkType.MOBILE,
                subscriberId = any(),
                startTime = any(),
                endTime = any(),
                uid = any()
            )
        } returns mobileBytes

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