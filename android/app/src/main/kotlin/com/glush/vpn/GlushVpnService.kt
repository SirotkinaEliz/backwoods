package com.glush.vpn

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.cancel

class GlushVpnService : VpnService() {

    private val TAG = "GlushVpnService"
    private val NOTIF_ID = 1001

    private val scope = CoroutineScope(Dispatchers.IO + Job())
    private var backend: GoBackend? = null
    private var currentTunnel: Tunnel? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopTunnel()
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIF_ID, buildNotification(connecting = true))
        scope.launch { startTunnel() }
        return START_STICKY
    }

    private suspend fun startTunnel() {
        try {
            // Read tunnel.conf embedded at build time
            val confText = resources.openRawResource(R.raw.tunnel)
                .bufferedReader().readText()

            val config = Config.parse(confText.reader())

            val be = GoBackend(this@GlushVpnService)

            val tun = object : Tunnel {
                override fun getName() = "glush"
                override fun onStateChange(newState: Tunnel.State) {
                    val connected = newState == Tunnel.State.UP
                    GlushApp.instance.setVpnStatus(connected)
                    updateNotification(connected)
                    Log.i(TAG, "Tunnel state: $newState")
                }
            }

            be.setState(tun, Tunnel.State.UP, config)
            backend = be
            currentTunnel = tun

        } catch (e: Exception) {
            Log.e(TAG, "Failed to start WireGuard tunnel", e)
            GlushApp.instance.setVpnStatus(false)
            updateNotification(false)
        }
    }

    private fun stopTunnel() {
        scope.launch {
            try {
                currentTunnel?.let {
                    backend?.setState(it, Tunnel.State.DOWN, null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping tunnel", e)
            }
        }
        GlushApp.instance.setVpnStatus(false)
    }

    private fun buildNotification(connecting: Boolean = false): Notification {
        val stopIntent = Intent(this, GlushVpnService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val openIntent = Intent(this, MainActivity::class.java)
        val openPending = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, GlushApp.NOTIF_CHANNEL_VPN)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("GLUSH VPN")
            .setContentText(if (connecting) "Подключение..." else "VPN активен")
            .setContentIntent(openPending)
            .addAction(android.R.drawable.ic_delete, "Отключить", stopPending)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    private fun updateNotification(connected: Boolean) {
        val notif = buildNotification(!connected)
        getSystemService(NotificationManager::class.java)
            ?.notify(NOTIF_ID, notif)
    }

    override fun onDestroy() {
        stopTunnel()
        scope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_STOP = "com.glush.vpn.STOP_VPN"
    }
}
