package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Build
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.App
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.AppCategory

class InstalledAppProvider {

    fun getInstalledLauncherApps(context: Context): List<App> {
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }

        return context.packageManager
            .queryIntentActivities(intent, 0)
            .map { resolveInfo ->
                val appInfo = resolveInfo.activityInfo.applicationInfo
                App(
                    uid = appInfo.uid,
                    name = appInfo.loadLabel(context.packageManager).toString(),
                    category = getAppCategory(appInfo)
                )
            }
            //remove duplicates because the uid could have multiple package names
            //example: com.google.android.youtube and com.google.android.apps.youtube
            .distinctBy {it.uid}
    }

    private fun getAppCategory(applicationInfo: ApplicationInfo): AppCategory {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return AppCategory.MISCELLANEOUS

        return when(applicationInfo.category) {
            ApplicationInfo.CATEGORY_GAME -> AppCategory.GAMING
            ApplicationInfo.CATEGORY_AUDIO -> AppCategory.AUDIO_STREAMING
            ApplicationInfo.CATEGORY_VIDEO -> AppCategory.VIDEO_STREAMING
            ApplicationInfo.CATEGORY_SOCIAL -> AppCategory.SOCIAL_MEDIA
            ApplicationInfo.CATEGORY_NEWS,
            ApplicationInfo.CATEGORY_MAPS,
            ApplicationInfo.CATEGORY_PRODUCTIVITY,
            ApplicationInfo.CATEGORY_ACCESSIBILITY -> AppCategory.MISCELLANEOUS
            else -> AppCategory.MISCELLANEOUS
        }
    }
}