package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget

import android.os.Build
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.appwidget.GlanceAppWidgetManager
import kotlinx.coroutines.launch


@Composable
fun PinGardenWidgetButton() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()

    Button(onClick = {
        coroutineScope.launch {
            GlanceAppWidgetManager(context).requestPinGlanceAppWidget(
                receiver = GardenWidgetReceiver::class.java,
                preview = GardenWidget(),
                previewState = DpSize(245.dp, 115.dp)
            )
        }
    }) {
        Text("Widget auf Homescreen hinzufügen.")
    }
}
