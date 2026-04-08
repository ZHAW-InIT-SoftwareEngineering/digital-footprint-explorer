package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model

/**
 * Scientific constants of the emissions model.
 * EF = Emission Factor [kgCO2e/kWh]
 */
object ModelConstants {

    /* Emission factors [kgCO2e/kWh] */
    const val EF_SWISS = 0.127
    const val EF_GLOBAL = 0.471

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

    /**
     * Background processes \[W]
     *
     * TODO: fill in literature values after research.
     * TODO: other processes
     */
    val P_BACKGROUND_BY_PROCESS: Map<BackgroundProcess, Double> = mapOf(
        BackgroundProcess.GPS       to 0.2,
        BackgroundProcess.BLUETOOTH to 0.05

    )

    /**
     * Backend energy intensities
     *
     * TODO: fill in literature values after research.
     * TODO: assign Navigation to a proxy
     */
    val BACKEND_INTENSITY_GB: Map<AppCategory, Double> = mapOf(
        AppCategory.VIDEO_STREAMING  to 0.0,
        AppCategory.AUDIO_STREAMING  to 0.0,
        AppCategory.SOCIAL_MEDIA     to 0.0,
        AppCategory.VIDEO_CALL       to 0.0,
        AppCategory.MISCELLANEOUS    to 0.0
    )
    const val BACKEND_INTENSITY_PER_MESSAGE_MESSAGING = 0.0
    const val BACKEND_INTENSITY_PER_MESSAGE_EMAIL = 0.0
    const val BACKEND_INTENSITY_PER_QUERY_AI = 0.0
    const val BACKEND_INTENSITY_PER_HOUR_GAMING = 0.0
}
