package ch.zhaw.digitalfootprintexplorer.servicelayerplatform.datasource

import android.content.Context
import android.content.Intent
import android.content.pm.ResolveInfo

class AndroidLauncherAppQuery: LauncherAppQuery {
    override fun create(context: Context): List<ResolveInfo> {
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        return context.packageManager.queryIntentActivities(intent, 0)
    }
}