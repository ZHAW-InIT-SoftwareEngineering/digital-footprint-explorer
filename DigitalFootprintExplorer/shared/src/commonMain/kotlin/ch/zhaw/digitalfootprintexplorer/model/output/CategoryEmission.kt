package ch.zhaw.digitalfootprintexplorer.model.output

import ch.zhaw.digitalfootprintexplorer.model.AppCategory

data class CategoryEmission(
    val category: AppCategory,
    val ghgDevice: Double,
    val ghgNetwork: Double,
    val ghgBackend: Double
) {
    val ghgTotal: Double
        get() = ghgDevice + ghgNetwork + ghgBackend
}
