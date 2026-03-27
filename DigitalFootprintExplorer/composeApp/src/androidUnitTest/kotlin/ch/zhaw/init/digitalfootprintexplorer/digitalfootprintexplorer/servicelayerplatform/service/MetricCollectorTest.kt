package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service

import android.content.Context
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.App
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.AppCategory
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.NetworkType
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertTrue
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertThrows
import org.junit.Test

class MetricCollectorTest {
    private val youtubeUid = 1233
    private val instagramUid = 1234

    private val installedAppProvider = mockk<InstalledAppProvider>()
    private val networkUsageDataSource = mockk<NetworkUsageDataSource>()
    private val context = mockk<Context>()

    @Test
    fun testCollectNetworkMetricsForWifi() = runTest {
        setUpMocks(
            appTwoMobileBytes = 0L,
            appOneMobileBytes = 0L
        )
        val metricCollector = MetricCollector(installedAppProvider, networkUsageDataSource)
        val metrics = metricCollector.collectNetworkMetrics(
            context = context,
            startTime = 1682222222,
            endTime = 1682222222,
            mobileSubscriberId = null
        )

        assertTrue(metrics.isNotEmpty())

        assertEquals(1000000L, metrics[0].wifiBytes)
        assertEquals(0L, metrics[0].mobileBytes)
        assertEquals("Youtube", metrics[0].appName)
        assertEquals(AppCategory.VIDEO_STREAMING, metrics[0].appCategory)
        assertEquals(1000000L, metrics[0].totalBytes)

        assertEquals(50000L, metrics[1].wifiBytes)
        assertEquals(0L, metrics[1].mobileBytes)
        assertEquals("Instagram", metrics[1].appName)
        assertEquals(AppCategory.SOCIAL_MEDIA, metrics[1].appCategory)
        assertEquals(50000L, metrics[1].totalBytes)
    }

    @Test
    fun testCollectNetworkMetricsForMobile() = runTest {
        setUpMocks(
            appTwoWifiBytes = 0L,
            appOneWifiBytes = 0L
        )
        val metricCollector = MetricCollector(installedAppProvider, networkUsageDataSource)
        val metrics = metricCollector.collectNetworkMetrics(
            context = context,
            startTime = 1682222222,
            endTime = 1682222222,
            mobileSubscriberId = "123456789"
        )

        assertTrue(metrics.isNotEmpty())

        assertEquals(0L, metrics[0].wifiBytes)
        assertEquals(1000000L, metrics[0].mobileBytes)
        assertEquals("Youtube", metrics[0].appName)
        assertEquals(AppCategory.VIDEO_STREAMING, metrics[0].appCategory)
        assertEquals(1000000L, metrics[0].totalBytes)

        assertEquals(0L, metrics[1].wifiBytes)
        assertEquals(120000L, metrics[1].mobileBytes)
        assertEquals("Instagram", metrics[1].appName)
        assertEquals(AppCategory.SOCIAL_MEDIA, metrics[1].appCategory)
        assertEquals(120000L, metrics[1].totalBytes)
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

        assertTrue(metrics.isNotEmpty())

        assertEquals(1000000L, metrics[0].wifiBytes)
        assertEquals(1000000L, metrics[0].mobileBytes)
        assertEquals("Youtube", metrics[0].appName)
        assertEquals(AppCategory.VIDEO_STREAMING, metrics[0].appCategory)
        assertEquals(2000000L, metrics[0].totalBytes)

        assertEquals(50000L, metrics[1].wifiBytes)
        assertEquals(120000L, metrics[1].mobileBytes)
        assertEquals("Instagram", metrics[1].appName)
        assertEquals(AppCategory.SOCIAL_MEDIA, metrics[1].appCategory)
        assertEquals(170000L, metrics[1].totalBytes)
    }

    @Test
    fun testStartTimeIsBeforeEndTime() = runTest {
        setUpMocks()
        val metricCollector = MetricCollector(installedAppProvider, networkUsageDataSource)
        assertThrows(IllegalArgumentException::class.java) {
            runBlocking {
                metricCollector.collectNetworkMetrics(
                    context = context,
                    startTime = 1682222222,
                    endTime = 1682222220,
                    mobileSubscriberId = "123456789"
                )
            }
        }
    }

    private fun setUpMocks(
        appOneUid: Int = 1233,
        appTwoUid: Int = 1234,
        appOneWifiBytes: Long = 1000000L,
        appOneMobileBytes: Long = 1000000L,
        appTwoWifiBytes: Long = 50000L,
        appTwoMobileBytes: Long = 120000L
    ) {
        every { installedAppProvider.getInstalledLauncherApps(context) } returns generateApps
        coEvery {
            networkUsageDataSource.getUsageBytes(
                networkType = NetworkType.WIFI,
                subscriberId = any(),
                startTime = any(),
                endTime = any(),
                uid = appOneUid
            )
        } returns appOneWifiBytes

        coEvery {
            networkUsageDataSource.getUsageBytes(
                networkType = NetworkType.MOBILE,
                subscriberId = any(),
                startTime = any(),
                endTime = any(),
                uid = appOneUid
            )
        } returns appOneMobileBytes

        coEvery {
            networkUsageDataSource.getUsageBytes(
                networkType = NetworkType.WIFI,
                subscriberId = any(),
                startTime = any(),
                endTime = any(),
                uid = appTwoUid
            )
        } returns appTwoWifiBytes

        coEvery {
            networkUsageDataSource.getUsageBytes(
                networkType = NetworkType.MOBILE,
                subscriberId = any(),
                startTime = any(),
                endTime = any(),
                uid = appTwoUid
            )
        } returns appTwoMobileBytes

    }

    private val generateApps = listOf(
        App(
            uid = youtubeUid,
            name = "Youtube",
            category = AppCategory.VIDEO_STREAMING
        ),
        App(
            uid = instagramUid,
            name = "Instagram",
            category = AppCategory.SOCIAL_MEDIA
        )
    )
}