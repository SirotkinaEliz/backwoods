package com.glush.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED ||
            intent?.action == "android.intent.action.QUICKBOOT_POWERON"
        ) {
            // Auto-start VPN on device boot
            val serviceIntent = Intent(context, GlushVpnService::class.java)
            context.startForegroundService(serviceIntent)
        }
    }
}
