package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.datasource

import android.content.Context
import android.content.pm.ResolveInfo

/**
 * Interface for creating launcher app queries.
 * Will be used for injecting the correct query in the app.
 */
interface LauncherAppQuery {
    fun create(context: Context): List<ResolveInfo>
}