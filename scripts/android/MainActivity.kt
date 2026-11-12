package com.s4daharu.virthelm

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// Native Android hints and foreground notification delivery. WorkManager
// registration lives in BackgroundIncidentWorker.kt; neither path is proof
// that Proxmox is continuously reachable.
class MainActivity : FlutterActivity() {
    private var networkEvents: NetworkEvents? = null
    private var notificationPermissionResult: MethodChannel.Result? = null
    private var incidentNavigationChannel: MethodChannel? = null
    private var pendingIncidentNavigation = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val observer = NetworkEvents(manager)
        networkEvents = observer
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.s4daharu.virthelm/device_network",
        ).setStreamHandler(observer)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> requestNotificationPermission(result)
                "setLockScreenPrivacy" -> result.success(
                    IncidentNotificationPrivacy.set(
                        applicationContext,
                        call.argument<String>("privacy"),
                    ),
                )
                "showIncidentSummary" -> result.success(
                    showIncidentSummary(
                        critical = call.argument<Boolean>("critical") == true,
                    ),
                )
                else -> result.notImplemented()
            }
        }

        val navigationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            INCIDENT_NAVIGATION_CHANNEL,
        )
        incidentNavigationChannel = navigationChannel
        navigationChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePendingIncidentIntent" ->
                    result.success(takePendingIncidentNavigation())
                else -> result.notImplemented()
            }
        }

        BackgroundCheckBridge.register(applicationContext, flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (!IncidentNotificationNavigation.targetsIncidents(intent)) return
        intent.action = null
        pendingIncidentNavigation = true
        incidentNavigationChannel?.invokeMethod(
            "openIncidents",
            null,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    pendingIncidentNavigation = false
                }

                override fun error(
                    errorCode: String,
                    errorMessage: String?,
                    errorDetails: Any?,
                ) {
                    // Keep the request pending for the Dart resume fallback.
                }

                override fun notImplemented() {
                    // Keep the request pending for the Dart resume fallback.
                }
            },
        )
    }

    private fun takePendingIncidentNavigation(): Boolean {
        val currentIntentTargetsIncidents =
            IncidentNotificationNavigation.targetsIncidents(intent)
        if (currentIntentTargetsIncidents) {
            intent?.action = null
        }
        val shouldOpen = pendingIncidentNavigation || currentIntentTargetsIncidents
        pendingIncidentNavigation = false
        return shouldOpen
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST) {
            val pending = notificationPermissionResult
            notificationPermissionResult = null
            pending?.success(
                grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED,
            )
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (notificationPermissionResult != null) {
            result.error(
                "permission_in_progress",
                "A notification permission request is already active.",
                null,
            )
            return
        }
        notificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    private fun showIncidentSummary(critical: Boolean): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val visibility = IncidentNotificationPrivacy.visibility(this)
        val channel = NotificationChannel(
            INCIDENT_CHANNEL_ID,
            "Incident alerts",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Foreground VirtHelm incident summaries"
            lockscreenVisibility = visibility
        }
        manager.createNotificationChannel(channel)

        val contentIntent = IncidentNotificationNavigation.contentIntent(this)
        val notification = Notification.Builder(this, INCIDENT_CHANNEL_ID)
            .setSmallIcon(R.drawable.virthelm_notification)
            .setContentTitle(
                if (critical) "VirtHelm critical incident" else "VirtHelm incident",
            )
            .setContentText("Open VirtHelm to review current incidents.")
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_STATUS)
            .setVisibility(visibility)
            .build()
        manager.notify(INCIDENT_NOTIFICATION_ID, notification)
        return true
    }

    override fun onDestroy() {
        networkEvents?.onCancel(null)
        networkEvents = null
        notificationPermissionResult?.success(false)
        notificationPermissionResult = null
        incidentNavigationChannel?.setMethodCallHandler(null)
        incidentNavigationChannel = null
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

    companion object {
        private const val NOTIFICATION_METHOD_CHANNEL =
            "com.s4daharu.virthelm/incident_notifications"
        private const val NOTIFICATION_PERMISSION_REQUEST = 4107
        private const val INCIDENT_NAVIGATION_CHANNEL =
            "com.s4daharu.virthelm/incident_navigation"
        private const val INCIDENT_CHANNEL_ID = "virthelm_incidents"
        private const val INCIDENT_NOTIFICATION_ID = 4108
    }
}
