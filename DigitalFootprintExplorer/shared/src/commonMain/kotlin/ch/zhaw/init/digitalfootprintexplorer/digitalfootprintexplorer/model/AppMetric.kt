package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model

data class AppMetric(
    val appName: String,
    val appCategory: AppCategory,
    val totalForegroundTime: Int = 0,
    val wifiBytes: Long,
    val cellularBytes: Long,
) {
    val totalBytes: Long
        get() = wifiBytes + cellularBytes
}