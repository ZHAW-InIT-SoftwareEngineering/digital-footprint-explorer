package ch.zhaw.digitalfootprintexplorer.model.output

/**
 * Overall result of the emissions calculation.
 * All values in kgCO2e.
 */
data class EmissionResult(
    val ghgAppUsage: Double,
    val ghgDisplay: Double,
    val ghgBackground: Double,
    val categoryBreakdown: List<CategoryEmission>
) {
    val ghgTotal: Double
        get() = ghgAppUsage + ghgDisplay + ghgBackground
}
