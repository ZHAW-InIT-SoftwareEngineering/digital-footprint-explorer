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

// [01] A category keeps its traffic rate and Wi-Fi share together, so the starting calculation uses the
// intended pair.
data class IosCategoryAssumption(
    val category: String,
    val gigabytesPerHour: Double,
    val wifiShare: Double
)

// [02] These starting values are model assumptions, not measured traffic or population averages. Decimal GB
// means one billion bytes.
class IosUsageAssumptions {
    val defaults: List<IosCategoryAssumption> = listOf(

        // [03] Netflix Medium gives an example of up to 0.7 GB per hour, not an average for all video apps.
        // https://help.netflix.com/en/node/87 — checked 2026-10-07
        IosCategoryAssumption(AppCategory.VIDEO_STREAMING.name, 0.7, 0.8),

        // [04] Spotify Normal mobile audio uses about 96 kbit/s: 0.0432 GB per hour before extra traffic.
        // https://support.spotify.com/ca-en/article/audio-quality/ — checked 2026-10-07
        IosCategoryAssumption(AppCategory.AUDIO_STREAMING.name, 0.0432, 0.8),

        // [05] The remaining rates and every 80% Wi-Fi share are example scenarios, not measured traffic.
        // App durations come from Screen Time; traffic stays an explicit model assumption.
        IosCategoryAssumption(AppCategory.SOCIAL_MEDIA.name, 0.2, 0.8),
        IosCategoryAssumption(AppCategory.MESSAGING.name, 0.01, 0.8),
        IosCategoryAssumption(AppCategory.ARTIFICIAL_INTELLIGENCE.name, 0.005, 0.8),
        IosCategoryAssumption(AppCategory.E_MAIL.name, 0.01, 0.8),
        IosCategoryAssumption(AppCategory.VIDEO_CALL.name, 0.5, 0.8),
        IosCategoryAssumption(AppCategory.GAMING.name, 0.05, 0.8),
        IosCategoryAssumption(AppCategory.NAVIGATION.name, 0.02, 0.8),
        IosCategoryAssumption(AppCategory.MISCELLANEOUS.name, 0.05, 0.8)
    )
}
