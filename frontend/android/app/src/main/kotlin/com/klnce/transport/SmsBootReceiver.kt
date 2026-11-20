package com.klnce.transport

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * SmsBootReceiver — listens for BOOT_COMPLETED and re-schedules
 * automatic SMS WorkManager jobs when the device restarts.
 *
 * Requires RECEIVE_BOOT_COMPLETED permission in AndroidManifest.xml.
 */
class SmsBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON"
        ) {
            SmsScheduleManager.rescheduleOnBoot(context)
        }
    }
}
