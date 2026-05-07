package ch.zhaw.digitalfootprintexplorer.model.input

import ch.zhaw.digitalfootprintexplorer.model.ProcessUsage

data class BackgroundInput(
    val activeProcesses: List<ProcessUsage>
)
