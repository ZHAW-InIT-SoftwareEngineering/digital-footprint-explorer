package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model

/**
 * Scientific constants of the emissions model.
 * EF = Emission Factor [kgCO2e/kWh]
 */
object ModelConstants {

    /* Emission factors [kgCO2e/kWh] */
    const val EF_SWISS = 0.0392
    const val EF_GLOBAL = 0.458

    /* Charging loss */
    const val CHARGING_EFFICIENCY = 0.585

    /* Network intensity [kWh/GB] */
    const val NETWORK_INTENSITY_WIFI = 0.006
    const val NETWORK_INTENSITY_CELLULAR = 0.055

    /* Device power consumption P_device [W] per category */
    val P_DEVICE_BY_CATEGORY: Map<AppCategory, Double> = mapOf(
        AppCategory.VIDEO_STREAMING      to 1.0,
        AppCategory.AUDIO_STREAMING      to 0.5,
        AppCategory.SOCIAL_MEDIA         to 1.7,
        AppCategory.MESSAGING            to 0.6,
        AppCategory.ARTIFICIAL_INTELLIGENCE to 0.5,
        AppCategory.E_MAIL               to 0.5,
        AppCategory.VIDEO_CALL           to 4.0,
        AppCategory.GAMING               to 1.3,
        AppCategory.NAVIGATION           to 0.9,
        AppCategory.MISCELLANEOUS        to 0.5
    )

    /**
     * Display
     *
     * Maximum display power at brightness=1.0 \[W]
     */
    const val P_DISPLAY_MAX_WATT = 0.4

    /** Background processes \[W] */
    val P_BACKGROUND_BY_PROCESS: Map<BackgroundProcess, Double> = mapOf(
        BackgroundProcess.GPS       to 0.3,
        BackgroundProcess.BLUETOOTH to 0.04
    )

    /** Backend energy intensity [kWh/GB] — single GB proxy applied uniformly across all categories. */
    const val BACKEND_INTENSITY_GB = 0.055

    /** Per-category multiplier applied to the backend intensity [kWh/GB]. */
    val BACKEND_INTENSITY_FACTOR_BY_CATEGORY: Map<AppCategory, Double> = mapOf(
        AppCategory.ARTIFICIAL_INTELLIGENCE to 10.0
    )
}
