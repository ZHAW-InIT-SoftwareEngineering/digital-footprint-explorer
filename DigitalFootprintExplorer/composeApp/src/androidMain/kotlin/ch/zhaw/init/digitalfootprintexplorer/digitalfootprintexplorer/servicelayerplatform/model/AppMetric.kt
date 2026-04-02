package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model

data class AppMetric(
    val appName: String,
    val appCategory: AppCategory,
    val totalForegroundTime: Int = 0,
    val wifiBytes: Long,
    val mobileBytes: Long,
) {
    val totalBytes: Long
        get() = wifiBytes + mobileBytes
}
