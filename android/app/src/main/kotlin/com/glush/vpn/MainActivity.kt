package com.glush.vpn

import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import com.glush.vpn.databinding.ActivityMainBinding

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val VPN_REQUEST_CODE = 100
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        // Register status listener
        GlushApp.instance.onStatusChanged = { connected ->
            runOnUiThread { updateUI(connected) }
        }

        binding.btnToggleVpn.setOnClickListener {
            if (GlushApp.instance.vpnConnected) {
                stopVpn()
            } else {
                requestVpnPermission()
            }
        }

        updateUI(GlushApp.instance.vpnConnected)
    }

    private fun requestVpnPermission() {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            startVpn()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE && resultCode == RESULT_OK) {
            startVpn()
        }
    }

    private fun startVpn() {
        updateUI(connecting = true)
        val intent = Intent(this, GlushVpnService::class.java)
        startForegroundService(intent)
    }

    private fun stopVpn() {
        val intent = Intent(this, GlushVpnService::class.java).apply {
            action = GlushVpnService.ACTION_STOP
        }
        startService(intent)
    }

    private fun updateUI(connected: Boolean = false, connecting: Boolean = false) {
        when {
            connecting -> {
                binding.statusIndicator.text = "⬤"
                binding.statusIndicator.setTextColor(0xFFFFAA00.toInt())
                binding.statusText.text = "Подключение..."
                binding.btnToggleVpn.isEnabled = false
                binding.btnToggleVpn.text = "Подключение..."
            }
            connected -> {
                binding.statusIndicator.text = "⬤"
                binding.statusIndicator.setTextColor(0xFF4CAF50.toInt())
                binding.statusText.text = "VPN подключён"
                binding.serverInfo.text = "Сервер: 91.84.96.45"
                binding.serverInfo.visibility = View.VISIBLE
                binding.btnToggleVpn.isEnabled = true
                binding.btnToggleVpn.text = "Отключить VPN"
                binding.btnToggleVpn.setBackgroundColor(0xFF7B5EA7.toInt())
            }
            else -> {
                binding.statusIndicator.text = "⬤"
                binding.statusIndicator.setTextColor(0xFF888888.toInt())
                binding.statusText.text = "VPN отключён"
                binding.serverInfo.visibility = View.GONE
                binding.btnToggleVpn.isEnabled = true
                binding.btnToggleVpn.text = "Подключить VPN"
                binding.btnToggleVpn.setBackgroundColor(0xFF2CA5E0.toInt())
            }
        }
    }

    override fun onDestroy() {
        GlushApp.instance.onStatusChanged = null
        super.onDestroy()
    }
}
