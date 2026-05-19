package ch.zhaw.digitalfootprintexplorer.servicelayerplatform.service

import android.app.ForegroundServiceStartNotAllowedException
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import ch.zhaw.digitalfootprintexplorer.DFEApplication
import ch.zhaw.digitalfootprintexplorer.R

/**
 * Foreground Service that hosts [DisplayBrightnessObserver] and [BackgroundProcessTracker]
 * so that brightness intervals and GPS/Bluetooth durations are recorded continuously —
 * even when the app is not in the foreground.
 *
 * Additionally listens for [Intent.ACTION_SCREEN_OFF] / [Intent.ACTION_SCREEN_ON] and
 * forwards these events to [DisplayBrightnessObserver] so that display-off periods are
 * correctly attributed a brightness of 0.0 in the emissions formula.
 *
 * The service is started from [DFEApplication.onCreate] and restarted after device reboots
 * by [BootReceiver]. [START_STICKY] ensures Android restarts it automatically if killed.
 */
class TrackingService : Service() {

    private lateinit var brightnessObserver: DisplayBrightnessObserver
    private lateinit var backgroundTracker: BackgroundProcessTracker

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_OFF -> brightnessObserver.onScreenOff()
                Intent.ACTION_SCREEN_ON  -> brightnessObserver.onScreenOn()
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())

        val app = applicationContext as DFEApplication
        brightnessObserver = app.displayBrightnessObserver
        backgroundTracker  = app.backgroundProcessTracker

        registerReceiver(
            screenReceiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_SCREEN_ON)
            }
        )

        brightnessObserver.register()
        backgroundTracker.register()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        super.onDestroy()
        runCatching { unregisterReceiver(screenReceiver) }
        brightnessObserver.unregister()
        backgroundTracker.unregister()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Footprint Tracking",
            NotificationManager.IMPORTANCE_MIN
        ).apply { setShowBadge(false) }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.notification_foreground_service_title))
            .setContentText(getString(R.string.notification_foreground_service_description))
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setSilent(true)
            .setOngoing(true)
            .build()

    companion object {
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID      = "dfe_tracking"
        private const val TAG             = "TrackingService"

        fun start(context: Context) {
            try {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, TrackingService::class.java)
                )
            } catch (e: Exception) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    e is ForegroundServiceStartNotAllowedException) {
                    Log.w(TAG, "Cannot start foreground service from background — will retry on next user launch")
                } else {
                    throw e
                }
            }
        }
    }
}