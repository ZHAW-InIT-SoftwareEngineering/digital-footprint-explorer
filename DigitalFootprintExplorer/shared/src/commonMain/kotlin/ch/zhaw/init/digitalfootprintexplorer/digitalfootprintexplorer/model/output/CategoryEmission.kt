package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.output

import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.AppCategory

data class CategoryEmission(
    val category: AppCategory,
    val ghgDeviceKgCO2e: Double,
    val ghgNetworkKgCO2e: Double,
    val ghgBackendKgCO2e: Double
) {
    val ghgTotalKgCO2e: Double
        get() = ghgDeviceKgCO2e + ghgNetworkKgCO2e + ghgBackendKgCO2e
}
