package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service

import android.content.Context
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.AppCategory
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.datasource.LauncherAppQuery
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.App
import io.mockk.every
import io.mockk.mockk
import kotlin.test.Test
import kotlin.test.assertEquals
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
        assertTrue(apps.size < 3)

        assertEquals("Youtube", apps[0].name)
        assertEquals(1000, apps[0].uid)

        assertEquals("Chrome", apps[1].name)
        assertEquals(1001, apps[1].uid)
    }

    @Test
    fun testGetInstalledLauncherAppsWithArtificialIntelligenceCategory() {
        val installedAppProvider = InstalledAppProvider(
            launcherAppQuery = launcherAppQuery
        )

        val chatGptAppInfo = createApplicationInfo(
            uid = 1000,
            category = ApplicationInfo.CATEGORY_PRODUCTIVITY,
            label = "ChatGPT",
            packageName = "com.openai.chatgpt"
        )

        val resolveInfo1 = createResolveInfo(
            packageName = "com.openai.chatgpt",
            applicationInfo = chatGptAppInfo
        )

        every { launcherAppQuery.create(context) } returns listOf(resolveInfo1)

        val apps: List<App> = installedAppProvider.getInstalledLauncherApps(context)

        assertNotNull(apps)
        assertTrue(apps.isNotEmpty())
        assertEquals(1, apps.size)
        assertEquals(AppCategory.ARTIFICIAL_INTELLIGENCE, apps[0].category)
    }

    @Test
    fun testGetInstalledLauncherAppsWithEMailCategory() {
        val installedAppProvider = InstalledAppProvider(launcherAppQuery = launcherAppQuery)

        val gmail = createApplicationInfo(
            uid = 1000,
            category = ApplicationInfo.CATEGORY_PRODUCTIVITY,
            label = "GMail",
            packageName = "com.google.android.gm"
        )

        val resolveInfo1 = createResolveInfo(
            packageName = "com.google.android.gm",
            applicationInfo = gmail
        )

        every { launcherAppQuery.create(context) } returns listOf(resolveInfo1)

        val apps: List<App> = installedAppProvider.getInstalledLauncherApps(context)

        assertNotNull(apps)
        assertTrue(apps.isNotEmpty())
        assertEquals(1, apps.size)
        assertEquals(AppCategory.E_MAIL, apps[0].category)
    }

    @Test
    fun testGetInstalledLauncherAppsWithMessagingCategory() {
        val installedAppProvider = InstalledAppProvider(launcherAppQuery = launcherAppQuery)

        val telegram = createApplicationInfo(
            uid = 1000,
            category = ApplicationInfo.CATEGORY_PRODUCTIVITY,
            label = "Telegram",
            packageName = "org.telegram.messenger"
        )

        val resolveInfo1 = createResolveInfo(
            packageName = "org.telegram.messenger",
            applicationInfo = telegram
        )

        every { launcherAppQuery.create(context) } returns listOf(resolveInfo1)

        val apps: List<App> = installedAppProvider.getInstalledLauncherApps(context)

        assertNotNull(apps)
        assertTrue(apps.isNotEmpty())
        assertEquals(1, apps.size)
        assertEquals(AppCategory.MESSAGING, apps[0].category)
    }

    @Test
    fun testGetInstalledLauncherAppsWithVideoCallCategory() {
        val installedAppProvider = InstalledAppProvider(launcherAppQuery = launcherAppQuery)

        val videoCall = createApplicationInfo(
            uid = 1000,
            category = ApplicationInfo.CATEGORY_PRODUCTIVITY,
            label = "Telegram",
            packageName = "com.recommended.videocall"
        )

        val resolveInfo1 = createResolveInfo(
            packageName = "com.recommended.videocall",
            applicationInfo = videoCall
        )

        every { launcherAppQuery.create(context) } returns listOf(resolveInfo1)

        val apps: List<App> = installedAppProvider.getInstalledLauncherApps(context)

        assertNotNull(apps)
        assertTrue(apps.isNotEmpty())
        assertEquals(1, apps.size)
        assertEquals(AppCategory.VIDEO_CALL, apps[0].category)
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