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

package ch.zhaw.digitalfootprintexplorer.ui.screen

import android.text.format.DateFormat
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringArrayResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import ch.zhaw.digitalfootprintexplorer.DFEApplication
import ch.zhaw.digitalfootprintexplorer.R
import ch.zhaw.digitalfootprintexplorer.model.AppCategory
import ch.zhaw.digitalfootprintexplorer.model.CategoryHistory
import ch.zhaw.digitalfootprintexplorer.model.DayHistory
import ch.zhaw.digitalfootprintexplorer.model.HistorySummary
import ch.zhaw.digitalfootprintexplorer.model.dailyAverage
import ch.zhaw.digitalfootprintexplorer.model.startOfWeek
import ch.zhaw.digitalfootprintexplorer.model.summarize
import ch.zhaw.digitalfootprintexplorer.ui.component.DayBar
import ch.zhaw.digitalfootprintexplorer.ui.component.DayBarValues
import ch.zhaw.digitalfootprintexplorer.ui.component.WeekBarChart
import ch.zhaw.digitalfootprintexplorer.ui.component.formatEmission
import ch.zhaw.digitalfootprintexplorer.ui.theme.ChartColors
import kotlinx.coroutines.launch
import kotlinx.datetime.Clock
import kotlinx.datetime.DatePeriod
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.daysUntil
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.minus
import kotlinx.datetime.plus
import kotlinx.datetime.todayIn
import java.util.Locale

/**
 * Weekly report (Monday–Sunday). Swiping the bar chart switches the week, tapping a bar
 * restricts the analysis to that day.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun StatisticsScreen(
    innerPadding: PaddingValues
) {
    val context = LocalContext.current
    val app = context.applicationContext as DFEApplication

    var storedDays by remember { mutableStateOf<Map<LocalDate, DayHistory>?>(null) }
    LaunchedEffect(Unit) { storedDays = app.gardenStateCalculator.getAllDays() }

    // The current day is not stored yet, it is calculated from midnight until the app was opened.
    val todaySnapshot by app.todayFootprint.snapshot.collectAsState()
    val history = storedDays?.let { stored ->
        todaySnapshot?.let { stored + (it.day.date to it.day) } ?: stored
    }

    Column(
        modifier = Modifier
            .background(MaterialTheme.colorScheme.background)
            .padding(innerPadding)
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        val days = history ?: return@Column

        if (days.isEmpty()) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer
                ),
                shape = MaterialTheme.shapes.medium
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(32.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = stringResource(R.string.no_statistics),
                        textAlign = TextAlign.Center,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            return@Column
        }

        val today = remember { Clock.System.todayIn(TimeZone.currentSystemDefault()) }
        val firstMonday = remember(days) { days.keys.min().startOfWeek() }
        val lastMonday = remember(days) { maxOf(today, days.keys.max()).startOfWeek() }
        val weekCount = firstMonday.daysUntil(lastMonday) / 7 + 1

        val pagerState = rememberPagerState(initialPage = weekCount - 1) { weekCount }
        val scope = rememberCoroutineScope()
        val monday = firstMonday.plus(DatePeriod(days = pagerState.currentPage * 7))
        val weekDates = (0..6).map { monday.plus(DatePeriod(days = it)) }

        // A day is always selected: the latest recorded day of the week until the user taps another.
        // Leaving the week resets the choice.
        var tappedDate by remember(monday) { mutableStateOf<LocalDate?>(null) }
        val selectedDate = tappedDate
            ?: weekDates.lastOrNull { it in days } ?: weekDates.last()

        val weekdayLabels = stringArrayResource(R.array.weekday_short_names)

        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceContainer
            ),
            shape = MaterialTheme.shapes.medium
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(20.dp)
            ) {
                Text(
                    text = stringResource(R.string.history_title),
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onBackground
                )

                Spacer(Modifier.height(8.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(
                        enabled = pagerState.currentPage > 0,
                        onClick = { scope.launch { pagerState.animateScrollToPage(pagerState.currentPage - 1) } }
                    ) {
                        Icon(
                            Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                            contentDescription = stringResource(R.string.history_previous_week)
                        )
                    }
                    Text(
                        text = weekRangeLabel(weekDates.first(), weekDates.last()),
                        modifier = Modifier.weight(1f),
                        textAlign = TextAlign.Center,
                        style = MaterialTheme.typography.titleSmall
                    )
                    IconButton(
                        enabled = pagerState.currentPage < weekCount - 1,
                        onClick = { scope.launch { pagerState.animateScrollToPage(pagerState.currentPage + 1) } }
                    ) {
                        Icon(
                            Icons.AutoMirrored.Filled.KeyboardArrowRight,
                            contentDescription = stringResource(R.string.history_next_week)
                        )
                    }
                }

                // The unfinished current day would pull the average down, so it only appears as a bar.
                val weekDays = weekDates.filter { it != today }.mapNotNull { days[it] }
                val average = weekDays.dailyAverage()
                val previousMonday = monday.minus(DatePeriod(days = 7))
                val previousAverage = (0..6)
                    .mapNotNull { days[previousMonday.plus(DatePeriod(days = it))] }
                    .dailyAverage()

                DailyAverageHeader(
                    averageKg = average?.totalKg,
                    previousAverageKg = previousAverage?.totalKg
                )

                Spacer(Modifier.height(12.dp))

                HorizontalPager(
                    state = pagerState,
                    modifier = Modifier.fillMaxWidth()
                ) { page ->
                    val pageMonday = firstMonday.plus(DatePeriod(days = page * 7))
                    val bars = (0..6).map { offset ->
                        val date = pageMonday.plus(DatePeriod(days = offset))
                        DayBar(
                            date = date,
                            label = weekdayLabels[date.dayOfWeek.isoDayNumber - 1],
                            values = days[date]?.let {
                                DayBarValues(it.appUsageKg, it.displayKg, it.backgroundKg)
                            }
                        )
                    }
                    // The unfinished current day is excluded, same as in the header average.
                    val pageAverage = (0..6)
                        .map { pageMonday.plus(DatePeriod(days = it)) }
                        .filter { it != today }
                        .mapNotNull { days[it] }
                        .dailyAverage()
                    WeekBarChart(
                        days = bars,
                        selectedDate = selectedDate,
                        onSelect = { tappedDate = it },
                        averageKg = pageAverage?.totalKg
                    )
                }

                Spacer(Modifier.height(8.dp))
                HorizontalDivider()
                Spacer(Modifier.height(12.dp))

                val selectedLabel = dayLabel(selectedDate)
                EmissionBreakdown(
                    title = if (selectedDate == today) {
                        stringResource(R.string.history_today_so_far, selectedLabel)
                    } else selectedLabel,
                    summary = days[selectedDate]?.let { listOf(it).dailyAverage() }
                )

                Spacer(Modifier.height(16.dp))

                HistoryDetails(
                    summary = listOfNotNull(days[selectedDate]).summarize(),
                    hasData = selectedDate in days
                )
            }
        }

        todaySnapshot?.let { snapshot ->
            Spacer(Modifier.height(8.dp))
            Text(
                text = stringResource(R.string.history_updated, formatUpdated(snapshot.calculatedAtMs)),
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

/**
 * Daily average of the shown week plus a badge comparing it to the previous week's daily average.
 */
@Composable
private fun DailyAverageHeader(
    averageKg: Double?,
    previousAverageKg: Double?
) {
    val change = if (averageKg != null && previousAverageKg != null && previousAverageKg > 0)
        (averageKg - previousAverageKg) / previousAverageKg else null

    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = stringResource(R.string.history_daily_average),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (averageKg != null) {
            Text(
                text = "%.2f g CO₂e".format(averageKg * 1000),
                style = MaterialTheme.typography.headlineMedium,
                color = MaterialTheme.colorScheme.onBackground
            )
        }
        if (change != null) {
            // Less than last week is good (primary), more is bad (error); ±1 % counts as equal.
            val color = when {
                change <= -0.01 -> MaterialTheme.colorScheme.primary
                change >= 0.01 -> MaterialTheme.colorScheme.error
                else -> MaterialTheme.colorScheme.onSurfaceVariant
            }
            val arrow = when {
                change <= -0.01 -> "↘"
                change >= 0.01 -> "↗"
                else -> "→"
            }
            Spacer(Modifier.height(4.dp))
            Text(
                text = "$arrow " + stringResource(
                    R.string.history_vs_last_week,
                    "%+.0f%%".format(change * 100)
                ),
                modifier = Modifier
                    .clip(MaterialTheme.shapes.small)
                    .background(color.copy(alpha = 0.18f))
                    .padding(horizontal = 10.dp, vertical = 4.dp),
                style = MaterialTheme.typography.labelLarge,
                color = color
            )
        } else {
            Spacer(Modifier.height(4.dp))
            Text(
                text = stringResource(R.string.history_no_comparison),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

/**
 * Three columns (app usage, display, background) with their absolute value in g CO₂e, like the
 * category summary of iOS Screen Time. [summary] null shows dashes.
 */
@Composable
private fun EmissionBreakdown(
    title: String,
    summary: HistorySummary?
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        // The unit is shown once here; the three values below only carry a plain "g".
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onBackground,
                modifier = Modifier.weight(1f)
            )
            summary?.let {
                Text(
                    text = "%.2f g CO₂e".format(it.totalKg * 1000),
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onBackground
                )
            }
        }
        Spacer(Modifier.height(12.dp))
        Row(modifier = Modifier.fillMaxWidth()) {
            BreakdownValue(
                label = stringResource(R.string.app_usage),
                valueKg = summary?.appUsageKg,
                totalKg = summary?.totalKg,
                color = ChartColors.appUsage,
                modifier = Modifier.weight(1f)
            )
            BreakdownValue(
                label = stringResource(R.string.display),
                valueKg = summary?.displayKg,
                totalKg = summary?.totalKg,
                color = ChartColors.display,
                modifier = Modifier.weight(1f)
            )
            BreakdownValue(
                label = stringResource(R.string.background),
                valueKg = summary?.backgroundKg,
                totalKg = summary?.totalKg,
                color = ChartColors.background,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun BreakdownValue(
    label: String,
    valueKg: Double?,
    totalKg: Double?,
    color: Color,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = color
        )
        val pct = if (valueKg != null && totalKg != null && totalKg > 0)
            "%.0f%%".format(valueKg / totalKg * 100) else "–"
        Text(
            text = pct,
            style = MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.onBackground
        )
//        Row(verticalAlignment = Alignment.Bottom) {
//            Text(
//                text = if (valueKg != null) "%.2f".format(valueKg * 1000) else "–",
//                style = MaterialTheme.typography.labelSmall,
//                color = MaterialTheme.colorScheme.onSurfaceVariant
//            )
//            if (valueKg != null) {
//                Text(
//                    text = " g",
//                    style = MaterialTheme.typography.labelSmall,
//                    color = MaterialTheme.colorScheme.onSurfaceVariant,
//                )
//            }
//        }
    }
}

/** Category list of the selected day, followed by its total. */
@Composable
private fun HistoryDetails(
    summary: HistorySummary,
    hasData: Boolean
) {
    val total = summary.totalKg

    Column(modifier = Modifier.fillMaxWidth()) {
        if (!hasData || total <= 0) {
            Text(
                text = stringResource(R.string.history_no_data),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 16.dp),
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            return@Column
        }

        HorizontalDivider(modifier = Modifier.padding(bottom = 12.dp))

        if (summary.categories.isNotEmpty()) {
            Text(
                text = stringResource(R.string.history_categories),
                style = MaterialTheme.typography.titleSmall
            )
            Spacer(Modifier.height(4.dp))

            // Category shares are relative to the app usage they make up.
            val categoriesTotal = summary.categories.sumOf { it.totalKg }
            summary.categories.forEach { category ->
                CategoryRow(category, categoriesTotal)
            }

        }
    }
}

@Composable
private fun CategoryRow(
    category: CategoryHistory,
    categoriesTotal: Double
) {
    var expanded by remember { mutableStateOf(false) }
    val share = if (categoriesTotal > 0) category.totalKg / categoriesTotal else 0.0
    val canExpand = category.apps.isNotEmpty()

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(
                enabled = canExpand,
                interactionSource = remember { MutableInteractionSource() },
                indication = null
            ) { expanded = !expanded }
            .padding(vertical = 6.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = stringResource(category.category.labelRes()),
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f)
            )
            Text(
                text = formatEmission(share, null),
                style = MaterialTheme.typography.bodyMedium
            )
            if (canExpand) {
                Icon(
                    if (expanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Spacer(Modifier.height(4.dp))
        LinearProgressIndicator(
            progress = { share.toFloat() },
            modifier = Modifier.fillMaxWidth(),
            color = MaterialTheme.colorScheme.primary,
            trackColor = MaterialTheme.colorScheme.surfaceContainerHigh
        )

        if (expanded) {
            Column(modifier = Modifier.padding(start = 12.dp, top = 8.dp)) {
                category.apps.forEach { appEntry ->
                    val appShare = if (category.totalKg > 0) appEntry.totalKg / category.totalKg else 0.0
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 3.dp)
                    ) {
                        Text(
                            text = appEntry.appName,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.weight(1f)
                        )
                        Text(
                            text = formatEmission(appShare, null),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }
}

private fun AppCategory.labelRes(): Int = when (this) {
    AppCategory.VIDEO_STREAMING -> R.string.category_video_streaming
    AppCategory.AUDIO_STREAMING -> R.string.category_audio_streaming
    AppCategory.SOCIAL_MEDIA -> R.string.category_social_media
    AppCategory.MESSAGING -> R.string.category_messaging
    AppCategory.ARTIFICIAL_INTELLIGENCE -> R.string.category_artificial_intelligence
    AppCategory.E_MAIL -> R.string.category_e_mail
    AppCategory.VIDEO_CALL -> R.string.category_video_call
    AppCategory.GAMING -> R.string.category_gaming
    AppCategory.NAVIGATION -> R.string.category_navigation
    AppCategory.MISCELLANEOUS -> R.string.category_miscellaneous
}

private fun weekRangeLabel(from: LocalDate, to: LocalDate): String =
    "${formatDate(from, "dMMM")} – ${formatDate(to, "dMMM")}"

private fun formatUpdated(epochMs: Long): String =
    java.text.SimpleDateFormat("dd.MM.yy HH:mm", Locale.getDefault()).format(java.util.Date(epochMs))

private fun dayLabel(date: LocalDate): String = formatDate(date, "EEEEdMMMM")

/** Formats [date] with the best pattern of the current locale for the given [skeleton]. */
private fun formatDate(date: LocalDate, skeleton: String): String {
    val locale = Locale.getDefault()
    val format = java.text.SimpleDateFormat(DateFormat.getBestDateTimePattern(locale, skeleton), locale)
    format.timeZone = java.util.TimeZone.getTimeZone("UTC")
    return format.format(java.util.Date(date.atStartOfDayIn(TimeZone.UTC).toEpochMilliseconds()))
}
