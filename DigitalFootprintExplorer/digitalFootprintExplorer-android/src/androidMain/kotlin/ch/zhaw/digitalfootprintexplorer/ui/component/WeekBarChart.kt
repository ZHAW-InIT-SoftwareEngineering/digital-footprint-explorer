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

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.layout.layout
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import ch.zhaw.digitalfootprintexplorer.ui.theme.ChartColors
import kotlin.math.ceil
import kotlin.math.roundToInt
import kotlinx.datetime.LocalDate

private val BAR_WIDTH = 28.dp
private val MIN_BAR_HEIGHT = 4.dp
private val AXIS_WIDTH = 52.dp
private const val AXIS_STEP_GRAMS = 25.0

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
 * Stacked bar chart for seven days with a y-axis from 0 to the next round value above the
 * highest day (in grams). A dashed line marks [averageKg] if given.
 * Tapping a bar selects that day.
 */
@Composable
fun WeekBarChart(
    days: List<DayBar>,
    selectedDate: LocalDate,
    onSelect: (LocalDate) -> Unit,
    modifier: Modifier = Modifier,
    averageKg: Double? = null
) {
    val maxDayGrams = days.maxOf { it.values?.totalKg ?: 0.0 } * 1000.0
    val axisMaxGrams = ceilToStep(maxOf(maxDayGrams, (averageKg ?: 0.0) * 1000.0))
    val axisMaxKg = axisMaxGrams / 1000.0
    val barAreaHeight = 140.dp
    val rowPadding = 8.dp
    val lineColor = MaterialTheme.colorScheme.onSurfaceVariant
    val gridColor = MaterialTheme.colorScheme.outlineVariant
    val averageFraction = averageKg?.let { (it / axisMaxKg).toFloat().coerceIn(0f, 1f) }

    Row(modifier = modifier.fillMaxWidth()) {
        Box(modifier = Modifier.weight(1f)) {
            // Grid lines and average line, aligned with the bar area of the columns below.
            Canvas(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = rowPadding)
                    .height(barAreaHeight)
            ) {
                drawLine(gridColor, Offset(0f, 0f), Offset(size.width, 0f), strokeWidth = 1.dp.toPx())
                drawLine(gridColor, Offset(0f, size.height), Offset(size.width, size.height), strokeWidth = 1.dp.toPx())
                // Faint orientation line for every AXIS_STEP_GRAMS between 0 and the maximum.
                val steps = (axisMaxGrams / AXIS_STEP_GRAMS).roundToInt()
                for (i in 1 until steps) {
                    val y = size.height * (1f - i / steps.toFloat())
                    drawLine(
                        color = gridColor.copy(alpha = 0.5f),
                        start = Offset(0f, y),
                        end = Offset(size.width, y),
                        strokeWidth = 1.dp.toPx()
                    )
                }
                averageFraction?.let {
                    val y = size.height * (1f - it)
                    drawLine(
                        color = lineColor,
                        start = Offset(0f, y),
                        end = Offset(size.width, y),
                        strokeWidth = 2.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(10.dp.toPx(), 6.dp.toPx()))
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                days.forEach { day ->
                    val selected = day.date == selectedDate
                    val total = day.values?.totalKg ?: 0.0

                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(12.dp))
                            .background(
                                if (selected) MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.5f)
                                else Color.Transparent
                            )
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null
                            ) { onSelect(day.date) }
                            .padding(vertical = rowPadding),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Box(
                            modifier = Modifier.height(barAreaHeight),
                            contentAlignment = Alignment.BottomCenter
                        ) {
                            if (day.values != null && total > 0) {
                                Column(
                                    modifier = Modifier
                                        .width(BAR_WIDTH)
                                        // At least 4 dp so a small day is still visible next to a big one.
                                        .height(
                                            maxOf(
                                                barAreaHeight * (total / axisMaxKg).toFloat().coerceIn(0f, 1f),
                                                MIN_BAR_HEIGHT
                                            )
                                        )
                                        .clip(RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp))
                                ) {
                                    BarSegment(day.values.appUsageKg, ChartColors.appUsage)
                                    BarSegment(day.values.displayKg, ChartColors.display)
                                    BarSegment(day.values.backgroundKg, ChartColors.background)
                                }
                            } else {
                                Box(
                                    modifier = Modifier
                                        .width(BAR_WIDTH)
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

        // Y-axis labels: 0 at the bottom, rounded maximum at the top, average marker in between.
        Box(
            modifier = Modifier
                .width(AXIS_WIDTH)
                .padding(top = rowPadding)
                .height(barAreaHeight)
        ) {
            val labelStyle = MaterialTheme.typography.labelSmall
            val labelColor = MaterialTheme.colorScheme.onSurfaceVariant
            val minLabelGap = 14.dp
            Text(
                text = formatAxisGrams(axisMaxGrams),
                style = labelStyle,
                color = labelColor,
                textAlign = TextAlign.End,
                modifier = Modifier.fillMaxWidth().centeredOnY(0.dp).padding(start = 4.dp)
            )
            Text(
                text = formatAxisGrams(0.0),
                style = labelStyle,
                color = labelColor,
                textAlign = TextAlign.End,
                modifier = Modifier.fillMaxWidth().centeredOnY(barAreaHeight).padding(start = 4.dp)
            )
            averageFraction?.let {
                val y = barAreaHeight * (1f - it)
                // Skip the marker if it would collide with the 0 or maximum label.
                if (y > minLabelGap && y < barAreaHeight - minLabelGap) {
                    Text(
                        text = "\u2300",
                        style = labelStyle,
                        color = lineColor,
                        textAlign = TextAlign.End,
                        modifier = Modifier.fillMaxWidth().centeredOnY(y).padding(start = 4.dp)
                    )
                }
            }
        }
    }
}

/** Places the element so its vertical centre sits on [y] (measured from the parent's top). */
private fun Modifier.centeredOnY(y: Dp): Modifier = layout { measurable, constraints ->
    val placeable = measurable.measure(constraints)
    layout(placeable.width, placeable.height) {
        placeable.place(0, y.roundToPx() - placeable.height / 2)
    }
}

/** Rounds [value] up to the next multiple of 25 (at least 25). */
private fun ceilToStep(value: Double): Double =
    maxOf(1.0, ceil(value / AXIS_STEP_GRAMS)) * AXIS_STEP_GRAMS

private fun formatAxisGrams(grams: Double): String =
    if (grams >= 10 || grams == 0.0) "%.0f g".format(grams) else "%.1f g".format(grams)

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
