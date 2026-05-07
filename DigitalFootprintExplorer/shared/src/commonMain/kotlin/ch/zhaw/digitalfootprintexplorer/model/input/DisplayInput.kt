package ch.zhaw.digitalfootprintexplorer.model.input

data class BrightnessInterval(
    val normalizedBrightness: Double,
    val durationH: Double
)

data class DisplayInput(
    val intervals: List<BrightnessInterval>
)
