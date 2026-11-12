package com.s4daharu.virthelm

import android.Manifest
import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.KeyStore
import java.security.MessageDigest
import java.util.Calendar
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.net.ssl.HttpsURLConnection

private const val MIN_BACKGROUND_INTERVAL_MINUTES = 15
private const val MAX_BACKGROUND_INTERVAL_MINUTES = 24 * 60
private const val MAX_RESPONSE_BYTES = 512 * 1024

private data class ScheduledPolicy(
    val enabled: Boolean,
    val intervalMinutes: Int,
    val quietHoursEnabled: Boolean,
    val quietStartMinute: Int,
    val quietEndMinute: Int,
    val cooldownMinutes: Int,
) {
    fun validate() {
        require(intervalMinutes in MIN_BACKGROUND_INTERVAL_MINUTES..MAX_BACKGROUND_INTERVAL_MINUTES)
        require(quietStartMinute in 0 until 24 * 60)
        require(quietEndMinute in 0 until 24 * 60)
        require(quietStartMinute != quietEndMinute)
        require(cooldownMinutes in 0..24 * 60)
    }

    fun isQuietNow(): Boolean {
        if (!quietHoursEnabled) return false
        val calendar = Calendar.getInstance()
        val minute = calendar.get(Calendar.HOUR_OF_DAY) * 60 + calendar.get(Calendar.MINUTE)
        return if (quietStartMinute < quietEndMinute) {
            minute >= quietStartMinute && minute < quietEndMinute
        } else {
            minute >= quietStartMinute || minute < quietEndMinute
        }
    }

    fun toJson(): String = JSONObject()
        .put("enabled", enabled)
        .put("intervalMinutes", intervalMinutes)
        .put("quietHoursEnabled", quietHoursEnabled)
        .put("quietStartMinute", quietStartMinute)
        .put("quietEndMinute", quietEndMinute)
        .put("cooldownMinutes", cooldownMinutes)
        .toString()

    companion object {
        fun fromJson(raw: String?): ScheduledPolicy {
            if (raw.isNullOrBlank()) {
                return ScheduledPolicy(
                    enabled = false,
                    intervalMinutes = 30,
                    quietHoursEnabled = false,
                    quietStartMinute = 22 * 60,
                    quietEndMinute = 7 * 60,
                    cooldownMinutes = 30,
                )
            }
            val json = JSONObject(raw)
            return ScheduledPolicy(
                enabled = json.optBoolean("enabled", false),
                intervalMinutes = json.optInt("intervalMinutes", 30),
                quietHoursEnabled = json.optBoolean("quietHoursEnabled", false),
                quietStartMinute = json.optInt("quietStartMinute", 22 * 60),
                quietEndMinute = json.optInt("quietEndMinute", 7 * 60),
                cooldownMinutes = json.optInt("cooldownMinutes", 30),
            ).also { it.validate() }
        }
    }
}

private data class ScheduledSecret(
    val endpoint: String,
    val authorization: String,
)

private data class ScheduledCheckResult(
    val outcome: String,
    val complete: Boolean,
    val incident: Boolean,
)

internal object BackgroundCheckCoordinator {
    private const val PREFS_NAME = "virthelm_background_checks_v1"
    private const val KEY_ALIAS = "virthelm_background_check_key_v1"
    private const val INPUT_PROFILE_KEY = "profileKey"
    private const val INCIDENT_CHANNEL_ID = "virthelm_incidents"
    private const val INCIDENT_NOTIFICATION_ID = 4108

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun profileKey(profileId: String): String {
        require(profileId.isNotBlank() && profileId.length <= 256)
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(profileId.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }

    private fun workName(key: String) = "virthelm-periodic-node-check-$key"
    private fun policyKey(key: String) = "policy:$key"
    private fun secretKey(key: String) = "secret:$key"
    private fun incidentKey(key: String) = "incident-active:$key"
    private fun lastAttemptKey(key: String) = "last-attempt:$key"
    private fun lastSuccessKey(key: String) = "last-success:$key"
    private fun lastOutcomeKey(key: String) = "last-outcome:$key"
    private fun lastNotificationKey(key: String) = "last-notification:$key"

    fun configure(
        context: Context,
        profileId: String,
        endpoint: String,
        authorization: String,
        policy: ScheduledPolicy,
    ): Boolean {
        policy.validate()
        require(policy.enabled)
        validateEndpoint(endpoint)
        require(authorization.startsWith("PVEAPIToken="))
        require(authorization.length in 16..4096)
        require(!authorization.any { it == '\n' || it == '\r' })

        val key = profileKey(profileId)
        val encrypted = encryptSecret(
            key,
            JSONObject()
                .put("endpoint", endpoint)
                .put("authorization", authorization)
                .toString(),
        )
        val storage = prefs(context)
        val committed = storage.edit()
            .putString(policyKey(key), policy.toJson())
            .putString(secretKey(key), encrypted)
            .commit()
        if (!committed) return false

        return try {
            val request = PeriodicWorkRequest.Builder(
                BackgroundIncidentWorker::class.java,
                policy.intervalMinutes.toLong(),
                TimeUnit.MINUTES,
            )
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .build(),
                )
                .setInputData(
                    Data.Builder()
                        .putString(INPUT_PROFILE_KEY, key)
                        .build(),
                )
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                workName(key),
                ExistingPeriodicWorkPolicy.UPDATE,
                request,
            )
            true
        } catch (_: RuntimeException) {
            storage.edit()
                .remove(secretKey(key))
                .putString(policyKey(key), policy.copy(enabled = false).toJson())
                .apply()
            false
        }
    }

    fun disable(context: Context, profileId: String, clearPolicy: Boolean) {
        val key = profileKey(profileId)
        WorkManager.getInstance(context).cancelUniqueWork(workName(key))
        val storage = prefs(context)
        val editor = storage.edit()
            .remove(secretKey(key))
            .remove(incidentKey(key))
        if (clearPolicy) {
            editor
                .remove(policyKey(key))
                .remove(lastAttemptKey(key))
                .remove(lastSuccessKey(key))
                .remove(lastOutcomeKey(key))
                .remove(lastNotificationKey(key))
        } else {
            val policy = runCatching {
                ScheduledPolicy.fromJson(storage.getString(policyKey(key), null))
            }.getOrDefault(
                ScheduledPolicy(
                    enabled = false,
                    intervalMinutes = 30,
                    quietHoursEnabled = false,
                    quietStartMinute = 22 * 60,
                    quietEndMinute = 7 * 60,
                    cooldownMinutes = 30,
                ),
            )
            editor.putString(policyKey(key), policy.copy(enabled = false).toJson())
        }
        if (!editor.commit()) {
            throw IllegalStateException("Could not clear scheduled-check state.")
        }
    }

    fun status(context: Context, profileId: String): Map<String, Any?> {
        val key = profileKey(profileId)
        val storage = prefs(context)
        val policy = runCatching {
            ScheduledPolicy.fromJson(storage.getString(policyKey(key), null))
        }.getOrDefault(
            ScheduledPolicy(
                enabled = false,
                intervalMinutes = 30,
                quietHoursEnabled = false,
                quietStartMinute = 22 * 60,
                quietEndMinute = 7 * 60,
                cooldownMinutes = 30,
            ),
        )
        val enabled = policy.enabled && storage.contains(secretKey(key))
        return mapOf(
            "enabled" to enabled,
            "intervalMinutes" to policy.intervalMinutes,
            "quietHoursEnabled" to policy.quietHoursEnabled,
            "quietStartMinute" to policy.quietStartMinute,
            "quietEndMinute" to policy.quietEndMinute,
            "cooldownMinutes" to policy.cooldownMinutes,
            "lastAttemptMs" to storage.getLong(lastAttemptKey(key), 0L),
            "lastSuccessMs" to storage.getLong(lastSuccessKey(key), 0L),
            "lastNotificationMs" to storage.getLong(lastNotificationKey(key), 0L),
            "lastOutcome" to storage.getString(lastOutcomeKey(key), null),
        )
    }

    fun runPeriodicCheck(context: Context, key: String) {
        if (!key.matches(Regex("^[0-9a-f]{64}$"))) return
        val storage = prefs(context)
        val policy = runCatching {
            ScheduledPolicy.fromJson(storage.getString(policyKey(key), null))
        }.getOrNull() ?: return
        if (!policy.enabled) return
        val secret = readSecret(storage.getString(secretKey(key), null), key) ?: return
        val now = System.currentTimeMillis()
        storage.edit().putLong(lastAttemptKey(key), now).apply()

        if (isAppForeground()) {
            storage.edit().putString(lastOutcomeKey(key), "skipped_foreground").apply()
            return
        }

        val result = try {
            readNodeState(secret)
        } catch (_: Exception) {
            ScheduledCheckResult(
                outcome = "read_failed",
                complete = false,
                incident = false,
            )
        }

        val editor = storage.edit().putString(lastOutcomeKey(key), result.outcome)
        if (result.complete) editor.putLong(lastSuccessKey(key), now)
        editor.apply()

        if (!result.complete) return
        val previouslyActive = storage.getBoolean(incidentKey(key), false)
        storage.edit().putBoolean(incidentKey(key), result.incident).apply()
        if (!result.incident || previouslyActive) return
        if (policy.isQuietNow()) return

        val previousDelivery = storage.getLong(lastNotificationKey(key), 0L)
        if (policy.cooldownMinutes > 0 && previousDelivery > 0L) {
            val elapsed = now - previousDelivery
            val cooldownMs = TimeUnit.MINUTES.toMillis(policy.cooldownMinutes.toLong())
            if (elapsed in 0 until cooldownMs) return
        }
        if (showScheduledIncidentNotification(context)) {
            storage.edit().putLong(lastNotificationKey(key), now).apply()
        }
    }

    private fun isAppForeground(): Boolean {
        val state = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(state)
        return state.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND ||
            state.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE
    }

    private fun validateEndpoint(endpoint: String) {
        val uri = URI(endpoint)
        require(uri.scheme.equals("https", ignoreCase = true))
        require(!uri.host.isNullOrBlank())
        require(uri.userInfo == null)
        require(uri.query == null && uri.fragment == null)
        require(uri.path.isNullOrEmpty() || uri.path == "/")
        require(uri.port in 1..65535)
    }

    private fun readNodeState(secret: ScheduledSecret): ScheduledCheckResult {
        val url = URL(
            secret.endpoint.trimEnd('/') +
                "/api2/json/cluster/resources?type=node",
        )
        val connection = url.openConnection() as HttpsURLConnection
        connection.requestMethod = "GET"
        connection.instanceFollowRedirects = false
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        connection.useCaches = false
        connection.setRequestProperty("Accept", "application/json")
        connection.setRequestProperty("Authorization", secret.authorization)
        try {
            val code = connection.responseCode
            if (code in 300..399) {
                return ScheduledCheckResult(
                    outcome = "redirect_blocked",
                    complete = false,
                    incident = false,
                )
            }
            if (code == HttpURLConnection.HTTP_UNAUTHORIZED ||
                code == HttpURLConnection.HTTP_FORBIDDEN
            ) {
                return ScheduledCheckResult(
                    outcome = "authorization_denied",
                    complete = false,
                    incident = false,
                )
            }
            if (code !in 200..299) {
                return ScheduledCheckResult(
                    outcome = "read_failed",
                    complete = false,
                    incident = false,
                )
            }
            val body = readLimited(connection.inputStream.readBytes())
            val root = JSONObject(body)
            val data = root.opt("data")
            if (data !is JSONArray) {
                return ScheduledCheckResult(
                    outcome = "incomplete",
                    complete = false,
                    incident = false,
                )
            }
            var usableNodes = 0
            var incident = false
            for (index in 0 until data.length()) {
                val item = data.optJSONObject(index) ?: continue
                if (item.optString("type") != "node") continue
                val status = item.optString("status").trim().lowercase()
                if (status.isEmpty()) continue
                usableNodes += 1
                if (status != "online") incident = true
            }
            if (usableNodes == 0) {
                return ScheduledCheckResult(
                    outcome = "incomplete",
                    complete = false,
                    incident = false,
                )
            }
            return ScheduledCheckResult(
                outcome = if (incident) "incident" else "healthy",
                complete = true,
                incident = incident,
            )
        } finally {
            connection.disconnect()
        }
    }

    private fun readLimited(bytes: ByteArray): String {
        require(bytes.size <= MAX_RESPONSE_BYTES)
        return bytes.toString(Charsets.UTF_8)
    }

    private fun showScheduledIncidentNotification(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            INCIDENT_CHANNEL_ID,
            "Incident alerts",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "VirtHelm incident summaries"
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        }
        manager.createNotificationChannel(channel)

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val contentIntent = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = Notification.Builder(context, INCIDENT_CHANNEL_ID)
            .setSmallIcon(R.drawable.virthelm_notification)
            .setContentTitle("VirtHelm scheduled incident")
            .setContentText("Open VirtHelm to review current incidents.")
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_STATUS)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build()
        manager.notify(INCIDENT_NOTIFICATION_ID, notification)
        return true
    }

    private fun encryptSecret(profileKey: String, cleartext: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        cipher.updateAAD(profileKey.toByteArray(Charsets.UTF_8))
        val encrypted = cipher.doFinal(cleartext.toByteArray(Charsets.UTF_8))
        return JSONObject()
            .put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .put("ciphertext", Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .toString()
    }

    private fun readSecret(raw: String?, profileKey: String): ScheduledSecret? {
        if (raw.isNullOrBlank()) return null
        return runCatching {
            val json = JSONObject(raw)
            val iv = Base64.decode(json.getString("iv"), Base64.NO_WRAP)
            val encrypted =
                Base64.decode(json.getString("ciphertext"), Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                getOrCreateKey(),
                GCMParameterSpec(128, iv),
            )
            cipher.updateAAD(profileKey.toByteArray(Charsets.UTF_8))
            val cleartext = cipher.doFinal(encrypted).toString(Charsets.UTF_8)
            val decoded = JSONObject(cleartext)
            ScheduledSecret(
                endpoint = decoded.getString("endpoint"),
                authorization = decoded.getString("authorization"),
            ).also {
                validateEndpoint(it.endpoint)
                require(it.authorization.startsWith("PVEAPIToken="))
            }
        }.getOrNull()
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(KEY_ALIAS, null)
        if (existing is SecretKey) return existing
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }
}

class BackgroundIncidentWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {
    override fun doWork(): Result {
        val profileKey = inputData.getString("profileKey") ?: return Result.success()
        BackgroundCheckCoordinator.runPeriodicCheck(applicationContext, profileKey)
        // Periodic checks never request an immediate retry. The next inexact
        // WorkManager period is the only automatic retry boundary.
        return Result.success()
    }
}

internal object BackgroundCheckBridge {
    private const val CHANNEL = "com.s4daharu.virthelm/background_checks"

    fun register(context: Context, flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "configure" -> {
                        val policy = ScheduledPolicy(
                            enabled = true,
                            intervalMinutes = call.requireInt("intervalMinutes"),
                            quietHoursEnabled =
                                call.argument<Boolean>("quietHoursEnabled") == true,
                            quietStartMinute = call.requireInt("quietStartMinute"),
                            quietEndMinute = call.requireInt("quietEndMinute"),
                            cooldownMinutes = call.requireInt("cooldownMinutes"),
                        )
                        result.success(
                            BackgroundCheckCoordinator.configure(
                                context = context,
                                profileId = call.requireString("profileId"),
                                endpoint = call.requireString("endpoint"),
                                authorization = call.requireString("authorization"),
                                policy = policy,
                            ),
                        )
                    }
                    "disable" -> {
                        BackgroundCheckCoordinator.disable(
                            context,
                            call.requireString("profileId"),
                            call.argument<Boolean>("clearPolicy") == true,
                        )
                        result.success(null)
                    }
                    "status" -> result.success(
                        BackgroundCheckCoordinator.status(
                            context,
                            call.requireString("profileId"),
                        ),
                    )
                    else -> result.notImplemented()
                }
            } catch (_: IllegalArgumentException) {
                result.error(
                    "invalid_configuration",
                    "Scheduled-check configuration is invalid.",
                    null,
                )
            } catch (_: Exception) {
                result.error(
                    "background_check_error",
                    "Could not update scheduled checks.",
                    null,
                )
            }
        }
    }

    private fun io.flutter.plugin.common.MethodCall.requireString(name: String): String =
        argument<String>(name)?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("Missing $name")

    private fun io.flutter.plugin.common.MethodCall.requireInt(name: String): Int =
        argument<Int>(name) ?: throw IllegalArgumentException("Missing $name")
}
