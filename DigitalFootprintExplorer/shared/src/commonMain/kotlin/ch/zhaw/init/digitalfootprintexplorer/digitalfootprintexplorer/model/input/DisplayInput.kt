package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input

data class BrightnessInterval(
    val normalizedBrightness: Float,
    val durationH: Float
)

data class DisplayInput(
    val intervals: List<BrightnessInterval>
)
