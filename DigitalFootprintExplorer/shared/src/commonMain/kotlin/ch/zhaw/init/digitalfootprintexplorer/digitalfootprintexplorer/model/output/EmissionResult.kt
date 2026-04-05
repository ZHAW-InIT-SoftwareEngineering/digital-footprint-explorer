package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.output

/**
 * Overall result of the emissions calculation.
 * All values in kgCO2e.
 */
data class EmissionResult(
    val ghgAppUsageKgCO2e: Double,
    val ghgDisplayKgCO2e: Double,
    val ghgBackgroundKgCO2e: Double,
    val categoryBreakdown: List<CategoryEmission>
) {
    val ghgTotalKgCO2e: Double
        get() = ghgAppUsageKgCO2e + ghgDisplayKgCO2e + ghgBackgroundKgCO2e
}
