package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model

enum class GardenState {
    FLOURISHING,
    GROWING,
    STABLE,
    WILTING,
    WITHERED;

    companion object {
        fun fromEmissions(kgCO2e: Double): GardenState = when {
            kgCO2e < 0.5 -> FLOURISHING
            kgCO2e < 1.5 -> GROWING
            kgCO2e < 3.0 -> STABLE
            kgCO2e < 6.0 -> WILTING
            else          -> WITHERED
        }
    }
}