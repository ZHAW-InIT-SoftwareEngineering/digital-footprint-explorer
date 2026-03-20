package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model

/**
 * Stores information about an installed app.
 */
data class App(
    val uid: Int,
    val name: String,
    val category: AppCategory
)
