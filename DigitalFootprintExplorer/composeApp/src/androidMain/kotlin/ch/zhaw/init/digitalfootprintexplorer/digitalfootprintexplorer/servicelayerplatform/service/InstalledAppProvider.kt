package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.datasource.AndroidLauncherAppQuery
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.datasource.AppCategoryConfigLoader
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.datasource.LauncherAppQuery
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.App
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model.AppCategory

class InstalledAppProvider(
    private val launcherAppQuery: LauncherAppQuery = AndroidLauncherAppQuery(),
    private val appCategoryConfigLoader: AppCategoryConfigLoader = AppCategoryConfigLoader()
) {

    fun getInstalledLauncherApps(context: Context): List<App> {
        return launcherAppQuery.create(context)
            .map { resolveInfo ->
                val appInfo = resolveInfo.activityInfo.applicationInfo
                generateApp(
                    applicationInfo = appInfo,
                    context = context
                )
            }
            //remove duplicates because the uid could have multiple package names
            //example: com.google.android.youtube and com.google.android.apps.youtube would have the same uid
            .distinctBy {it.uid}
    }

    private fun generateApp(applicationInfo: ApplicationInfo, context: Context): App {
        val foundCategory = compareAppCategoryConfigWithPackagename(
            packageName = applicationInfo.packageName,
            context = context
        )

        return App(
            uid = applicationInfo.uid,
            /**todo: verfiy if works correctly, maybe use packageName instead of label.
             * Comment: The string provided in the AndroidManifest file, if any.
             * You probably don't want to use this. You probably want PackageManager.getApplicationLabel
             * **/
            name = applicationInfo.nonLocalizedLabel.toString(),
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
     */
    private fun selectAppCategoryFromAppCategoryConfig(category: String): AppCategory {
        return when(category) {
            "AI" -> AppCategory.ARTIFICIAL_INTELLIGENCE
            "Mail" -> AppCategory.E_MAIL
            "Messaging" -> AppCategory.MESSAGING
            else -> AppCategory.MISCELLANEOUS
        }
    }

    private fun compareAppCategoryConfigWithPackagename(
        packageName: String,
        context: Context
    ): AppCategory {
        appCategoryConfigLoader.load(context)
            .forEach { (category, packageNames) -> if (packageName in packageNames) return selectAppCategoryFromAppCategoryConfig(category) }
        return AppCategory.MISCELLANEOUS
    }
}