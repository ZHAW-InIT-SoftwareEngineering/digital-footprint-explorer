package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Process
import android.util.Log
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.AppCategory
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.DataPoint
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.NetworkType
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.App
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertThrows
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class MetricCollectorTest {
    private val youtubeUid = 1233
    private val instagramUid = 1234

    private val installedAppProvider = mockk<InstalledAppProvider>()
    private val networkUsageDataSource = mockk<NetworkUsageDataSource>()
    private val usageStatsManager = mockk<UsageStatsManager>()
    private val appOpsManager = mockk<AppOpsManager>()
    private val context = mockk<Context>()

    @Test
    fun testCollectNetworkMetricsForWifi() = runTest {
        setUpMocks(
            appTwoCellularBytes = 0L,
            appOneCellularBytes = 0L
        )
        val metricCollector = MetricCollector(installedAppProvider, networkUsageDataSource, usageStatsManager)
        val metrics = metricCollector.collectNetworkMetrics(
            context = context,
            startTime = 1682222222,
            endTime = 1682222222,
            mobileSubscriberId = null
        )

        assertTrue(metrics.isNotEmpty())

        assertEquals(DataPoint.Measured(1000000.0), metrics[0].wifiBytes)
        assertEquals(DataPoint.Measured(0.0), metrics[0].cellularBytes)
        assertEquals("Youtube", metrics[0].appName)
        assertEquals(AppCategory.VIDEO_STREAMING, metrics[0].appCategory)

        assertEquals(DataPoint.Measured(50000.0), metrics[1].wifiBytes)
        assertEquals(DataPoint.Measured(0.0), metrics[1].cellularBytes)
        assertEquals("Instagram", metrics[1].appName)
        assertEquals(AppCategory.SOCIAL_MEDIA, metrics[1].appCategory)
    }

    @Test
    fun testCollectNetworkMetricsForMobile() = runTest {
        setUpMocks(
            appTwoWifiBytes = 0L,
            appOneWifiBytes = 0L
        )
        val metricCollector = MetricCollector(installedAppProvider, networkUsageDataSource, usageStatsManager)
        val metrics = metricCollector.collectNetworkMetrics(
            context = context,
            startTime = 1682222222,
            endTime = 1682222222,
            mobileSubscriberId = "123456789"
        )

        assertTrue(metrics.isNotEmpty())

        assertEquals(DataPoint.Measured(0.0), metrics[0].wifiBytes)
        assertEquals(DataPoint.Measured(1000000.0), metrics[0].cellularBytes)
        assertEquals("Youtube", metrics[0].appName)
        assertEquals(AppCategory.VIDEO_STREAMING, metrics[0].appCategory)

        assertEquals(DataPoint.Measured(0.0), metrics[1].wifiBytes)
        assertEquals(DataPoint.Measured(120000.0), metrics[1].cellularBytes)
        assertEquals("Instagram", metrics[1].appName)
        assertEquals(AppCategory.SOCIAL_MEDIA, metrics[1].appCategory)
    }

    @Test
    fun testCollectNetworkMetricsForBoth() = runTest {
        setUpMocks()
        val metricCollector = MetricCollector(installedAppProvider, networkUsageDataSource, usageStatsManager)
        val metrics = metricCollector.collectNetworkMetrics(
            context = context,
            startTime = 1682222222,
            endTime = 1682222222,
            mobileSubscriberId = "123456789"
        )

        assertTrue(metrics.isNotEmpty())

        assertEquals(DataPoint.Measured(1000000.0), metrics[0].wifiBytes)
        assertEquals(DataPoint.Measured(1000000.0), metrics[0].cellularBytes)
        assertEquals("Youtube", metrics[0].appName)
        assertEquals(AppCategory.VIDEO_STREAMING, metrics[0].appCategory)

        assertEquals(DataPoint.Measured(50000.0), metrics[1].wifiBytes)
        assertEquals(DataPoint.Measured(120000.0), metrics[1].cellularBytes)
        assertEquals("Instagram", metrics[1].appName)
        assertEquals(AppCategory.SOCIAL_MEDIA, metrics[1].appCategory)
    }

    @Test
    fun testStartTimeIsBeforeEndTime() = runTest {
        setUpMocks()
        val metricCollector = MetricCollector(installedAppProvider, networkUsageDataSource, usageStatsManager)
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
        appOneCellularBytes: Long = 1000000L,
        appTwoWifiBytes: Long = 50000L,
        appTwoCellularBytes: Long = 120000L
    ) {
        mockkStatic(Process::class)
        every { Process.myUid() } returns 1000
        mockkStatic(Log::class)
        every { Log.d(any(), any()) } returns 0
        every { Log.w(any(), any<String>()) } returns 0
        every { installedAppProvider.getInstalledLauncherApps(context) } returns generateApps
        every { context.getSystemService(Context.APP_OPS_SERVICE) } returns appOpsManager
        every { context.packageName } returns "ch.zhaw.test"
        every { appOpsManager.unsafeCheckOpNoThrow(any(), any(), any()) } returns AppOpsManager.MODE_ALLOWED
        every { usageStatsManager.queryUsageStats(any(), any(), any()) } returns emptyList()
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
                networkType = NetworkType.CELLULAR,
                subscriberId = any(),
                startTime = any(),
                endTime = any(),
                uid = appOneUid
            )
        } returns appOneCellularBytes

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
                networkType = NetworkType.CELLULAR,
                subscriberId = any(),
                startTime = any(),
                endTime = any(),
                uid = appTwoUid
            )
        } returns appTwoCellularBytes

    }

    private val generateApps = listOf(
        App(
            uid         = youtubeUid,
            name        = "Youtube",
            packageName = "com.google.android.youtube",
            category    = AppCategory.VIDEO_STREAMING
        ),
        App(
            uid         = instagramUid,
            name        = "Instagram",
            packageName = "com.instagram.android",
            category    = AppCategory.SOCIAL_MEDIA
        )
    )
}