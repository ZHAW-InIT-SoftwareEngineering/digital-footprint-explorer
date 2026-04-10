package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer

import android.os.Build
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.safeContentPadding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.appwidget.GlanceAppWidgetManager
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.theme.DFETheme
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.GardenWidget
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.GardenWidgetReceiver
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.WidgetOnboardingSheet
import digitalfootprintexplorer.composeapp.generated.resources.Res
import digitalfootprintexplorer.composeapp.generated.resources.compose_multiplatform
import kotlinx.coroutines.launch
import org.jetbrains.compose.resources.painterResource

@Composable
@Preview
fun App() {
    DFETheme {
        val context = LocalContext.current
        val scope = rememberCoroutineScope()
        var showOnboarding by remember { mutableStateOf(false) }
        var showContent by remember { mutableStateOf(false) }

        LaunchedEffect(Unit) {
            val installedIds = GlanceAppWidgetManager(context).getGlanceIds(GardenWidget::class.java)
            showOnboarding = installedIds.isEmpty()
        }

        if (showOnboarding) {
            WidgetOnboardingSheet(
                onDismiss = { showOnboarding = false },
                onPin = {
                    scope.launch {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            GlanceAppWidgetManager(context).requestPinGlanceAppWidget(
                                receiver = GardenWidgetReceiver::class.java,
                                preview = GardenWidget(),
                                previewState = DpSize(245.dp, 115.dp)
                            )
                        }
                        showOnboarding = false
                    }
                }
            )
        }

        Column(
            modifier = Modifier
                .background(MaterialTheme.colorScheme.background)
                .safeContentPadding()
                .fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Button(onClick = { showContent = !showContent }) {
                Text("Click me!")
            }
            AnimatedVisibility(showContent) {
                val greeting = remember { Greeting().greet() }
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Image(painterResource(Res.drawable.compose_multiplatform), null)
                    Text("Compose: $greeting")
                }
            }
        }
    }
}
