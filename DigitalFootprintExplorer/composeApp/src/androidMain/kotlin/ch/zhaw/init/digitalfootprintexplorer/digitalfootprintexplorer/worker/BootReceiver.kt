package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service.TrackingService

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
