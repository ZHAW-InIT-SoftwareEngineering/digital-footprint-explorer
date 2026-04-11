package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model

import kotlinx.datetime.LocalDate

data class DailyFootprintEntry(val date: LocalDate, val kgCO2e: Double)
