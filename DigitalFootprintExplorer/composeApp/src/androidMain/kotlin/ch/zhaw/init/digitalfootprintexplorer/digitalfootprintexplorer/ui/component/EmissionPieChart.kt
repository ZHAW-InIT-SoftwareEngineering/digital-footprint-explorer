package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.component

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.theme.pieChartAppUsageColor
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.theme.pieChartBackgroundColor
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.theme.pieChartDisplayColor
import com.patrykandpatrick.vico.compose.common.Fill
import com.patrykandpatrick.vico.compose.common.component.TextComponent
import com.patrykandpatrick.vico.compose.pie.PieChart
import com.patrykandpatrick.vico.compose.pie.PieChartHost
import com.patrykandpatrick.vico.compose.pie.data.PieChartModelProducer
import com.patrykandpatrick.vico.compose.pie.data.PieValueFormatter
import com.patrykandpatrick.vico.compose.pie.data.pieSeries
import com.patrykandpatrick.vico.compose.pie.rememberPieChart
import kotlin.math.roundToInt

@Composable
fun EmissionPieChart(
    appUsage: Double,
    display: Double,
    background: Double,
    modifier: Modifier = Modifier
) {
    val total = (appUsage + display + background).toFloat()
    val modelProducer = remember { PieChartModelProducer() }

    LaunchedEffect(appUsage, display, background) {
        modelProducer.runTransaction {
            pieSeries {
                series(
                    appUsage.toFloat(),
                    display.toFloat(),
                    background.toFloat()
                )
            }
        }
    }

    val labelComponent = remember {
        TextComponent(
            textStyle = TextStyle(color = Color.White)
        )
    }

    val pieChart = rememberPieChart(
        sliceProvider = PieChart.SliceProvider.series(
            listOf(
                PieChart.Slice(
                    fill = Fill(pieChartAppUsageColor),
                    label = PieChart.SliceLabel.Inside(labelComponent)
                ),
                PieChart.Slice(
                    fill = Fill(pieChartDisplayColor),
                    label = PieChart.SliceLabel.Inside(labelComponent)
                ),
                PieChart.Slice(
                    fill = Fill(pieChartBackgroundColor),
                    label = PieChart.SliceLabel.Inside(labelComponent)
                )
            )
        ),
        valueFormatter = PieValueFormatter { _, value, _ ->
            if (total <= 0f) {
                ""
            } else {
                "${((value / total) * 100f).roundToInt()}%"
            }
        }
    )

    PieChartHost(
        chart = pieChart,
        modelProducer = modelProducer,
        modifier = modifier
    )
}