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
import androidx.glance.appwidget.GlanceAppWidgetManager
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
        val state = readState(context)
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

    companion object {
        private const val PREFS_NAME  = "garden_widget_prefs"
        private const val KEY_STATE   = "garden_state"

        private fun readState(context: Context): GardenState {
            val prefs     = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val stateName = prefs.getString(KEY_STATE, GardenState.STABLE.name) ?: GardenState.STABLE.name
            return runCatching { GardenState.valueOf(stateName) }.getOrDefault(GardenState.STABLE)
        }

        /** Called by [DailyFootprintWorker] after each calculation to persist and refresh the widget. */
        suspend fun updateState(context: Context, state: GardenState) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_STATE, state.name)
                .apply()

            GlanceAppWidgetManager(context)
                .getGlanceIds(GardenWidget::class.java)
                .forEach { id -> GardenWidget().update(context, id) }
        }
    }
}
