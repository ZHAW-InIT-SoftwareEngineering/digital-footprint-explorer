package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.datasource.AndroidLauncherAppQuery
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.datasource.LauncherAppQuery
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.App
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.AppCategory

class InstalledAppProvider(
    private val launcherAppQuery: LauncherAppQuery = AndroidLauncherAppQuery()
) {

    fun getInstalledLauncherApps(context: Context): List<App> {
        return launcherAppQuery.create(context)
            .map { resolveInfo ->
                val appInfo = resolveInfo.activityInfo.applicationInfo
                App(
                    uid = appInfo.uid,
                    /**todo: verfiy if works correctly, maybe use packageName instead of label.
                     * Comment: The string provided in the AndroidManifest file, if any.
                     * You probably don't want to use this. You probably want PackageManager.getApplicationLabel
                     * **/
                    name = appInfo.nonLocalizedLabel.toString(),
                    category = getAppCategory(appInfo)
                )
            }
            //remove duplicates because the uid could have multiple package names
            //example: com.google.android.youtube and com.google.android.apps.youtube would have the same uid
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