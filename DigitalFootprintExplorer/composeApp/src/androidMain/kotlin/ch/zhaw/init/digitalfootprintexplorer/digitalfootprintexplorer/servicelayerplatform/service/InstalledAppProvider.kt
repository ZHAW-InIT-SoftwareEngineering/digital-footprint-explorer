package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Build
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.App

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

    private fun getAppCategory(applicationInfo: ApplicationInfo): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return "UNDEFINED"

        return when(applicationInfo.category) {
            ApplicationInfo.CATEGORY_GAME -> "GAME"
            ApplicationInfo.CATEGORY_AUDIO -> "AUDIO"
            ApplicationInfo.CATEGORY_VIDEO -> "VIDEO"
            ApplicationInfo.CATEGORY_IMAGE -> "IMAGE"
            ApplicationInfo.CATEGORY_SOCIAL -> "SOCIAL"
            ApplicationInfo.CATEGORY_NEWS -> "NEWS"
            ApplicationInfo.CATEGORY_MAPS -> "MAPS"
            ApplicationInfo.CATEGORY_PRODUCTIVITY -> "PRODUCTIVITY"
            ApplicationInfo.CATEGORY_ACCESSIBILITY -> "ACCESSIBILITY"
            else -> "UNDEFINED"
        }
    }
}