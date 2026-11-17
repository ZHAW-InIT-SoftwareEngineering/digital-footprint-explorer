/*
 * Copyright (C) 2026 Zurich University of Applied Sciences, Switzerland
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package ch.zhaw.digitalfootprintexplorer.ios

import ch.zhaw.digitalfootprintexplorer.model.AppCategory
import ch.zhaw.digitalfootprintexplorer.model.BackgroundProcess
import ch.zhaw.digitalfootprintexplorer.model.DataPoint
import ch.zhaw.digitalfootprintexplorer.model.EmissionsCalculator
import ch.zhaw.digitalfootprintexplorer.model.ProcessUsage
import ch.zhaw.digitalfootprintexplorer.model.input.AppUsageInput
import ch.zhaw.digitalfootprintexplorer.model.input.BackgroundInput
import ch.zhaw.digitalfootprintexplorer.model.input.BrightnessInterval
import ch.zhaw.digitalfootprintexplorer.model.input.DisplayInput
import kotlin.math.roundToInt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

// [01] These fixed, made-up cases check that the iOS bridge keeps the Android model's maths and labels
// assumed traffic honestly.
class IosFootprintCalculatorTest {
    private val calculator = IosFootprintCalculator()

    // [02] Use a fixed traffic rate here, so changing the app's starting assumptions cannot silently change
    // the expected answer.
    private val video = IosCategoryUsage("VIDEO_STREAMING", 60.0, 1.0, 0.8)

    @Test
    // [03] A longer calendar day must accept its real capacity without clipping valid usage or changing the
    // model rates.
    fun `a long calendar day uses the original emission maths without clipping`() {
        val hour = calculator.calculate(listOf(video), 0.5, 0.0, 0.0)
        val longDay = calculator.calculateForCalendarDay(listOf(video.copy(minutes = 1450.0)),
            0.5, 0.0, 0.0, 1500.0)
        assertEquals(hour.totalKg * 1450.0 / 60.0, longDay.totalKg, 1e-10)
        assertEquals(hour.appUsageKg * 1450.0 / 60.0, longDay.appUsageKg, 1e-10)
        assertEquals(hour.displayKg * 1450.0 / 60.0, longDay.displayKg, 1e-10)
        assertFailsWith<IllegalArgumentException> {
            calculator.calculate(listOf(video.copy(minutes = 1450.0)), 0.5, 0.0, 0.0)
        }
    }

    @Test
    // [04] Invalid day lengths and excess combined usage must fail clearly instead of producing a
    // believable-looking total.
    fun `actual day limits reject excess time and invalid capacity metadata`() {
        for (capacity in listOf(1380.0, 1440.0, 1500.0)) {
            calculator.calculateForCalendarDay(listOf(video.copy(minutes = capacity)),
                0.5, 0.0, 0.0, capacity)
            assertFailsWith<IllegalArgumentException> {
                calculator.calculateForCalendarDay(listOf(video.copy(minutes = capacity + 1)),
                    0.5, 0.0, 0.0, capacity)
            }
        }
        for (invalid in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY,
            0.0, -1.0, 1500.5, 2881.0)) {
            assertFailsWith<IllegalArgumentException> {
                calculator.calculateForCalendarDay(listOf(video), 0.5, 0.0, 0.0, invalid)
            }
        }
    }

    @Test
    // [05] Supplying an ordinary day explicitly should keep the original bridge result unchanged.
    fun `explicit ordinary day retains the original adapter result`() {
        assertEquals(calculator.calculate(listOf(video), 0.63, 1.125, 8.25),
            calculator.calculateForCalendarDay(listOf(video), 0.63, 1.125, 8.25, 1440.0))
    }

    @Test
    // [06] A simple hour-long example catches accidental changes to units, charging losses or fixed model
    // values.
    fun `one hour fixture retains the original coefficients and units`() {
        val result = calculator.calculate(listOf(video), 0.5, 0.25, 2.0)
        assertEquals(0.03251719658119658, result.totalKg, 1e-12)
        assertEquals(0.03249340854700855, result.appUsageKg, 1e-12)
        assertEquals(0.000013401709401709404, result.displayKg, 1e-12)
        assertEquals(0.000010386324786324786, result.backgroundKg, 1e-12)
        val category = result.categories.single()
        assertEquals("VIDEO_STREAMING", category.category)
        assertEquals(0.00006700854700854701, category.deviceKg, 1e-12)
        assertEquals(0.0072364, category.networkKg, 1e-12)
        assertEquals(0.02519, category.backendKg, 1e-12)
    }

    @Test
    // [07] Each iOS category must reach the same answer as an equivalent direct input to the Android
    // calculation.
    fun `all category iOS inputs match equivalent raw Android model inputs`() {
        val scenarios = AppCategory.entries.mapIndexed { index, category ->
            IosCategoryUsage(category.name, 17.0 + index * 3.5, 0.0125 * (index + 1), index / 10.0)
        }
        assertMatchesAndroid(scenarios, brightness = 0.63, gpsHours = 1.125, bluetoothHours = 8.25)
    }

    @Test
    // [08] A fraction of a minute must round to the same shared seconds before screen and traffic estimates
    // are compared.
    fun `fractional minutes round to shared model seconds and retain parity`() {
        assertMatchesAndroid(
            listOf(video.copy(minutes = 0.12345), video.copy(minutes = 0.5)),
            brightness = 1.0, gpsHours = 0.0, bluetoothHours = 0.0
        )
        val singleSecond = calculator.calculate(listOf(video.copy(minutes = 1.0 / 60.0)), 0.0, 0.0, 0.0)
        val hour = calculator.calculate(listOf(video), 0.0, 0.0, 0.0)
        assertEquals(hour.appUsageKg / 3600.0, singleSecond.appUsageKg, 1e-12)
    }

    @Test
    // [09] Two entries in one category should combine just as they do in the original model.
    fun `duplicate categories aggregate like Android`() {
        val split = calculator.calculate(listOf(video.copy(minutes = 30.0), video.copy(minutes = 30.0)), 0.5, 0.0, 0.0)
        val merged = calculator.calculate(listOf(video), 0.5, 0.0, 0.0)
        assertEquals(1, split.categories.size)
        assertEquals(merged.totalKg, split.totalKg, 1e-12)
    }

    @Test
    // [10] No supplied use should leave every contribution at zero, not only the overall total.
    fun `zero inputs produce zero for every component`() {
        val result = calculator.calculate(emptyList(), 0.5, 0.0, 0.0)
        assertEquals(0.0, result.totalKg)
        assertEquals(0.0, result.appUsageKg)
        assertEquals(0.0, result.displayKg)
        assertEquals(0.0, result.backgroundKg)
        assertTrue(result.categories.isEmpty())
    }

    @Test
    // [11] Changing assumed traffic should change network and server estimates, while leaving device power
    // for the same usage time alone.
    fun `traffic assumptions change network and backend but keep device power`() {
        val low = calculator.calculate(listOf(video.copy(gigabytesPerHour = 0.1)), 0.5, 0.0, 0.0)
        val high = calculator.calculate(listOf(video.copy(gigabytesPerHour = 2.0)), 0.5, 0.0, 0.0)
        assertEquals(low.displayKg, high.displayKg)
        assertEquals(low.categories.single().deviceKg, high.categories.single().deviceKg)
        assertEquals(20.0 * low.categories.single().networkKg, high.categories.single().networkKg, 1e-12)
        assertEquals(20.0 * low.categories.single().backendKg, high.categories.single().backendKg, 1e-12)
    }

    @Test
    // [12] A Wi-Fi share change affects network energy, but the same overall traffic still reaches the
    // server calculation.
    fun `cellular traffic increases network emissions without changing backend`() {
        val wifi = calculator.calculate(listOf(video.copy(wifiShare = 1.0)), 0.0, 0.0, 0.0)
        val cellular = calculator.calculate(listOf(video.copy(wifiShare = 0.0)), 0.0, 0.0, 0.0)
        assertTrue(cellular.categories.single().networkKg > wifi.categories.single().networkKg)
        assertEquals(wifi.categories.single().backendKg, cellular.categories.single().backendKg)
    }

    @Test
    // [13] GPS and Bluetooth time is separate from screen time, so the bridge must not replace one with the
    // other.
    fun `background durations remain independent of screen time`() {
        assertMatchesAndroid(emptyList(), brightness = 0.8, gpsHours = 24.0, bluetoothHours = 24.0)
        val result = calculator.calculate(emptyList(), 0.8, 24.0, 24.0)
        assertEquals(0.0, result.displayKg)
        assertTrue(result.backgroundKg > 0.0)
    }

    @Test
    // [14] Unknown categories and an impossible daily total should be rejected before they reach the model.
    fun `invalid category and combined duration are rejected`() {
        assertFailsWith<IllegalArgumentException> { calculator.calculate(listOf(video.copy(category = "unknown")), 0.5, 0.0, 0.0) }
        assertFailsWith<IllegalArgumentException> { calculator.calculate(listOf(video.copy(minutes = 1000.0), video.copy(minutes = 500.0)), 0.5, 0.0, 0.0) }
        assertFailsWith<IllegalArgumentException> { calculator.calculate(listOf(video.copy(minutes = -0.1)), 0.5, 0.0, 0.0) }
        calculator.calculate(listOf(video.copy(minutes = 1440.0)), 1.0, 24.0, 24.0)
    }

    @Test
    // [15] Every numeric input needs the same protection against unreadable values such as infinity.
    fun `nonfinite values are rejected in every input field`() {
        for (invalid in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY)) {
            assertFailsWith<IllegalArgumentException> { calculator.calculate(listOf(video.copy(minutes = invalid)), 0.5, 0.0, 0.0) }
            assertFailsWith<IllegalArgumentException> { calculator.calculate(listOf(video.copy(gigabytesPerHour = invalid)), 0.5, 0.0, 0.0) }
            assertFailsWith<IllegalArgumentException> { calculator.calculate(listOf(video.copy(wifiShare = invalid)), 0.5, 0.0, 0.0) }
            assertFailsWith<IllegalArgumentException> { calculator.calculate(listOf(video), invalid, 0.0, 0.0) }
            assertFailsWith<IllegalArgumentException> { calculator.calculate(listOf(video), 0.5, invalid, 0.0) }
            assertFailsWith<IllegalArgumentException> { calculator.calculate(listOf(video), 0.5, 0.0, invalid) }
        }
    }

    @Test
    // [16] Shares, hours and traffic must stay within usable limits; very large calculations should fail
    // rather than return infinity.
    fun `out of range shares hours and traffic overflow are rejected`() {
        for (invalid in listOf(-0.1, 1.1)) {
            assertFailsWith<IllegalArgumentException> { calculator.calculate(listOf(video.copy(wifiShare = invalid)), 0.5, 0.0, 0.0) }
            assertFailsWith<IllegalArgumentException> { calculator.calculate(listOf(video), invalid, 0.0, 0.0) }
        }
        for (invalid in listOf(-0.1, 24.1)) {
            assertFailsWith<IllegalArgumentException> { calculator.calculate(listOf(video), 0.5, invalid, 0.0) }
            assertFailsWith<IllegalArgumentException> { calculator.calculate(listOf(video), 0.5, 0.0, invalid) }
        }
        assertFailsWith<IllegalArgumentException> { calculator.calculate(listOf(video.copy(gigabytesPerHour = -1.0)), 0.5, 0.0, 0.0) }
        assertFailsWith<IllegalArgumentException> { calculator.calculate(listOf(video.copy(gigabytesPerHour = Double.MAX_VALUE)), 0.5, 0.0, 0.0) }
    }

    @Test
    // [17] Starting assumptions should cover each model category once, without a gap or duplicate.
    fun `editable defaults cover every original model category exactly once`() {
        val defaults = IosUsageAssumptions().defaults
        assertEquals(AppCategory.entries.map { it.name }.toSet(), defaults.map { it.category }.toSet())
        assertEquals(AppCategory.entries.size, defaults.size)
        assertTrue(defaults.all { it.gigabytesPerHour >= 0.0 && it.wifiShare in 0.0..1.0 })
    }

    // [18] Build equivalent direct model inputs from these made-up values. They are test fixtures, not
    // measurements from a phone.
    private fun assertMatchesAndroid(usages: List<IosCategoryUsage>, brightness: Double, gpsHours: Double, bluetoothHours: Double) {

        val rawInputs = usages.map { usage ->
            val seconds = (usage.minutes * 60.0).roundToInt()
            val bytes = seconds / 3600.0 * usage.gigabytesPerHour * 1_000_000_000.0
            AppUsageInput(
                usage.category, AppCategory.valueOf(usage.category), seconds,
                DataPoint.Measured(bytes * usage.wifiShare),
                DataPoint.Measured(bytes * (1.0 - usage.wifiShare))
            )
        }
        val raw = EmissionsCalculator().calculate(
            rawInputs,
            DisplayInput(listOf(BrightnessInterval(brightness, rawInputs.sumOf { it.totalForegroundTime } / 3600.0))),
            BackgroundInput(listOf(
                ProcessUsage(BackgroundProcess.GPS, gpsHours.toFloat()),
                ProcessUsage(BackgroundProcess.BLUETOOTH, bluetoothHours.toFloat())
            ))
        )
        val ios = calculator.calculate(usages, brightness, gpsHours, bluetoothHours)
        assertEquals(raw.ghgTotal, ios.totalKg, 1e-12)
        assertEquals(raw.ghgAppUsage, ios.appUsageKg, 1e-12)
        assertEquals(raw.ghgDisplay, ios.displayKg, 1e-12)
        assertEquals(raw.ghgBackground, ios.backgroundKg, 1e-12)
        assertEquals(raw.categoryBreakdown.size, ios.categories.size)
        raw.categoryBreakdown.zip(ios.categories).forEach { (expected, actual) ->
            assertEquals(expected.category.name, actual.category)
            assertEquals(expected.ghgTotal, actual.totalKg, 1e-12)
            assertEquals(expected.ghgDevice, actual.deviceKg, 1e-12)
            assertEquals(expected.ghgNetwork, actual.networkKg, 1e-12)
            assertEquals(expected.ghgBackend, actual.backendKg, 1e-12)
        }
    }
}
