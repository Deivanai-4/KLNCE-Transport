package com.klnce.transport

import android.content.Context
import androidx.work.*
import java.util.Calendar
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/**
 * SmsScheduleManager — schedules and cancels WorkManager jobs for
 * morning (06:30 IST) and afternoon (14:00 IST) automatic SMS dispatch.
 *
 * Uses OneTimeWorkRequests chained to run once per day at the target time.
 * On completion the Worker re-enqueues itself for the next day.
 */
object SmsScheduleManager {

    private const val TAG_MORNING = "klnce_sms_morning"
    private const val TAG_AFTERNOON = "klnce_sms_afternoon"

    private const val IST_TIMEZONE = "Asia/Kolkata"

    /**
     * Schedule (or reschedule) morning and afternoon jobs.
     * [morningTime] and [afternoonTime] are "HH:mm" strings in IST.
     */
    fun scheduleJobs(
        context: Context,
        morningTime: String = "06:30",
        afternoonTime: String = "14:00"
    ) {
        scheduleJob(context, morningTime, "morning", TAG_MORNING)
        scheduleJob(context, afternoonTime, "afternoon", TAG_AFTERNOON)
    }

    private fun scheduleJob(
        context: Context,
        timeHHmm: String,
        session: String,
        tag: String
    ) {
        val delayMs = computeDelayMs(timeHHmm)
        if (delayMs < 0) return

        val data = workDataOf(
            SmsScheduleWorker.KEY_SESSION to session,
            SmsScheduleWorker.KEY_TARGET_TIME to timeHHmm
        )

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val request = OneTimeWorkRequestBuilder<SmsScheduleWorker>()
            .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
            .setInputData(data)
            .setConstraints(constraints)
            .addTag(tag)
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            tag,
            ExistingWorkPolicy.REPLACE,
            request
        )
    }

    /**
     * Calculate milliseconds until the next occurrence of [timeHHmm] in IST.
     * If the time has already passed today, returns delay until tomorrow.
     */
    fun computeDelayMs(timeHHmm: String): Long {
        return try {
            val parts = timeHHmm.split(":")
            val targetHour = parts[0].toInt()
            val targetMinute = parts[1].toInt()

            val ist = TimeZone.getTimeZone(IST_TIMEZONE)
            val now = Calendar.getInstance(ist)
            val target = Calendar.getInstance(ist).apply {
                set(Calendar.HOUR_OF_DAY, targetHour)
                set(Calendar.MINUTE, targetMinute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            if (target.timeInMillis <= now.timeInMillis) {
                // Already passed today — schedule for tomorrow
                target.add(Calendar.DAY_OF_YEAR, 1)
            }

            target.timeInMillis - now.timeInMillis
        } catch (e: Exception) {
            -1L
        }
    }

    /** Cancel all scheduled auto-SMS jobs. */
    fun cancelJobs(context: Context) {
        val wm = WorkManager.getInstance(context)
        wm.cancelAllWorkByTag(TAG_MORNING)
        wm.cancelAllWorkByTag(TAG_AFTERNOON)
    }

    /**
     * Re-schedule jobs on device boot (called from SmsBootReceiver).
     * Reads saved times from SharedPreferences if available.
     */
    fun rescheduleOnBoot(context: Context) {
        val prefs = context.getSharedPreferences("klnce_auto_sms", Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean("auto_sms_enabled", false)
        if (!enabled) return
        val morningTime = prefs.getString("morning_time", "06:30") ?: "06:30"
        val afternoonTime = prefs.getString("afternoon_time", "14:00") ?: "14:00"
        scheduleJobs(context, morningTime, afternoonTime)
    }

    /** Persist settings locally so they survive device restarts. */
    fun savePreferences(
        context: Context,
        enabled: Boolean,
        morningTime: String,
        afternoonTime: String
    ) {
        context.getSharedPreferences("klnce_auto_sms", Context.MODE_PRIVATE).edit().apply {
            putBoolean("auto_sms_enabled", enabled)
            putString("morning_time", morningTime)
            putString("afternoon_time", afternoonTime)
            apply()
        }
    }
}
