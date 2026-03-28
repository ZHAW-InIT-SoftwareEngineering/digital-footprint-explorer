package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service

import android.content.Context
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.datasource.LauncherAppQuery
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.App
import io.mockk.every
import io.mockk.mockk
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class InstalledAppProviderTest {

    private val packageManager = mockk<PackageManager>()
    private val context = mockk<Context> {
        every { packageManager } returns this@InstalledAppProviderTest.packageManager
    }
    private val launcherAppQuery = mockk<LauncherAppQuery>()

    @Test
    fun testGetInstalledLauncherApps() {
        val installedAppProvider = InstalledAppProvider(launcherAppQuery = launcherAppQuery)

        val youtubeAppInfo = createApplicationInfo(
            uid = 1000,
            category = ApplicationInfo.CATEGORY_VIDEO,
            label = "Youtube",
            packageName = "com.google.android.youtube"
        )

        val chromeAppInfo = createApplicationInfo(
            uid = 1001,
            category = ApplicationInfo.CATEGORY_PRODUCTIVITY,
            label = "Chrome",
            packageName = "com.android.chrome"
        )

        val resolveInfo1 = createResolveInfo(
            packageName = "com.google.android.youtube",
            applicationInfo = youtubeAppInfo
        )

        val resolveInfo2 = createResolveInfo(
            packageName = "com.android.chrome",
            applicationInfo = chromeAppInfo
        )

        every { launcherAppQuery.create(context) } returns listOf(resolveInfo1, resolveInfo2)

        val apps: List<App> = installedAppProvider.getInstalledLauncherApps(context)

        assertNotNull(apps)
        assertTrue(apps.isNotEmpty())
        assertEquals(2, apps.size)

        assertEquals("Youtube", apps[0].name)
        assertEquals(1000, apps[0].uid)

        assertEquals("Chrome", apps[1].name)
        assertEquals(1001, apps[1].uid)
    }

    @Test
    fun testGetInstalledLauncherAppsWithoutDuplicates() {
        val installedAppProvider = InstalledAppProvider(launcherAppQuery = launcherAppQuery)

        val youtubeAppInfo = createApplicationInfo(
            uid = 1000,
            category = ApplicationInfo.CATEGORY_VIDEO,
            label = "Youtube",
            packageName = "com.google.android.youtube"
        )

        val chromeAppInfo = createApplicationInfo(
            uid = 1001,
            category = ApplicationInfo.CATEGORY_PRODUCTIVITY,
            label = "Chrome",
            packageName = "com.android.chrome"
        )

        val youtubeAppInfo2 = createApplicationInfo(
            uid = 1000,
            category = ApplicationInfo.CATEGORY_VIDEO,
            label = "Youtube",
            packageName = "com.google.android.youtube2"
        )

        val resolveInfo1 = createResolveInfo(
            packageName = "com.google.android.youtube",
            applicationInfo = youtubeAppInfo
        )

        val resolveInfo2 = createResolveInfo(
            packageName = "com.android.chrome",
            applicationInfo = chromeAppInfo
        )

        val resolveInfo3 = createResolveInfo(
            packageName = "com.google.android.youtube2",
            applicationInfo = youtubeAppInfo2
        )

        every { launcherAppQuery.create(context) } returns listOf(resolveInfo1, resolveInfo2, resolveInfo3)

        val apps: List<App> = installedAppProvider.getInstalledLauncherApps(context)

        assertNotNull(apps)
        assertTrue(apps.isNotEmpty())

        assertNotEquals(3, apps.size)

        assertEquals("Youtube", apps[0].name)
        assertEquals(1000, apps[0].uid)

        assertEquals("Chrome", apps[1].name)
        assertEquals(1001, apps[1].uid)
    }

    private fun createApplicationInfo(
        uid: Int,
        category: Int,
        label: String,
        packageName: String,
    ): ApplicationInfo {
        return ApplicationInfo().apply {
            this.uid = uid
            this.category = category
            this.packageName = packageName
            this.nonLocalizedLabel = label
        }
    }

    private fun createResolveInfo(
        packageName: String,
        applicationInfo: ApplicationInfo
    ): ResolveInfo {

        val activityInfo = ActivityInfo().apply {
            this.packageName = packageName
            this.applicationInfo = applicationInfo
        }

        return ResolveInfo().apply {
            this.activityInfo = activityInfo
        }
    }
}