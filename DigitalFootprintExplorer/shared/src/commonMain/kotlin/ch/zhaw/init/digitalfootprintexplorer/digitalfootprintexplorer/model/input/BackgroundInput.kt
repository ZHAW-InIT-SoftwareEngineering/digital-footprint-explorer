package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input

import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.ProcessUsage

data class BackgroundInput(
    val activeProcesses: List<ProcessUsage>
)
