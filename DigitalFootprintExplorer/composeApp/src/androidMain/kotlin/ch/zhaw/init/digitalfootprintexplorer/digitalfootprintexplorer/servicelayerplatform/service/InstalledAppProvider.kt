package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.datasource.APP_CATEGORY_CONFIG
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.datasource.AndroidLauncherAppQuery
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.datasource.LauncherAppQuery
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.AppCategory
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.App

class InstalledAppProvider(
    private val launcherAppQuery: LauncherAppQuery = AndroidLauncherAppQuery()
) {

    fun getInstalledLauncherApps(context: Context): List<App> {
        return launcherAppQuery.create(context)
            .map { resolveInfo ->
                val appInfo = resolveInfo.activityInfo.applicationInfo
                generateApp(context = context, applicationInfo = appInfo)
            }
            /* Remove duplicates because one UID can have multiple package names, */
            /* e.g. com.google.android.youtube and com.google.android.apps.youtube share a UID. */
            .distinctBy { it.uid }
    }

    private fun generateApp(context: Context, applicationInfo: ApplicationInfo): App {
        val foundCategory = compareAppCategoryConfigWithPackageName(packageName = applicationInfo.packageName)
        /* Use PackageManager.getApplicationLabel() to obtain the localised, user-visible app name. */
        /* Falls back to the package name if the label cannot be resolved. */
        val appName = runCatching {
            context.packageManager.getApplicationLabel(applicationInfo).toString()
        }.getOrDefault(applicationInfo.packageName)

        return App(
            uid      = applicationInfo.uid,
            name     = appName,
            category = if (foundCategory != AppCategory.MISCELLANEOUS) foundCategory else selectAppCategory(applicationInfo)
        )
    }

    /**
     * This method is used to select the app category from the applicationInfo.category field.
     * @param applicationInfo the applicationInfo object from the AndroidManifest file.
     * @return the app category.
     */
    private fun selectAppCategory(applicationInfo: ApplicationInfo): AppCategory {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return AppCategory.MISCELLANEOUS

        return when(applicationInfo.category) {
            ApplicationInfo.CATEGORY_GAME -> AppCategory.GAMING
            ApplicationInfo.CATEGORY_AUDIO -> AppCategory.AUDIO_STREAMING
            ApplicationInfo.CATEGORY_VIDEO -> AppCategory.VIDEO_STREAMING
            ApplicationInfo.CATEGORY_SOCIAL -> AppCategory.SOCIAL_MEDIA
            ApplicationInfo.CATEGORY_MAPS -> AppCategory.NAVIGATION
            ApplicationInfo.CATEGORY_NEWS,
            ApplicationInfo.CATEGORY_PRODUCTIVITY,
            ApplicationInfo.CATEGORY_ACCESSIBILITY -> AppCategory.MISCELLANEOUS
            else -> AppCategory.MISCELLANEOUS
        }
    }

    /**
     * This method is used to select the app category from the appCategoryConfig.json file.
     * @param category the category from the appCategoryConfig.json file.
     * @return the app category.
     */
    private fun selectAppCategoryFromAppCategoryConfig(category: String): AppCategory {
        return when(category) {
            "AI" -> AppCategory.ARTIFICIAL_INTELLIGENCE
            "Mail" -> AppCategory.E_MAIL
            "Messaging" -> AppCategory.MESSAGING
            "Video_Call" -> AppCategory.VIDEO_CALL
            else -> AppCategory.MISCELLANEOUS
        }
    }

    private fun compareAppCategoryConfigWithPackageName(packageName: String): AppCategory {
        APP_CATEGORY_CONFIG.forEach {
            (category, packageNames) -> if (packageName in packageNames)
                return selectAppCategoryFromAppCategoryConfig(category)
        }
        return AppCategory.MISCELLANEOUS
    }
}