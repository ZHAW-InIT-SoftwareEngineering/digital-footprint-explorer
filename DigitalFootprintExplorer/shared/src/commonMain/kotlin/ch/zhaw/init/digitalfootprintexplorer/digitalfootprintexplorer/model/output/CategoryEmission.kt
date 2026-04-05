package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.output

import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.AppCategory

data class CategoryEmission(
    val category: AppCategory,
    val ghgDevice: Double,
    val ghgNetwork: Double,
    val ghgBackend: Double
) {
    val ghgTotal: Double
        get() = ghgDevice + ghgNetwork + ghgBackend
}
