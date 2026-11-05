package com.s4daharu.virthelm

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

// The default network is an OS hint, not proof that Proxmox is reachable.
class MainActivity : FlutterActivity() {
    private var networkEvents: NetworkEvents? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val observer = NetworkEvents(manager)
        networkEvents = observer
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.s4daharu.virthelm/device_network",
        ).setStreamHandler(observer)
    }

    override fun onDestroy() {
        networkEvents?.onCancel(null)
        networkEvents = null
        super.onDestroy()
    }

    private class NetworkEvents(
        private val manager: ConnectivityManager,
    ) : EventChannel.StreamHandler {
        private val main = Handler(Looper.getMainLooper())
        private var sink: EventChannel.EventSink? = null
        private var callback: ConnectivityManager.NetworkCallback? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            onCancel(null)
            sink = events
            val next = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) { emit() }
                override fun onLost(network: Network) { emit() }
            }
            try {
                manager.registerDefaultNetworkCallback(next)
                callback = next
                emit()
            } catch (_: RuntimeException) {
                // Permission/system failures must be UNKNOWN, not "offline".
                main.post { sink?.success(null) }
            }
        }

        private fun emit() {
            main.post {
                try {
                    sink?.success(manager.activeNetwork != null)
                } catch (_: RuntimeException) {
                    sink?.success(null)
                }
            }
        }

        override fun onCancel(arguments: Any?) {
            val previous = callback
            callback = null
            sink = null
            if (previous != null) {
                try {
                    manager.unregisterNetworkCallback(previous)
                } catch (_: RuntimeException) {
                    // Already unregistered by Android.
                }
            }
        }
    }
}
