package com.glush.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import androidx.multidex.MultiDexApplication

class GlushApp : MultiDexApplication() {

    companion object {
        lateinit var instance: GlushApp
            private set

        const val NOTIF_CHANNEL_VPN = "glush_vpn"
        const val NOTIF_CHANNEL_VPN_NAME = "GLUSH VPN"
    }

    var vpnConnected = false
    var onStatusChanged: ((Boolean) -> Unit)? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannels()
    }

    fun setVpnStatus(connected: Boolean) {
        vpnConnected = connected
        onStatusChanged?.invoke(connected)
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIF_CHANNEL_VPN,
                NOTIF_CHANNEL_VPN_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "GLUSH WireGuard VPN status"
            }
            getSystemService(NotificationManager::class.java)
                ?.createNotificationChannel(channel)
        }
    }
}
