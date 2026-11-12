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

package ch.zhaw.digitalfootprintexplorer.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
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
import androidx.glance.unit.ColorProvider
import ch.zhaw.digitalfootprintexplorer.ui.theme.surfaceContainerLowDark
import ch.zhaw.digitalfootprintexplorer.MainActivity
import ch.zhaw.digitalfootprintexplorer.R
import ch.zhaw.digitalfootprintexplorer.model.GardenState

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
            val stateName = prefs[KEY_STATE] ?: GardenState.FLOURISHING.name
            val state     = runCatching { GardenState.valueOf(stateName) }.getOrDefault(GardenState.FLOURISHING)
            GardenContent(state)
        }
    }

    @Composable
    private fun GardenContent(state: GardenState) {
        val imageRes = when (state) {
            GardenState.FLOURISHING -> R.drawable.garden_state_1_flourishing
            GardenState.GROWING     -> R.drawable.garden_state_2_growing
            GardenState.STABLE      -> R.drawable.garden_state_3_stable
            GardenState.WILTING     -> R.drawable.garden_state_4_wilting
            GardenState.WITHERED    -> R.drawable.garden_state_5_withered
        }

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(ColorProvider(surfaceContainerLowDark))
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
