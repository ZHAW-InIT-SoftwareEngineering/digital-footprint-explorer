package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.ContentScale
import androidx.glance.layout.fillMaxSize
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.MainActivity
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.R
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.GardenState

class GardenWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val state = GardenState.FLOURISHING /* TODO: Status updaten wenn neue Berechnungen gemacht wurden. */

        provideContent {
            GardenContent(state)
        }
    }

    @Composable
    private fun GardenContent(state: GardenState) {
        val imageRes = when (state) {
            GardenState.FLOURISHING -> R.drawable.garden_state_1_flourshining
            GardenState.GROWING     -> R.drawable.garden_state_2_growing
            GardenState.STABLE      -> R.drawable.garden_state_3_stable
            GardenState.WILTING     -> R.drawable.garden_state_4_wilting
            GardenState.WITHERED    -> R.drawable.garden_state_5_withered
        }

        GlanceTheme {
            Box(
                modifier = GlanceModifier
                    .fillMaxSize()
                    .background(GlanceTheme.colors.background)
                    .clickable(actionStartActivity<MainActivity>()),
                contentAlignment = Alignment.Center
            ) {
                Image(
                    provider = ImageProvider(imageRes),
                    contentDescription = state.name,
                    modifier = GlanceModifier.fillMaxSize(),
                    contentScale = ContentScale.Fit
                )
            }
        }
    }
}
