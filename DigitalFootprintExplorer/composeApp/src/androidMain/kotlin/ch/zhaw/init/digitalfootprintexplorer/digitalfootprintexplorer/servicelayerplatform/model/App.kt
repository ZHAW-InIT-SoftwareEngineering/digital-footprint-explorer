package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model

import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.AppCategory

/**
 * Stores information about an installed app.
 */
data class App(
    val uid: Int,
    val name: String,
    val category: AppCategory
)
