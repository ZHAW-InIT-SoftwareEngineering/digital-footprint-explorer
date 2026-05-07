package ch.zhaw.digitalfootprintexplorer.model

import kotlinx.datetime.LocalDate

data class DailyFootprintEntry(
    val date: LocalDate,
    val kgCO2e: Double,
    val ghgAppUsage: Double,
    val ghgDisplay: Double,
    val ghgBackground: Double,
    val measuredAt: String
)