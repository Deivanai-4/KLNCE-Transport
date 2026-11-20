package com.klnce.transport

import android.content.Context
import android.telephony.SmsManager
import android.os.Build
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * SmsScheduleWorker — Android WorkManager Worker that runs at 06:30 AM / 2:00 PM IST.
 *
 * Actions:
 * 1. Read JWT token + backend base URL from SharedPreferences.
 * 2. GET /api/sms/auto-schedule/settings — confirm auto SMS is still enabled.
 * 3. POST /api/sms/auto-schedule/prepare — create/retrieve the campaign.
 * 4. Based on confirmation_policy:
 *    - 'confirmation': post a local Android notification for admin to approve.
 *    - 'automatic': dispatch SMS immediately via SmsManager.
 * 5. Re-enqueue itself for the next day.
 */
class SmsScheduleWorker(context: Context, params: WorkerParameters) :
    Worker(context, params) {

    companion object {
        const val KEY_SESSION = "session"
        const val KEY_TARGET_TIME = "target_time"
        private const val PREFS_NAME = "klnce_auto_sms"
        private const val PREFS_JWT = "klnce_jwt"
        private const val PREFS_BASE_URL = "klnce_base_url"
    }

    override fun doWork(): Result {
        val session = inputData.getString(KEY_SESSION) ?: return Result.failure()
        val targetTime = inputData.getString(KEY_TARGET_TIME) ?: "06:30"

        return try {
            val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val autoEnabled = prefs.getBoolean("auto_sms_enabled", false)
            if (!autoEnabled) {
                // Auto SMS was disabled — don't re-enqueue
                return Result.success()
            }

            val appPrefs = applicationContext.getSharedPreferences(PREFS_JWT, Context.MODE_PRIVATE)
            val jwt = appPrefs.getString("token", null)
            val baseUrl = appPrefs.getString("base_url", null)
                ?: prefs.getString(PREFS_BASE_URL, null)

            if (jwt.isNullOrBlank() || baseUrl.isNullOrBlank()) {
                // No credentials — cannot call backend; retry later
                reEnqueue(session, targetTime)
                return Result.retry()
            }

            // ── 1. Verify settings are still enabled ─────────────────────
            val settingsJson = httpGet("$baseUrl/api/sms/auto-schedule/settings", jwt)
                ?: run { reEnqueue(session, targetTime); return Result.retry() }

            val settings = settingsJson.optJSONObject("settings") ?: settingsJson
            if (!settings.optBoolean("is_enabled", false) ||
                settings.optBoolean("emergency_disabled", false)) {
                reEnqueue(session, targetTime)
                return Result.success()
            }

            val policy = settings.optString("confirmation_policy", "confirmation")

            // ── 2. Prepare campaign ───────────────────────────────────────
            val prepPayload = JSONObject().apply { put("session", session) }
            val prepJson = httpPost(
                "$baseUrl/api/sms/auto-schedule/prepare",
                jwt,
                prepPayload.toString()
            ) ?: run { reEnqueue(session, targetTime); return Result.retry() }

            val campaignId = prepJson.optString("campaign_id", "")
            val recipientCount = prepJson.optInt("recipient_count", 0)
            val campaignStatus = prepJson.optString("status", "")

            // ── 3. Act based on confirmation policy ───────────────────────
            if (policy == "automatic" && campaignStatus != "pending_confirmation") {
                // Retrieve recipients and send directly
                val recipientsJson = httpGet(
                    "$baseUrl/api/sms/campaigns/$campaignId/recipients",
                    jwt
                )
                if (recipientsJson != null) {
                    dispatchSmsDirect(recipientsJson, prefs.getInt("subscription_id", -1))
                }
            } else {
                // Post local notification for admin approval
                postLocalNotification(session, campaignId, recipientCount)
            }

            // ── 4. Re-enqueue for next day ────────────────────────────────
            reEnqueue(session, targetTime)
            Result.success()

        } catch (e: Exception) {
            reEnqueue(session, targetTime)
            Result.retry()
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private fun httpGet(urlStr: String, jwt: String): JSONObject? {
        return try {
            val conn = URL(urlStr).openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.setRequestProperty("Authorization", "Bearer $jwt")
            conn.setRequestProperty("Content-Type", "application/json")
            conn.connectTimeout = 15000
            conn.readTimeout = 15000
            if (conn.responseCode == 200) {
                val reader = BufferedReader(InputStreamReader(conn.inputStream))
                JSONObject(reader.readText())
            } else null
        } catch (e: Exception) { null }
    }

    private fun httpPost(urlStr: String, jwt: String, body: String): JSONObject? {
        return try {
            val conn = URL(urlStr).openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Authorization", "Bearer $jwt")
            conn.setRequestProperty("Content-Type", "application/json")
            conn.doOutput = true
            conn.connectTimeout = 15000
            conn.readTimeout = 15000
            OutputStreamWriter(conn.outputStream).use { it.write(body) }
            if (conn.responseCode in 200..201) {
                val reader = BufferedReader(InputStreamReader(conn.inputStream))
                JSONObject(reader.readText())
            } else null
        } catch (e: Exception) { null }
    }

    private fun dispatchSmsDirect(recipientsJson: JSONObject, subscriptionId: Int) {
        val smsManager: SmsManager = if (subscriptionId >= 0 &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1
        ) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                applicationContext.getSystemService(SmsManager::class.java)
                    .createForSubscriptionId(subscriptionId)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
            }
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                applicationContext.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
        }

        val recipients = recipientsJson.optJSONArray("recipients") ?: return
        for (i in 0 until recipients.length()) {
            val r = recipients.getJSONObject(i)
            val phone = r.optString("mobile", "")
            val message = r.optString("message", "")
            if (phone.isBlank() || message.isBlank()) continue
            try {
                val parts = smsManager.divideMessage(message)
                if (parts.size > 1) {
                    smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
                } else {
                    smsManager.sendTextMessage(phone, null, message, null, null)
                }
                Thread.sleep(300) // throttle: ~3 SMS/sec
            } catch (_: Exception) {}
        }
    }

    private fun postLocalNotification(session: String, campaignId: String, count: Int) {
        try {
            val sessionLabel = if (session == "morning") "Morning" else "Afternoon"
            val nm = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE)
                as android.app.NotificationManager
            val channelId = "klnce_auto_sms"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val ch = android.app.NotificationChannel(
                    channelId,
                    "Auto SMS Confirmations",
                    android.app.NotificationManager.IMPORTANCE_HIGH
                )
                nm.createNotificationChannel(ch)
            }
            val notification = androidx.core.app.NotificationCompat.Builder(
                applicationContext, channelId
            )
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("KLNCE $sessionLabel SMS Ready")
                .setContentText("$count recipients — open app to Confirm & Send")
                .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build()
            nm.notify(campaignId.hashCode(), notification)
        } catch (_: Exception) {}
    }

    private fun reEnqueue(session: String, targetTime: String) {
        val delayMs = SmsScheduleManager.computeDelayMs(targetTime)
        if (delayMs <= 0) return
        val tag = if (session == "morning") "klnce_sms_morning" else "klnce_sms_afternoon"
        val data = workDataOf(KEY_SESSION to session, KEY_TARGET_TIME to targetTime)
        val constraints = androidx.work.Constraints.Builder()
            .setRequiredNetworkType(androidx.work.NetworkType.CONNECTED)
            .build()
        val request = androidx.work.OneTimeWorkRequestBuilder<SmsScheduleWorker>()
            .setInitialDelay(delayMs, java.util.concurrent.TimeUnit.MILLISECONDS)
            .setInputData(data)
            .setConstraints(constraints)
            .addTag(tag)
            .build()
        androidx.work.WorkManager.getInstance(applicationContext).enqueueUniqueWork(
            tag,
            androidx.work.ExistingWorkPolicy.REPLACE,
            request
        )
    }
}
