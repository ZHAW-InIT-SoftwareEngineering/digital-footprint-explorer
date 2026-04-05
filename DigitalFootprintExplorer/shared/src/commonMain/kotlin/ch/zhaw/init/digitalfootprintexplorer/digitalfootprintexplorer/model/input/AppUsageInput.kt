package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input

import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.AppCategory
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.DataPoint

data class AppUsageInput(
    val appName: String,
    val appCategory: AppCategory,
    val totalForegroundTime: Int = 0,
    val wifiBytes: DataPoint,
    val cellularBytes: DataPoint,
)
