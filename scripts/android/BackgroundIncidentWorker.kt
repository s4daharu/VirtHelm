package com.s4daharu.virthelm

import android.Manifest
import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
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
import java.io.InputStream
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
private const val MAX_BACKGROUND_TASK_NODES = 16
private const val MAX_BACKGROUND_NODE_CPU_RULES = 32

internal object IncidentNotificationPrivacy {
    private const val PREFS_NAME = "virthelm_notification_privacy_v1"
    private const val KEY_LOCK_SCREEN = "lock_screen"

    fun set(context: Context, raw: String?): Boolean {
        val normalized = when (raw) {
            "hidden", "generic" -> raw
            else -> return false
        }
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_LOCK_SCREEN, normalized)
            .commit()
    }

    fun visibility(context: Context): Int {
        val value = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_LOCK_SCREEN, null)
        return if (value == "generic") {
            Notification.VISIBILITY_PRIVATE
        } else {
            Notification.VISIBILITY_SECRET
        }
    }
}

internal object IncidentNotificationDeliveryLedger {
    private const val PREFS_NAME = "virthelm_incident_delivery_v1"
    private const val KEY_PREFIX = "last:"
    private val lock = Any()

    fun profileKey(profileId: String): String {
        require(profileId.isNotBlank() && profileId.length <= 256)
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(profileId.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }

    fun deliver(
        context: Context,
        profileKey: String,
        cooldownMinutes: Int,
        nowMs: Long = System.currentTimeMillis(),
        post: () -> Boolean,
    ): Boolean {
        require(profileKey.matches(Regex("^[0-9a-f]{64}$")))
        require(cooldownMinutes in 0..24 * 60)
        return synchronized(lock) {
            val storage =
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val key = KEY_PREFIX + profileKey
            val previous = storage.getLong(key, 0L)
            if (previous > nowMs) {
                storage.edit().remove(key).apply()
            } else if (cooldownMinutes > 0 && previous > 0L) {
                val cooldownMs =
                    TimeUnit.MINUTES.toMillis(cooldownMinutes.toLong())
                if (nowMs - previous < cooldownMs) return@synchronized false
            }
            val shown = post()
            if (shown) {
                // apply() updates the in-memory value immediately and avoids
                // synchronous disk I/O on the activity main thread.
                storage.edit().putLong(key, nowMs).apply()
            }
            shown
        }
    }

    fun clearKey(context: Context, profileKey: String) {
        if (!profileKey.matches(Regex("^[0-9a-f]{64}$"))) return
        synchronized(lock) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .remove(KEY_PREFIX + profileKey)
                .apply()
        }
    }
}

internal object IncidentNotificationNavigation {
    const val ACTION_OPEN_INCIDENTS =
        "com.s4daharu.virthelm.action.OPEN_INCIDENTS"
    private const val REQUEST_CODE = 4109

    fun contentIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN_INCIDENTS
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun targetsIncidents(intent: Intent?): Boolean =
        intent?.action == ACTION_OPEN_INCIDENTS
}

internal data class ScheduledPolicy(
    val enabled: Boolean,
    val intervalMinutes: Int,
    val quietHoursEnabled: Boolean,
    val quietStartMinute: Int,
    val quietEndMinute: Int,
    val cooldownMinutes: Int,
    val failedTaskChecksEnabled: Boolean,
    val nodeCpuThresholdChecksEnabled: Boolean,
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
        .put("failedTaskChecksEnabled", failedTaskChecksEnabled)
        .put("nodeCpuThresholdChecksEnabled", nodeCpuThresholdChecksEnabled)
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
                    failedTaskChecksEnabled = false,
                    nodeCpuThresholdChecksEnabled = false,
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
                failedTaskChecksEnabled =
                    json.optBoolean("failedTaskChecksEnabled", false),
                nodeCpuThresholdChecksEnabled =
                    json.optBoolean("nodeCpuThresholdChecksEnabled", false),
            ).also { it.validate() }
        }
    }
}

private data class ScheduledNodeCpuRule(
    val id: String,
    val node: String,
    val thresholdPercent: Int,
    val consecutiveSamples: Int,
    val hysteresisPercent: Int,
) {
    fun validate() {
        require(id.isNotBlank() && id.length <= 80)
        require(node.isNotBlank() && node.length <= 120)
        require(!node.any { it.code < 0x20 || it.code == 0x7f })
        require(thresholdPercent in 1..100)
        require(consecutiveSamples in 1..10)
        require(hysteresisPercent in 0..20)
        require(hysteresisPercent < thresholdPercent)
    }

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("node", node)
        .put("thresholdPercent", thresholdPercent)
        .put("consecutiveSamples", consecutiveSamples)
        .put("hysteresisPercent", hysteresisPercent)

    companion object {
        fun fromJson(json: JSONObject): ScheduledNodeCpuRule =
            ScheduledNodeCpuRule(
                id = json.getString("id"),
                node = json.getString("node").trim(),
                thresholdPercent = json.getInt("thresholdPercent"),
                consecutiveSamples = json.getInt("consecutiveSamples"),
                hysteresisPercent = json.getInt("hysteresisPercent"),
            ).also { it.validate() }

        fun fromChannel(raw: Any?): ScheduledNodeCpuRule {
            val map = raw as? Map<*, *>
                ?: throw IllegalArgumentException("Invalid threshold rule")
            return ScheduledNodeCpuRule(
                id = map["id"] as? String
                    ?: throw IllegalArgumentException("Missing rule id"),
                node = (map["node"] as? String)?.trim()
                    ?: throw IllegalArgumentException("Missing rule node"),
                thresholdPercent = map["thresholdPercent"] as? Int
                    ?: throw IllegalArgumentException("Missing rule threshold"),
                consecutiveSamples = map["consecutiveSamples"] as? Int
                    ?: throw IllegalArgumentException("Missing rule samples"),
                hysteresisPercent = map["hysteresisPercent"] as? Int
                    ?: throw IllegalArgumentException("Missing rule hysteresis"),
            ).also { it.validate() }
        }
    }
}

private data class ScheduledSecret(
    val endpoint: String,
    val authorization: String,
    val nodeCpuThresholdRules: List<ScheduledNodeCpuRule> = emptyList(),
)

private data class NodeStateReadResult(
    val outcome: String,
    val complete: Boolean,
    val incident: Boolean,
    val nodes: List<String> = emptyList(),
    val taskNodesComplete: Boolean = false,
    val cpuByNode: Map<String, Double> = emptyMap(),
)

private data class FailedTaskReadResult(
    val outcome: String,
    val complete: Boolean,
    val incident: Boolean,
    val newIncident: Boolean,
    val watermarkSeconds: Long,
)

private data class ThresholdRuleRuntimeState(
    val pendingSamples: Int,
    val active: Boolean,
)

private data class ThresholdEvaluationResult(
    val complete: Boolean,
    val incident: Boolean,
    val newIncident: Boolean,
    val stateJson: String?,
)

private data class ScheduledCheckResult(
    val outcome: String,
    val complete: Boolean,
    val nodeComplete: Boolean,
    val nodeIncident: Boolean,
    val taskComplete: Boolean,
    val taskIncident: Boolean,
    val taskNewIncident: Boolean,
    val taskWatermarkSeconds: Long?,
    val thresholdComplete: Boolean,
    val thresholdIncident: Boolean,
    val thresholdNewIncident: Boolean,
    val thresholdStateJson: String?,
)

internal object BackgroundCheckCoordinator {
    private const val PREFS_NAME = "virthelm_background_checks_v1"
    private const val KEY_ALIAS = "virthelm_background_check_key_v1"
    private const val INPUT_PROFILE_KEY = "profileKey"
    private const val INCIDENT_CHANNEL_ID = "virthelm_incidents"
    private const val INCIDENT_NOTIFICATION_ID = 4108

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun profileKey(profileId: String): String =
        IncidentNotificationDeliveryLedger.profileKey(profileId)

    private fun workName(key: String) = "virthelm-periodic-node-check-$key"
    private fun policyKey(key: String) = "policy:$key"
    private fun secretKey(key: String) = "secret:$key"
    private fun legacyIncidentKey(key: String) = "incident-active:$key"
    private fun nodeIncidentKey(key: String) = "node-incident-active:$key"
    private fun taskIncidentKey(key: String) = "task-incident-active:$key"
    private fun taskWatermarkKey(key: String) = "task-watermark:$key"
    private fun thresholdStateKey(key: String) = "node-cpu-threshold-state:$key"
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
        nodeCpuThresholdRules: List<ScheduledNodeCpuRule>,
    ): Boolean {
        policy.validate()
        require(policy.enabled)
        validateEndpoint(endpoint)
        require(authorization.startsWith("PVEAPIToken="))
        require(authorization.length in 16..4096)
        require(!authorization.any { it == '\n' || it == '\r' })
        val effectiveRules =
            if (policy.nodeCpuThresholdChecksEnabled) {
                validateNodeCpuRules(nodeCpuThresholdRules)
            } else {
                emptyList()
            }

        val key = profileKey(profileId)
        val encrypted = encryptSecret(
            key,
            encodeSecret(
                ScheduledSecret(
                    endpoint = endpoint,
                    authorization = authorization,
                    nodeCpuThresholdRules = effectiveRules,
                ),
            ),
        )
        val storage = prefs(context)
        val committed = storage.edit()
            .putString(policyKey(key), policy.toJson())
            .putString(secretKey(key), encrypted)
            .commit()
        if (!committed) return false
        reconcileThresholdState(storage, key, effectiveRules)

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
                .remove(thresholdStateKey(key))
                .putString(policyKey(key), policy.copy(enabled = false).toJson())
                .apply()
            false
        }
    }

    fun syncNodeCpuThresholdRules(
        context: Context,
        profileId: String,
        nodeCpuThresholdRules: List<ScheduledNodeCpuRule>,
    ): Boolean {
        val key = profileKey(profileId)
        val storage = prefs(context)
        val policy = runCatching {
            ScheduledPolicy.fromJson(storage.getString(policyKey(key), null))
        }.getOrNull()
        if (policy == null || !policy.enabled) {
            storage.edit().remove(thresholdStateKey(key)).apply()
            return true
        }
        val existing =
            readSecret(storage.getString(secretKey(key), null), key)
                ?: return false
        val effectiveRules =
            if (policy.nodeCpuThresholdChecksEnabled) {
                validateNodeCpuRules(nodeCpuThresholdRules)
            } else {
                emptyList()
            }
        val encrypted = encryptSecret(
            key,
            encodeSecret(existing.copy(nodeCpuThresholdRules = effectiveRules)),
        )
        if (!storage.edit().putString(secretKey(key), encrypted).commit()) {
            return false
        }
        reconcileThresholdState(storage, key, effectiveRules)
        return true
    }

    fun disable(context: Context, profileId: String, clearPolicy: Boolean) {
        val key = profileKey(profileId)
        WorkManager.getInstance(context).cancelUniqueWork(workName(key))
        val storage = prefs(context)
        val editor = storage.edit()
            .remove(secretKey(key))
            .remove(legacyIncidentKey(key))
            .remove(nodeIncidentKey(key))
            .remove(taskIncidentKey(key))
            .remove(taskWatermarkKey(key))
            .remove(thresholdStateKey(key))
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
                    failedTaskChecksEnabled = false,
                    nodeCpuThresholdChecksEnabled = false,
                ),
            )
            editor.putString(policyKey(key), policy.copy(enabled = false).toJson())
        }
        if (!editor.commit()) {
            throw IllegalStateException("Could not clear scheduled-check state.")
        }
        if (clearPolicy) {
            IncidentNotificationDeliveryLedger.clearKey(context, key)
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
                failedTaskChecksEnabled = false,
                nodeCpuThresholdChecksEnabled = false,
            ),
        )
        val secretAvailable =
            readSecret(storage.getString(secretKey(key), null), key) != null
        val enabled = policy.enabled && secretAvailable
        return mapOf(
            "enabled" to enabled,
            "intervalMinutes" to policy.intervalMinutes,
            "quietHoursEnabled" to policy.quietHoursEnabled,
            "quietStartMinute" to policy.quietStartMinute,
            "quietEndMinute" to policy.quietEndMinute,
            "cooldownMinutes" to policy.cooldownMinutes,
            "failedTaskChecksEnabled" to policy.failedTaskChecksEnabled,
            "nodeCpuThresholdChecksEnabled" to
                policy.nodeCpuThresholdChecksEnabled,
            "lastAttemptMs" to storage.getLong(lastAttemptKey(key), 0L),
            "lastSuccessMs" to storage.getLong(lastSuccessKey(key), 0L),
            "lastNotificationMs" to storage.getLong(lastNotificationKey(key), 0L),
            "lastOutcome" to if (policy.enabled && !secretAvailable) {
                "configuration_unavailable"
            } else {
                storage.getString(lastOutcomeKey(key), null)
            },
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
            readScheduledState(
                secret = secret,
                policy = policy,
                previousTaskWatermarkSeconds =
                    storage.getLong(taskWatermarkKey(key), 0L),
                previousThresholdState =
                    storage.getString(thresholdStateKey(key), null),
            )
        } catch (_: Exception) {
            ScheduledCheckResult(
                outcome = "read_failed",
                complete = false,
                nodeComplete = false,
                nodeIncident = false,
                taskComplete = false,
                taskIncident = false,
                taskNewIncident = false,
                taskWatermarkSeconds = null,
                thresholdComplete = false,
                thresholdIncident = false,
                thresholdNewIncident = false,
                thresholdStateJson = null,
            )
        }

        val editor = storage.edit().putString(lastOutcomeKey(key), result.outcome)
        if (result.complete) editor.putLong(lastSuccessKey(key), now)

        val legacyNodeActive = storage.getBoolean(legacyIncidentKey(key), false)
        val previousNodeActive =
            storage.getBoolean(nodeIncidentKey(key), legacyNodeActive)
        var newlyActive = false
        if (result.nodeComplete) {
            editor.putBoolean(nodeIncidentKey(key), result.nodeIncident)
            if (result.nodeIncident && !previousNodeActive) newlyActive = true
        }
        if (result.taskComplete) {
            editor.putBoolean(taskIncidentKey(key), result.taskIncident)
            result.taskWatermarkSeconds?.let {
                editor.putLong(taskWatermarkKey(key), it)
            }
            if (result.taskNewIncident) newlyActive = true
        }
        result.thresholdStateJson?.let {
            editor.putString(thresholdStateKey(key), it)
        }
        if (result.thresholdNewIncident) newlyActive = true
        editor.remove(legacyIncidentKey(key)).apply()

        if (!newlyActive) return
        if (policy.isQuietNow()) return

        if (
            showScheduledIncidentNotification(
                context = context,
                profileKey = key,
                cooldownMinutes = policy.cooldownMinutes,
                nowMs = now,
            )
        ) {
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

    private fun isSafeNodePathSegment(value: String): Boolean =
        value != "." &&
            value != ".." &&
            value.matches(Regex("^[A-Za-z0-9._-]{1,128}$"))

    private fun thresholdRuleStateId(ruleId: String): String =
        IncidentNotificationDeliveryLedger.profileKey(ruleId)

    private fun readThresholdState(
        raw: String?,
        rules: List<ScheduledNodeCpuRule>,
    ): MutableMap<String, ThresholdRuleRuntimeState>? {
        if (raw == null) return mutableMapOf()
        return runCatching {
            val json = JSONObject(raw)
            val allowed = rules.map { thresholdRuleStateId(it.id) }.toSet()
            val state = mutableMapOf<String, ThresholdRuleRuntimeState>()
            val keys = json.keys()
            while (keys.hasNext()) {
                val id = keys.next()
                require(id.matches(Regex("^[0-9a-f]{64}$")))
                if (!allowed.contains(id)) continue
                val item = json.getJSONObject(id)
                val pending = item.getInt("pending")
                val active = item.getBoolean("active")
                require(pending in 0..10)
                state[id] = ThresholdRuleRuntimeState(
                    pendingSamples = pending,
                    active = active,
                )
            }
            state
        }.getOrNull()
    }

    private fun encodeThresholdState(
        rules: List<ScheduledNodeCpuRule>,
        states: Map<String, ThresholdRuleRuntimeState>,
    ): String {
        val json = JSONObject()
        for (rule in rules) {
            val id = thresholdRuleStateId(rule.id)
            val state = states[id] ?: ThresholdRuleRuntimeState(
                pendingSamples = 0,
                active = false,
            )
            json.put(
                id,
                JSONObject()
                    .put("pending", state.pendingSamples)
                    .put("active", state.active),
            )
        }
        return json.toString()
    }

    private fun reconcileThresholdState(
        storage: SharedPreferences,
        profileKey: String,
        rules: List<ScheduledNodeCpuRule>,
    ) {
        if (rules.isEmpty()) {
            storage.edit().remove(thresholdStateKey(profileKey)).apply()
            return
        }
        val existing = readThresholdState(
            storage.getString(thresholdStateKey(profileKey), null),
            rules,
        ) ?: mutableMapOf()
        storage.edit()
            .putString(
                thresholdStateKey(profileKey),
                encodeThresholdState(rules, existing),
            )
            .apply()
    }

    private fun evaluateNodeCpuThresholds(
        rules: List<ScheduledNodeCpuRule>,
        cpuByNode: Map<String, Double>,
        rawState: String?,
    ): ThresholdEvaluationResult {
        val states = readThresholdState(rawState, rules)
            ?: return ThresholdEvaluationResult(
                complete = false,
                incident = false,
                newIncident = false,
                stateJson = null,
            )
        var complete = true
        var newIncident = false

        for (rule in rules) {
            val stateId = thresholdRuleStateId(rule.id)
            val previous = states[stateId] ?: ThresholdRuleRuntimeState(
                pendingSamples = 0,
                active = false,
            )
            val sample = cpuByNode[rule.node]
            if (sample == null) {
                complete = false
                states[stateId] = previous.copy(pendingSamples = 0)
                continue
            }

            if (previous.active) {
                val clearPercent =
                    rule.thresholdPercent - rule.hysteresisPercent
                val shouldResolve =
                    if (rule.hysteresisPercent == 0) {
                        sample < rule.thresholdPercent / 100.0
                    } else {
                        sample <= clearPercent / 100.0
                    }
                states[stateId] =
                    if (shouldResolve) {
                        ThresholdRuleRuntimeState(
                            pendingSamples = 0,
                            active = false,
                        )
                    } else {
                        previous.copy(pendingSamples = 0)
                    }
                continue
            }

            if (sample < rule.thresholdPercent / 100.0) {
                states[stateId] = ThresholdRuleRuntimeState(
                    pendingSamples = 0,
                    active = false,
                )
                continue
            }
            val pending = previous.pendingSamples + 1
            if (pending >= rule.consecutiveSamples) {
                states[stateId] = ThresholdRuleRuntimeState(
                    pendingSamples = 0,
                    active = true,
                )
                newIncident = true
            } else {
                states[stateId] = ThresholdRuleRuntimeState(
                    pendingSamples = pending,
                    active = false,
                )
            }
        }

        val incident = rules.any { rule ->
            states[thresholdRuleStateId(rule.id)]?.active == true
        }
        return ThresholdEvaluationResult(
            complete = complete,
            incident = incident,
            newIncident = newIncident,
            stateJson = encodeThresholdState(rules, states),
        )
    }

    private fun readScheduledState(
        secret: ScheduledSecret,
        policy: ScheduledPolicy,
        previousTaskWatermarkSeconds: Long,
        previousThresholdState: String?,
    ): ScheduledCheckResult {
        val node = readNodeState(secret)
        if (!node.complete) {
            return ScheduledCheckResult(
                outcome = node.outcome,
                complete = false,
                nodeComplete = false,
                nodeIncident = false,
                taskComplete = !policy.failedTaskChecksEnabled,
                taskIncident = false,
                taskNewIncident = false,
                taskWatermarkSeconds = null,
                thresholdComplete = !policy.nodeCpuThresholdChecksEnabled,
                thresholdIncident = false,
                thresholdNewIncident = false,
                thresholdStateJson = null,
            )
        }

        val tasks = if (!policy.failedTaskChecksEnabled) {
            FailedTaskReadResult(
                outcome = "healthy",
                complete = true,
                incident = false,
                newIncident = false,
                watermarkSeconds = previousTaskWatermarkSeconds,
            )
        } else if (node.taskNodesComplete) {
            readFailedTaskState(
                secret = secret,
                nodes = node.nodes,
                previousWatermarkSeconds = previousTaskWatermarkSeconds,
            )
        } else {
            FailedTaskReadResult(
                outcome = "task_incomplete",
                complete = false,
                incident = false,
                newIncident = false,
                watermarkSeconds = previousTaskWatermarkSeconds,
            )
        }

        val thresholds = if (policy.nodeCpuThresholdChecksEnabled) {
            evaluateNodeCpuThresholds(
                rules = secret.nodeCpuThresholdRules,
                cpuByNode = node.cpuByNode,
                rawState = previousThresholdState,
            )
        } else {
            ThresholdEvaluationResult(
                complete = true,
                incident = false,
                newIncident = false,
                stateJson = null,
            )
        }

        val complete = tasks.complete && thresholds.complete
        val outcome = when {
            !tasks.complete -> tasks.outcome
            !thresholds.complete -> "threshold_incomplete"
            !policy.failedTaskChecksEnabled &&
                !policy.nodeCpuThresholdChecksEnabled ->
                if (node.incident) "incident" else "healthy"
            node.incident && tasks.incident && thresholds.incident ->
                "node_task_threshold_incident"
            node.incident && tasks.incident -> "node_and_task_incident"
            node.incident && thresholds.incident ->
                "node_and_threshold_incident"
            tasks.incident && thresholds.incident ->
                "task_and_threshold_incident"
            node.incident -> "node_incident"
            tasks.incident -> "task_incident"
            thresholds.incident -> "threshold_incident"
            else -> "healthy"
        }
        return ScheduledCheckResult(
            outcome = outcome,
            complete = complete,
            nodeComplete = true,
            nodeIncident = node.incident,
            taskComplete = tasks.complete,
            taskIncident = tasks.incident,
            taskNewIncident = tasks.newIncident,
            taskWatermarkSeconds =
                if (tasks.complete && policy.failedTaskChecksEnabled) {
                    tasks.watermarkSeconds
                } else {
                    null
                },
            thresholdComplete = thresholds.complete,
            thresholdIncident = thresholds.incident,
            thresholdNewIncident = thresholds.newIncident,
            thresholdStateJson = thresholds.stateJson,
        )
    }

    private fun readNodeState(secret: ScheduledSecret): NodeStateReadResult {
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
                return NodeStateReadResult(
                    outcome = "redirect_blocked",
                    complete = false,
                    incident = false,
                )
            }
            if (code == HttpURLConnection.HTTP_UNAUTHORIZED ||
                code == HttpURLConnection.HTTP_FORBIDDEN
            ) {
                return NodeStateReadResult(
                    outcome = "authorization_denied",
                    complete = false,
                    incident = false,
                )
            }
            if (code !in 200..299) {
                return NodeStateReadResult(
                    outcome = "read_failed",
                    complete = false,
                    incident = false,
                )
            }
            val body = connection.inputStream.use { readLimited(it) }
            val root = JSONObject(body)
            val data = root.opt("data")
            if (data !is JSONArray) {
                return NodeStateReadResult(
                    outcome = "incomplete",
                    complete = false,
                    incident = false,
                )
            }
            var usableNodes = 0
            var incident = false
            var taskNodesComplete = true
            val nodes = mutableListOf<String>()
            val cpuByNode = mutableMapOf<String, Double>()
            val seenCpuNodeIds = mutableSetOf<String>()
            for (index in 0 until data.length()) {
                val item = data.optJSONObject(index) ?: continue
                if (item.optString("type") != "node") continue
                val status = item.optString("status").trim().lowercase()
                if (status.isEmpty()) continue
                usableNodes += 1
                if (status != "online") incident = true

                val nodeName = item.optString("node").trim()
                if (!isSafeNodePathSegment(nodeName)) {
                    taskNodesComplete = false
                } else {
                    nodes.add(nodeName)
                }

                val rawCpu = item.opt("cpu")
                val cpu = (rawCpu as? Number)?.toDouble()
                val cpuIdentityUsable =
                    nodeName.isNotEmpty() &&
                        nodeName.length <= 120 &&
                        !nodeName.any { it.code < 0x20 || it.code == 0x7f }
                if (cpuIdentityUsable) {
                    if (!seenCpuNodeIds.add(nodeName)) {
                        cpuByNode.remove(nodeName)
                    } else if (
                        cpu != null &&
                        cpu.isFinite() &&
                        cpu in 0.0..1.0
                    ) {
                        cpuByNode[nodeName] = cpu
                    }
                }
            }
            if (usableNodes == 0) {
                return NodeStateReadResult(
                    outcome = "incomplete",
                    complete = false,
                    incident = false,
                )
            }
            val uniqueNodes = nodes.distinct()
            if (uniqueNodes.size != usableNodes) {
                taskNodesComplete = false
            }
            return NodeStateReadResult(
                outcome = if (incident) "incident" else "healthy",
                complete = true,
                incident = incident,
                nodes = uniqueNodes,
                taskNodesComplete = taskNodesComplete,
                cpuByNode = cpuByNode.toMap(),
            )
        } finally {
            connection.disconnect()
        }
    }

    private fun readFailedTaskState(
        secret: ScheduledSecret,
        nodes: List<String>,
        previousWatermarkSeconds: Long,
    ): FailedTaskReadResult {
        if (nodes.isEmpty() || nodes.size > MAX_BACKGROUND_TASK_NODES) {
            return FailedTaskReadResult(
                outcome = "task_incomplete",
                complete = false,
                incident = false,
                newIncident = false,
                watermarkSeconds = previousWatermarkSeconds,
            )
        }
        var incident = false
        var newIncident = false
        var watermarkSeconds = previousWatermarkSeconds
        for (node in nodes) {
            if (!isSafeNodePathSegment(node)) {
                return FailedTaskReadResult(
                    outcome = "task_incomplete",
                    complete = false,
                    incident = false,
                    newIncident = false,
                    watermarkSeconds = previousWatermarkSeconds,
                )
            }
            val url = URL(
                secret.endpoint.trimEnd('/') +
                    "/api2/json/nodes/$node/tasks?limit=20&source=all",
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
                    return FailedTaskReadResult(
                        outcome = "task_redirect_blocked",
                        complete = false,
                        incident = false,
                        newIncident = false,
                        watermarkSeconds = previousWatermarkSeconds,
                    )
                }
                if (code == HttpURLConnection.HTTP_UNAUTHORIZED ||
                    code == HttpURLConnection.HTTP_FORBIDDEN
                ) {
                    return FailedTaskReadResult(
                        outcome = "task_authorization_denied",
                        complete = false,
                        incident = false,
                        newIncident = false,
                        watermarkSeconds = previousWatermarkSeconds,
                    )
                }
                if (code !in 200..299) {
                    return FailedTaskReadResult(
                        outcome = "task_read_failed",
                        complete = false,
                        incident = false,
                        newIncident = false,
                        watermarkSeconds = previousWatermarkSeconds,
                    )
                }
                val body = connection.inputStream.use { readLimited(it) }
                val root = JSONObject(body)
                val data = root.opt("data")
                if (data !is JSONArray) {
                    return FailedTaskReadResult(
                        outcome = "task_incomplete",
                        complete = false,
                        incident = false,
                        newIncident = false,
                        watermarkSeconds = previousWatermarkSeconds,
                    )
                }
                for (index in 0 until data.length()) {
                    val item = data.optJSONObject(index)
                        ?: return FailedTaskReadResult(
                            outcome = "task_incomplete",
                            complete = false,
                            incident = false,
                            newIncident = false,
                            watermarkSeconds = previousWatermarkSeconds,
                        )
                    val rawStatus = item.optString("status").trim()
                    if (rawStatus.isEmpty()) {
                        return FailedTaskReadResult(
                            outcome = "task_incomplete",
                            complete = false,
                            incident = false,
                            newIncident = false,
                            watermarkSeconds = previousWatermarkSeconds,
                        )
                    }
                    if (rawStatus.equals("RUNNING", ignoreCase = true)) {
                        continue
                    }
                    val endTimeSeconds = item.optLong("endtime", 0L)
                    if (endTimeSeconds > 0L) {
                        watermarkSeconds = maxOf(watermarkSeconds, endTimeSeconds)
                    }
                    if (rawStatus.equals("unknown", ignoreCase = true)) {
                        continue
                    }
                    val explicitExitStatus = item.optString("exitstatus").trim()
                    val exitStatus = if (explicitExitStatus.isNotEmpty()) {
                        explicitExitStatus
                    } else if (rawStatus.equals("stopped", ignoreCase = true)) {
                        null
                    } else {
                        rawStatus
                    }
                    if (exitStatus != null &&
                        !exitStatus.equals("OK", ignoreCase = true)
                    ) {
                        if (endTimeSeconds <= 0L) {
                            return FailedTaskReadResult(
                                outcome = "task_incomplete",
                                complete = false,
                                incident = false,
                                newIncident = false,
                                watermarkSeconds = previousWatermarkSeconds,
                            )
                        }
                        incident = true
                        if (endTimeSeconds > previousWatermarkSeconds) {
                            newIncident = true
                        }
                    }
                }
            } finally {
                connection.disconnect()
            }
        }
        return FailedTaskReadResult(
            outcome = if (incident) "task_incident" else "healthy",
            complete = true,
            incident = incident,
            newIncident = newIncident,
            watermarkSeconds = watermarkSeconds,
        )
    }

    private fun readLimited(stream: InputStream): String {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8 * 1024)
        var total = 0
        while (true) {
            val count = stream.read(buffer)
            if (count < 0) break
            total += count
            require(total <= MAX_RESPONSE_BYTES)
            output.write(buffer, 0, count)
        }
        return output.toString(Charsets.UTF_8.name())
    }

    private fun showScheduledIncidentNotification(
        context: Context,
        profileKey: String,
        cooldownMinutes: Int,
        nowMs: Long,
    ): Boolean {
        return IncidentNotificationDeliveryLedger.deliver(
            context = context,
            profileKey = profileKey,
            cooldownMinutes = cooldownMinutes,
            nowMs = nowMs,
        ) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                    PackageManager.PERMISSION_GRANTED
            ) {
                return@deliver false
            }
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val visibility = IncidentNotificationPrivacy.visibility(context)
            val channel = NotificationChannel(
                INCIDENT_CHANNEL_ID,
                "Incident alerts",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "VirtHelm incident summaries"
                lockscreenVisibility = visibility
            }
            manager.createNotificationChannel(channel)

            val contentIntent = IncidentNotificationNavigation.contentIntent(context)
            val notification = Notification.Builder(context, INCIDENT_CHANNEL_ID)
                .setSmallIcon(R.drawable.virthelm_notification)
                .setContentTitle("VirtHelm scheduled incident")
                .setContentText("Open VirtHelm to review current incidents.")
                .setContentIntent(contentIntent)
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_STATUS)
                .setVisibility(visibility)
                .build()
            manager.notify(INCIDENT_NOTIFICATION_ID, notification)
            true
        }
    }

    private fun validateNodeCpuRules(
        rules: List<ScheduledNodeCpuRule>,
    ): List<ScheduledNodeCpuRule> {
        require(rules.size <= MAX_BACKGROUND_NODE_CPU_RULES)
        val ids = mutableSetOf<String>()
        for (rule in rules) {
            rule.validate()
            require(ids.add(rule.id))
        }
        return rules.toList()
    }

    private fun encodeSecret(secret: ScheduledSecret): String {
        val rules = JSONArray()
        for (rule in secret.nodeCpuThresholdRules) {
            rules.put(rule.toJson())
        }
        return JSONObject()
            .put("endpoint", secret.endpoint)
            .put("authorization", secret.authorization)
            .put("nodeCpuThresholdRules", rules)
            .toString()
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
            val rulesJson = decoded.optJSONArray("nodeCpuThresholdRules")
            val rules = mutableListOf<ScheduledNodeCpuRule>()
            if (rulesJson != null) {
                require(rulesJson.length() <= MAX_BACKGROUND_NODE_CPU_RULES)
                for (index in 0 until rulesJson.length()) {
                    rules.add(
                        ScheduledNodeCpuRule.fromJson(
                            rulesJson.getJSONObject(index),
                        ),
                    )
                }
            }
            ScheduledSecret(
                endpoint = decoded.getString("endpoint"),
                authorization = decoded.getString("authorization"),
                nodeCpuThresholdRules = validateNodeCpuRules(rules),
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
                            failedTaskChecksEnabled =
                                call.argument<Boolean>("failedTaskChecksEnabled") == true,
                            nodeCpuThresholdChecksEnabled =
                                call.argument<Boolean>(
                                    "nodeCpuThresholdChecksEnabled",
                                ) == true,
                        )
                        result.success(
                            BackgroundCheckCoordinator.configure(
                                context = context,
                                profileId = call.requireString("profileId"),
                                endpoint = call.requireString("endpoint"),
                                authorization = call.requireString("authorization"),
                                policy = policy,
                                nodeCpuThresholdRules =
                                    call.nodeCpuThresholdRules(),
                            ),
                        )
                    }
                    "syncNodeCpuThresholdRules" -> {
                        result.success(
                            BackgroundCheckCoordinator.syncNodeCpuThresholdRules(
                                context = context,
                                profileId = call.requireString("profileId"),
                                nodeCpuThresholdRules =
                                    call.nodeCpuThresholdRules(),
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

    private fun io.flutter.plugin.common.MethodCall.nodeCpuThresholdRules():
        List<ScheduledNodeCpuRule> {
        val raw = argument<List<*>>("nodeCpuThresholdRules") ?: emptyList<Any?>()
        require(raw.size <= MAX_BACKGROUND_NODE_CPU_RULES)
        return raw.map { ScheduledNodeCpuRule.fromChannel(it) }
    }
}
