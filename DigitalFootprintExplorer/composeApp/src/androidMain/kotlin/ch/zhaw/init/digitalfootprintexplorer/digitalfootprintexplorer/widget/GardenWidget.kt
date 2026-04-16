package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.stringPreferencesKey
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
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.ContentScale
import androidx.glance.layout.fillMaxSize
import androidx.glance.state.GlanceStateDefinition
import androidx.glance.state.PreferencesGlanceStateDefinition
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.MainActivity
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.R
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.GardenState

class GardenWidget : GlanceAppWidget() {

    /**
     * Use Glance's built-in Preferences DataStore as the state backing.
     *
     * The previous approach (SharedPreferences + manual update()) had a subtle flaw:
     * [provideGlance] read the state ONCE before [provideContent] and passed it as a
     * fixed value, so Glance had no way to detect a change and sometimes skipped the
     * redraw. With [PreferencesGlanceStateDefinition], [currentState] inside
     * [provideContent] is reactive — every [updateAppWidgetState] call reliably
     * triggers a recomposition.
     */
    override val stateDefinition: GlanceStateDefinition<*> = PreferencesGlanceStateDefinition

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            // currentState() reads from Glance's DataStore reactively.
            // It is re-evaluated on every recomposition triggered by updateAppWidgetState.
            val prefs     = currentState<Preferences>()
            val stateName = prefs[KEY_STATE] ?: GardenState.STABLE.name
            val state     = runCatching { GardenState.valueOf(stateName) }.getOrDefault(GardenState.STABLE)
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
        private val KEY_STATE = stringPreferencesKey("garden_state")

        /**
         * Writes [state] into Glance's DataStore and triggers a widget refresh.
         *
         * [updateAppWidgetState] is the idiomatic Glance API: it atomically updates
         * the DataStore entry and guarantees that the next [GlanceAppWidget.update]
         * call sees the new value via [currentState].
         */
        suspend fun updateState(context: Context, state: GardenState) {
            GlanceAppWidgetManager(context)
                .getGlanceIds(GardenWidget::class.java)
                .forEach { id ->
                    updateAppWidgetState(context, PreferencesGlanceStateDefinition, id) { prefs ->
                        prefs.toMutablePreferences().also { it[KEY_STATE] = state.name }
                    }
                    GardenWidget().update(context, id)
                }
        }
    }
}
