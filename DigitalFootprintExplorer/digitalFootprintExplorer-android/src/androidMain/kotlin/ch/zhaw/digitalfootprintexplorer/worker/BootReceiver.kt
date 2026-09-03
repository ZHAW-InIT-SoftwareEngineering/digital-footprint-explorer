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

package ch.zhaw.digitalfootprintexplorer.worker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import ch.zhaw.digitalfootprintexplorer.servicelayerplatform.service.TrackingService

/**
 * Restarts [TrackingService] and reschedules [DailyFootprintWorker] after a device reboot.
 *
 * Without this receiver the foreground service — and therefore the brightness/GPS/Bluetooth
 * tracking — would not resume until the user manually opens the app again.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            TrackingService.start(context)
            DailyFootprintWorker.scheduleNext(context)
        }
    }
}
