package ch.zhaw.digitalfootprintexplorer.model

enum class BackgroundProcess {
    GPS,
    BLUETOOTH
}

data class ProcessUsage(
    val process: BackgroundProcess,
    val durationH: Float
)
