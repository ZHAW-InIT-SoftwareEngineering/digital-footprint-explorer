package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.model

data class Metric(
    val appName: String,
    val appCategory: AppCategory,
    val totalForegroundTime: Int,
    val dataVolumeInMB: Float,
    val networkType: NetworkType
)
