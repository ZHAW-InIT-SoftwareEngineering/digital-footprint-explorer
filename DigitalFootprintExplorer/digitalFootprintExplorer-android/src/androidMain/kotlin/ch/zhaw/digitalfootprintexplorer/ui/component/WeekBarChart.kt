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

package ch.zhaw.digitalfootprintexplorer.ui.component

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import ch.zhaw.digitalfootprintexplorer.ui.theme.pieChartAppUsageColor
import ch.zhaw.digitalfootprintexplorer.ui.theme.pieChartBackgroundColor
import ch.zhaw.digitalfootprintexplorer.ui.theme.pieChartDisplayColor
import kotlinx.datetime.LocalDate

/** One bar of the [WeekBarChart]. A null [values] means no data was recorded for that day. */
data class DayBar(
    val date: LocalDate,
    val label: String,
    val values: DayBarValues?
)

data class DayBarValues(
    val appUsageKg: Double,
    val displayKg: Double,
    val backgroundKg: Double
) {
    val totalKg: Double get() = appUsageKg + displayKg + backgroundKg
}

/**
 * Stacked bar chart for seven days. Bar heights are relative to the highest day of the week.
 * Only the [selectedDate] bar is drawn in colour, all others are greyed out.
 * Tapping a bar selects that day.
 */
@Composable
fun WeekBarChart(
    days: List<DayBar>,
    selectedDate: LocalDate,
    onSelect: (LocalDate) -> Unit,
    modifier: Modifier = Modifier
) {
    val maxDay = days.maxOf { it.values?.totalKg ?: 0.0 }
    val barAreaHeight = 140.dp

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        days.forEach { day ->
            val selected = day.date == selectedDate
            val total = day.values?.totalKg ?: 0.0

            Column(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(8.dp))
                    .background(
                        if (selected) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.4f)
                        else androidx.compose.ui.graphics.Color.Transparent
                    )
                    .clickable { onSelect(day.date) }
                    .padding(vertical = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Box(
                    modifier = Modifier
                        .height(barAreaHeight)
                        .padding(vertical = 4.dp),
                    contentAlignment = Alignment.BottomCenter
                ) {
                    if (day.values != null && maxDay > 0 && total > 0) {
                        Column(
                            modifier = Modifier
                                .width(20.dp)
                                .fillMaxHeight((total / maxDay).toFloat())
                                .clip(RoundedCornerShape(4.dp))
                        ) {
                            if (selected) {
                                BarSegment(day.values.appUsageKg, pieChartAppUsageColor)
                                BarSegment(day.values.displayKg, pieChartDisplayColor)
                                BarSegment(day.values.backgroundKg, pieChartBackgroundColor)
                            } else {
                                // Greyed out: only the selected day shows the colours.
                                Box(
                                    modifier = Modifier
                                        .fillMaxSize()
                                        .background(MaterialTheme.colorScheme.surfaceContainerHighest)
                                )
                            }
                        }
                    } else {
                        Box(
                            modifier = Modifier
                                .width(20.dp)
                                .height(2.dp)
                                .background(MaterialTheme.colorScheme.outlineVariant)
                        )
                    }
                }

                Text(
                    text = day.label,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
                    color = if (selected) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.ColumnScope.BarSegment(
    valueKg: Double,
    color: androidx.compose.ui.graphics.Color
) {
    if (valueKg <= 0.0) return
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .weight(valueKg.toFloat())
            .background(color)
    )
}
