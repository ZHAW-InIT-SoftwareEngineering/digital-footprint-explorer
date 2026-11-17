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

// [01] Keep usage time beside the traffic assumptions it uses. The traffic rate and Wi-Fi share are
// estimates, not Screen Time readings.
data class IosCategoryUsage(
    val category: String,
    val minutes: Double,
    val gigabytesPerHour: Double,
    val wifiShare: Double
)

// [02] The iOS screen needs the device, network and server parts of each category, all in kilograms of
// CO2e.
data class IosCategoryResult(
    val category: String,
    val totalKg: Double,
    val deviceKg: Double,
    val networkKg: Double,
    val backendKg: Double
)

data class IosFootprintResult(
    val totalKg: Double,
    val appUsageKg: Double,
    val displayKg: Double,
    val backgroundKg: Double,
    val categories: List<IosCategoryResult>
)

// [03] This is a bridge: iOS supplies minutes and assumptions, and the existing shared model does the
// emissions calculation.
class IosFootprintCalculator {

    // [04] Invalid inputs become errors Swift can handle, rather than ending the app unexpectedly.
    @Throws(IllegalArgumentException::class)
    fun calculate(
        usages: List<IosCategoryUsage>,
        brightness: Double,
        gpsHours: Double,
        bluetoothHours: Double
    ): IosFootprintResult = calculateForCalendarDay(usages, brightness, gpsHours, bluetoothHours, 1440.0)

    @Throws(IllegalArgumentException::class)
    // [05] Use the actual calendar-day length, so a daylight-saving change is not mistaken for excess
    // usage.
    fun calculateForCalendarDay(
        usages: List<IosCategoryUsage>,
        brightness: Double,
        gpsHours: Double,
        bluetoothHours: Double,
        calendarDayMinutes: Double
    ): IosFootprintResult {
        // [06] Reject broken day lengths and impossible inputs before they can produce a believable-looking
        // estimate.
        require(calendarDayMinutes.isFinite() && calendarDayMinutes > 0.0 && calendarDayMinutes <= 2880.0
            && calendarDayMinutes % 1.0 == 0.0) { "Calendar day minutes must be a positive whole duration of at most 48 hours." }
        requireUnitInterval(brightness, "Brightness")
        requireHours(gpsHours, "GPS hours")
        requireHours(bluetoothHours, "Bluetooth hours")

        usages.forEach { usage ->
            require(usage.minutes.isFinite() && usage.minutes >= 0.0) {
                "Usage minutes must be finite and nonnegative."
            }
            require(usage.gigabytesPerHour.isFinite() && usage.gigabytesPerHour >= 0.0) {
                "Traffic per hour must be finite and nonnegative."
            }
            requireUnitInterval(usage.wifiShare, "Wi-Fi share")
        }
        // [07] A day cannot contain more category time than its allowed span. Check the combined value as
        // well as each category.
        val totalMinutes = usages.sumOf { it.minutes }
        require(totalMinutes.isFinite() && totalMinutes <= calendarDayMinutes) {
            "Combined category usage cannot exceed the supplied calendar day."
        }

        val inputs = usages.map { usage ->
            val category = AppCategory.valueOf(usage.category)

            // [08] Use one rounded duration for both traffic and screen calculations, matching the seconds
            // used by the Android model.
            val seconds = (usage.minutes * 60.0).roundToInt()
            val totalBytes = seconds / 3600.0 * usage.gigabytesPerHour * 1_000_000_000.0
            require(totalBytes.isFinite()) { "The traffic estimate is too large." }
            AppUsageInput(
                appName = usage.category,
                appCategory = category,
                totalForegroundTime = seconds,
                // [09] Keep assumed traffic visibly marked Estimated; a calculation input is not proof that
                // the phone sent those bytes.
                wifiBytes = DataPoint.Estimated(
                    totalBytes * usage.wifiShare,
                    "Traffic estimated from the chosen GB/hour and Wi-Fi share"
                ),
                cellularBytes = DataPoint.Estimated(
                    totalBytes * (1.0 - usage.wifiShare),
                    "Traffic estimated from the chosen GB/hour and Wi-Fi share"
                )
            )
        }

        // [10] Screen energy follows the same total app duration, rather than quietly using a different
        // screen-time total.
        val screenHours = inputs.sumOf { it.totalForegroundTime }.toDouble() / 3600.0
        val result = EmissionsCalculator().calculate(
            inputs,
            DisplayInput(listOf(BrightnessInterval(brightness, screenHours))),

            // [11] Keep the original model's number precision for GPS and Bluetooth so the iOS bridge does
            // not change its results.
            BackgroundInput(listOf(
                ProcessUsage(BackgroundProcess.GPS, gpsHours.toFloat()),
                ProcessUsage(BackgroundProcess.BLUETOOTH, bluetoothHours.toFloat())
            ))
        )
        // [12] Very large numbers must fail clearly instead of reaching the garden as an unreadable or
        // infinite estimate.
        require(result.ghgTotal.isFinite()) { "The footprint estimate is too large." }
        return IosFootprintResult(
            totalKg = result.ghgTotal,
            appUsageKg = result.ghgAppUsage,
            displayKg = result.ghgDisplay,
            backgroundKg = result.ghgBackground,
            categories = result.categoryBreakdown.map { category ->
                IosCategoryResult(
                    category.category.name,
                    category.ghgTotal,
                    category.ghgDevice,
                    category.ghgNetwork,
                    category.ghgBackend
                )
            }
        )
    }

    private fun requireUnitInterval(value: Double, name: String) {
        require(value.isFinite() && value in 0.0..1.0) { "$name must be between 0 and 1." }
    }

    private fun requireHours(value: Double, name: String) {
        require(value.isFinite() && value in 0.0..24.0) { "$name must be between 0 and 24." }
    }
}
