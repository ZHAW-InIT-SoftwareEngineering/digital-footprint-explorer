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

package ch.zhaw.digitalfootprintexplorer.model

/**
 * Represents an input value with its data quality.
 * Measured: directly measured by the OS.
 * Estimated: scientifically justified estimate as fallback.
 * Unavailable: value cannot be determined, no fallback available → treated as 0.0.
 */
sealed class DataPoint {
    data class Measured(val value: Double) : DataPoint()
    data class Estimated(val value: Double, val reason: String) : DataPoint()
    data class Unavailable(val reason: String) : DataPoint()

    fun valueOrDefault(default: Double = 0.0): Double = when (this) {
        is Measured -> value
        is Estimated -> value
        is Unavailable -> default
    }
}
