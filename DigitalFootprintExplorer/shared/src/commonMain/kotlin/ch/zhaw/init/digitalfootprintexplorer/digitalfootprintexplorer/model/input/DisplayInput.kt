package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input

data class BrightnessInterval(
    val normalizedBrightness: Double,
    val durationH: Double
)

data class DisplayInput(
    val intervals: List<BrightnessInterval>
)
