package ch.zhaw.digitalfootprintexplorer.servicelayerplatform.model

import ch.zhaw.digitalfootprintexplorer.model.AppCategory

/**
 * Stores information about an installed app.
 */
data class App(
    val uid: Int,
    val name: String,
    val packageName: String,
    val category: AppCategory
)
