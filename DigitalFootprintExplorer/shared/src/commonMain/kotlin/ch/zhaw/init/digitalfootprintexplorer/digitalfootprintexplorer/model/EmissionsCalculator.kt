package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model

import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input.AppUsageInput
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input.BackgroundInput
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input.DisplayInput
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.output.CategoryEmission
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.output.EmissionResult

/**
 * Calculates the CO2 footprint of smartphone usage.
 *
 * Model formula (Thesis Ch. 3):
 *   GHG_total = GHG_appUsage + GHG_display + GHG_background
 *
 * @param userEmissionFactor Emission factor of the user's electricity mix [kgCO2e/kWh].
 *   Default: Swiss electricity mix. Configurable later.
 */
class EmissionsCalculator(
    private val userEmissionFactor: Double = ModelConstants.EF_SWISS
) {

    fun calculate(
        appUsage: List<AppUsageInput>,
        display: DisplayInput,
        background: BackgroundInput
    ): EmissionResult {
        val categoryBreakdown = calculateAppUsage(appUsage)
        return EmissionResult(
            ghgAppUsageKgCO2e = categoryBreakdown.fold(0.0) { acc, c -> acc + c.ghgTotalKgCO2e },
            ghgDisplayKgCO2e = calculateDisplay(display),
            ghgBackgroundKgCO2e = calculateBackground(background),
            categoryBreakdown = categoryBreakdown
        )
    }

    // -------------------------------------------------------------------------
    // Block 1: App usage
    // GHG_appUsage = Σ_k [GHG_device,k + GHG_network,k + GHG_backend,k]
    // -------------------------------------------------------------------------

    private fun calculateAppUsage(metrics: List<AppUsageInput>): List<CategoryEmission> {
        // Aggregate by category
        return metrics
            .groupBy { it.appCategory }
            .map { (category, entries) ->
                val totalTimeH = entries.sumOf { it.totalForegroundTime } / 60.0
                val totalWifiGB = entries.fold(0.0) { acc, m -> acc + m.wifiBytes.valueOrDefault() } / 1_000_000_000.0
                val totalCellularGB = entries.fold(0.0) { acc, m -> acc + m.cellularBytes.valueOrDefault() } / 1_000_000_000.0

                CategoryEmission(
                    category = category,
                    ghgDeviceKgCO2e = calculateDevice(category, totalTimeH),
                    ghgNetworkKgCO2e = calculateNetwork(totalWifiGB, totalCellularGB),
                    ghgBackendKgCO2e = calculateBackend(category, totalWifiGB + totalCellularGB, totalTimeH)
                )
            }
    }

    /**
     * GHG_device,k = P_device,k [W] * t_k [h] / 1000 * (1/η) * EF_user
     */
    private fun calculateDevice(category: AppCategory, timeH: Double): Double {
        val pWatt = ModelConstants.P_DEVICE_BY_CATEGORY[category]
            ?: ModelConstants.P_DEVICE_BY_CATEGORY[AppCategory.MISCELLANEOUS]!!
        val energyKwh = pWatt * timeH / 1000.0
        return energyKwh / ModelConstants.CHARGING_EFFICIENCY * userEmissionFactor
    }

    /**
     * GHG_network,k = (wifiGB * I_WIFI + cellularGB * I_CELLULAR) * EF_global
     *
     * Wi-Fi and cellular are calculated separately because their energy intensity
     * differs significantly (factor ~9x).
     */
    private fun calculateNetwork(wifiGB: Double, cellularGB: Double): Double {
        val energyKwh =
            wifiGB * ModelConstants.NETWORK_INTENSITY_WIFI +
            cellularGB * ModelConstants.NETWORK_INTENSITY_CELLULAR
        return energyKwh * ModelConstants.EF_GLOBAL
    }

    /**
     * GHG_backend,k = E_backend,k * EF_global
     *
     * Proxy varies by category (TODO: values pending literature review).
     * Currently 0.0 for all categories – structure is implemented.
     */
    private fun calculateBackend(category: AppCategory, totalDataGB: Double, timeH: Double): Double {
        val eBackendKwh = when (category) {
            AppCategory.VIDEO_STREAMING,
            AppCategory.AUDIO_STREAMING,
            AppCategory.SOCIAL_MEDIA,
            AppCategory.VIDEO_CALL,
            AppCategory.MISCELLANEOUS -> {
                // Proxy: kWh/GB
                totalDataGB * (ModelConstants.BACKEND_INTENSITY_GB[category] ?: 0.0)
            }
            AppCategory.MESSAGING -> {
                // Proxy: kWh/message (TODO: estimate message count from data volume)
                0.0
            }
            AppCategory.E_MAIL -> {
                // Proxy: kWh/message (TODO)
                0.0
            }
            AppCategory.ARTIFICIAL_INTELLIGENCE -> {
                // Proxy: kWh/query (TODO: ~50–80 KB/query → count estimable from data volume)
                0.0
            }
            AppCategory.GAMING -> {
                // Proxy: kWh/h
                timeH * ModelConstants.BACKEND_INTENSITY_PER_HOUR_GAMING
            }
            AppCategory.NAVIGATION -> {
                // Proxy: not yet defined
                0.0
            }
        }
        return eBackendKwh * ModelConstants.EF_GLOBAL
    }

    // -------------------------------------------------------------------------
    // Block 2: Display
    // E_display [Wh] = P_display [W] * Σ_i (B̃_i * Δt_i [h])
    // GHG_display = E_display/1000 * (1/η) * EF_user
    // -------------------------------------------------------------------------

    private fun calculateDisplay(display: DisplayInput): Double {
        val energyWh = ModelConstants.P_DISPLAY_MAX_WATT *
            display.intervals.fold(0.0) { acc, i -> acc + i.normalizedBrightness * i.durationH }
        val energyKwh = energyWh / 1000.0
        return energyKwh / ModelConstants.CHARGING_EFFICIENCY * userEmissionFactor
    }

    // -------------------------------------------------------------------------
    // Block 3: Background processes
    // GHG_background = Σ_p (P_p [W] * t_p [h] / 1000 * (1/η) * EF_user)
    // -------------------------------------------------------------------------

    private fun calculateBackground(background: BackgroundInput): Double {
        return background.activeProcesses.fold(0.0) { acc, proc ->
            val pWatt = ModelConstants.P_BACKGROUND_BY_PROCESS[proc.process] ?: 0.0
            val energyKwh = pWatt * proc.durationH / 1000.0
            acc + energyKwh / ModelConstants.CHARGING_EFFICIENCY * userEmissionFactor
        }
    }
}
