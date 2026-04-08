package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model

import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input.AppUsageInput
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input.BackgroundInput
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input.BrightnessInterval
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.input.DisplayInput
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.output.EmissionResult
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

private fun Long.dp() = DataPoint.Measured(this.toDouble())

class EmissionsCalculatorTest {

    private val calculator = EmissionsCalculator()
    private val emptyDisplay = DisplayInput(emptyList())
    private val emptyBackground = BackgroundInput(emptyList())

    @Test
    fun `zero input yields zero emissions`() {
        val result = calculator.calculate(emptyList(), emptyDisplay, emptyBackground)
        assertEquals(0.0, result.ghgTotal)
        assertEquals(0.0, result.ghgAppUsage)
        assertEquals(0.0, result.ghgDisplay)
        assertEquals(0.0, result.ghgBackground)
    }

    @Test
    fun `1h video streaming over wifi yields positive value`() {
        val metric = AppUsageInput(
            appName = "Netflix",
            appCategory = AppCategory.VIDEO_STREAMING,
            totalForegroundTime = 60, /* 1 hour in minutes */
            wifiBytes = 2_700_000_000L.dp(), /* ~2.7 GB/h typical for HD */
            cellularBytes = 0L.dp()
        )
        val result = calculator.calculate(listOf(metric), emptyDisplay, emptyBackground)
        assertTrue(result.ghgAppUsage > 0.0)
        val wifiGB = 2_700_000_000.0 / 1_000_000_000.0
        val timeH = 60.0 / 60.0
        val expectedDevice = ModelConstants.P_DEVICE_BY_CATEGORY[AppCategory.VIDEO_STREAMING]!! *
            timeH / 1000.0 / ModelConstants.CHARGING_EFFICIENCY * ModelConstants.EF_SWISS
        val expectedNetwork = wifiGB * ModelConstants.NETWORK_INTENSITY_WIFI * ModelConstants.EF_GLOBAL
        assertEquals(expectedDevice + expectedNetwork, result.ghgAppUsage, absoluteTolerance = 1e-9)
    }

    @Test
    fun `cellular is more energy intensive than wifi`() {
        val wifiMetric = AppUsageInput("App", AppCategory.VIDEO_STREAMING, 60,
            wifiBytes = 1_000_000_000L.dp(), cellularBytes = 0L.dp())
        val cellMetric = AppUsageInput("App", AppCategory.VIDEO_STREAMING, 60,
            wifiBytes = 0L.dp(), cellularBytes = 1_000_000_000L.dp())

        val wifiResult = calculator.calculate(listOf(wifiMetric), emptyDisplay, emptyBackground)
        val cellResult = calculator.calculate(listOf(cellMetric), emptyDisplay, emptyBackground)

        assertTrue(cellResult.ghgNetwork(cellMetric) > wifiResult.ghgNetwork(wifiMetric))
    }

    @Test
    fun `only display input yields ghg only for display`() {
        val display = DisplayInput(listOf(BrightnessInterval(0.5, 1.0))) // 50% brightness, 1h
        val result = calculator.calculate(emptyList(), display, emptyBackground)
        assertEquals(0.0, result.ghgAppUsage)
        /* 0.4W * 0.5 * 1h / 1000 / 0.585 * 0.127 = ~0.0000434 kgCO2e */
        assertEquals(0.0000434, result.ghgDisplay, absoluteTolerance = 0.000001)
    }

    @Test
    fun `multiple apps of same category are aggregated correctly`() {
        val metrics = listOf(
            AppUsageInput("Netflix", AppCategory.VIDEO_STREAMING, 30, 500_000_000L.dp(), 0L.dp()),
            AppUsageInput("YouTube", AppCategory.VIDEO_STREAMING, 30, 500_000_000L.dp(), 0L.dp())
        )
        val resultAggregated = calculator.calculate(metrics, emptyDisplay, emptyBackground)

        val singleMetric = AppUsageInput("Combined", AppCategory.VIDEO_STREAMING, 60, 1_000_000_000L.dp(), 0L.dp())
        val resultSingle = calculator.calculate(listOf(singleMetric), emptyDisplay, emptyBackground)

        assertEquals(resultSingle.ghgTotal, resultAggregated.ghgTotal, absoluteTolerance = 1e-10)
    }

    @Test
    fun `ghg total is sum of the three components`() {
        val metric = AppUsageInput("App", AppCategory.SOCIAL_MEDIA, 60, 100_000_000L.dp(), 0L.dp())
        val display = DisplayInput(listOf(BrightnessInterval(0.7, 0.5)))
        val background = BackgroundInput(listOf(ProcessUsage(BackgroundProcess.GPS, 1.0f)))

        val result = calculator.calculate(listOf(metric), display, background)
        val expectedTotal = result.ghgAppUsage + result.ghgDisplay + result.ghgBackground
        assertEquals(expectedTotal, result.ghgTotal, absoluteTolerance = 1e-10)
    }

    /* Helper functions for the cellular test */
    private fun EmissionResult.ghgNetwork(metric: AppUsageInput): Double =
        categoryBreakdown.firstOrNull { it.category == metric.appCategory }?.ghgNetwork ?: 0.0
}
