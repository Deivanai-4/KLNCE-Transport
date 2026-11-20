package com.klnce.transport

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val SMS_CHANNEL = "com.klnce.transport/sms"
        private const val SMS_PERMISSION_REQUEST_CODE = 8001
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkSmsCapability" -> {
                    checkSmsCapability(result)
                }
                "requestSmsPermissions" -> {
                    requestSmsPermissions(result)
                }
                "sendSmsDirect" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    val message = call.argument<String>("message")
                    val subscriptionId = call.argument<Int>("subscriptionId")
                    if (phoneNumber.isNullOrBlank() || message.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "Phone number and message are required", null)
                        return@setMethodCallHandler
                    }
                    sendSmsDirect(phoneNumber, message, subscriptionId, result)
                }
                "sendSmsViaIntent" -> {
                    val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    sendSmsViaIntent(phoneNumber, message, result)
                }
                // ── Stage 8: WorkManager auto-schedule bridge ──────────────
                "scheduleAutoSmsJobs" -> {
                    val morningTime = call.argument<String>("morningTime") ?: "06:30"
                    val afternoonTime = call.argument<String>("afternoonTime") ?: "14:00"
                    scheduleAutoSmsJobs(morningTime, afternoonTime, result)
                }
                "cancelAutoSmsJobs" -> {
                    cancelAutoSmsJobs(result)
                }
                "getAutoSmsScheduleStatus" -> {
                    getAutoSmsScheduleStatus(result)
                }
                "saveAutoSmsPrefs" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val morningTime = call.argument<String>("morningTime") ?: "06:30"
                    val afternoonTime = call.argument<String>("afternoonTime") ?: "14:00"
                    SmsScheduleManager.savePreferences(context, enabled, morningTime, afternoonTime)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    /**
     * Check device telephony hardware, SIM state, permission status, and list active SIM subscriptions.
     */
    private fun checkSmsCapability(result: MethodChannel.Result) {
        try {
            val packageManager = context.packageManager
            val hasTelephony = packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)

            val telephonyManager = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            val simStateInt = telephonyManager?.simState ?: TelephonyManager.SIM_STATE_UNKNOWN
            val simStateStr = when (simStateInt) {
                TelephonyManager.SIM_STATE_READY -> "READY"
                TelephonyManager.SIM_STATE_ABSENT -> "ABSENT"
                TelephonyManager.SIM_STATE_NETWORK_LOCKED -> "NETWORK_LOCKED"
                TelephonyManager.SIM_STATE_PIN_REQUIRED -> "PIN_REQUIRED"
                TelephonyManager.SIM_STATE_PUK_REQUIRED -> "PUK_REQUIRED"
                else -> "UNKNOWN"
            }

            val sendSmsGranted = ContextCompat.checkSelfPermission(
                context, Manifest.permission.SEND_SMS
            ) == PackageManager.PERMISSION_GRANTED

            val readPhoneStateGranted = ContextCompat.checkSelfPermission(
                context, Manifest.permission.READ_PHONE_STATE
            ) == PackageManager.PERMISSION_GRANTED

            val simCards = mutableListOf<Map<String, Any>>()
            var defaultSubId = -1

            // Retrieve SIM details if READ_PHONE_STATE is available
            if (readPhoneStateGranted && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                try {
                    val subManager = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
                    val activeSubs = subManager?.activeSubscriptionInfoList
                    if (activeSubs != null) {
                        for (info: SubscriptionInfo in activeSubs) {
                            val simMap = mapOf(
                                "subscriptionId" to info.subscriptionId,
                                "simSlotIndex" to info.simSlotIndex,
                                "carrierName" to (info.carrierName?.toString() ?: "Unknown"),
                                "displayName" to (info.displayName?.toString() ?: "SIM ${info.simSlotIndex + 1}"),
                                "countryIso" to (info.countryIso ?: "")
                            )
                            simCards.add(simMap)
                        }
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        defaultSubId = SubscriptionManager.getDefaultSmsSubscriptionId()
                    }
                } catch (e: SecurityException) {
                    // Handled safely without crash
                }
            }

            // Fallback carrier name if no SIM card info was obtained
            if (simCards.isEmpty() && simStateInt == TelephonyManager.SIM_STATE_READY) {
                val carrier = telephonyManager?.networkOperatorName ?: "Active SIM"
                simCards.add(
                    mapOf(
                        "subscriptionId" to -1,
                        "simSlotIndex" to 0,
                        "carrierName" to (if (carrier.isNotBlank()) carrier else "Mobile Carrier"),
                        "displayName" to "Default SIM",
                        "countryIso" to (telephonyManager?.networkCountryIso ?: "")
                    )
                )
            }

            val isReady = hasTelephony && (simStateInt == TelephonyManager.SIM_STATE_READY) && sendSmsGranted

            result.success(
                mapOf(
                    "hasTelephony" to hasTelephony,
                    "simState" to simStateStr,
                    "isSimReady" to (simStateInt == TelephonyManager.SIM_STATE_READY),
                    "sendSmsGranted" to sendSmsGranted,
                    "readPhoneStateGranted" to readPhoneStateGranted,
                    "isReady" to isReady,
                    "simCards" to simCards,
                    "defaultSubId" to defaultSubId,
                    "deviceModel" to "${Build.MANUFACTURER} ${Build.MODEL}",
                    "androidVersion" to Build.VERSION.RELEASE,
                    "sdkInt" to Build.VERSION.SDK_INT
                )
            )
        } catch (e: Exception) {
            result.error("SMS_CHECK_FAILED", e.localizedMessage, null)
        }
    }

    /**
     * Request SMS sending and phone state permissions from the administrator.
     */
    private fun requestSmsPermissions(result: MethodChannel.Result) {
        val sendSmsGranted = ContextCompat.checkSelfPermission(
            context, Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED
        val readPhoneStateGranted = ContextCompat.checkSelfPermission(
            context, Manifest.permission.READ_PHONE_STATE
        ) == PackageManager.PERMISSION_GRANTED

        if (sendSmsGranted && readPhoneStateGranted) {
            result.success(true)
            return
        }

        pendingPermissionResult = result
        val permissionsToRequest = mutableListOf<String>()
        if (!sendSmsGranted) permissionsToRequest.add(Manifest.permission.SEND_SMS)
        if (!readPhoneStateGranted) permissionsToRequest.add(Manifest.permission.READ_PHONE_STATE)

        ActivityCompat.requestPermissions(
            this,
            permissionsToRequest.toTypedArray(),
            SMS_PERMISSION_REQUEST_CODE
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_PERMISSION_REQUEST_CODE) {
            val allGranted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(allGranted)
            pendingPermissionResult = null
        }
    }

    /**
     * Send SMS directly from the administrator device SIM using Android SmsManager.
     * Captures and returns Android SMS service status (RESULT_OK, NO_SERVICE, etc.)
     * and sets up SMSC delivery reporting.
     */
    private fun sendSmsDirect(
        phoneNumber: String,
        message: String,
        subscriptionId: Int?,
        result: MethodChannel.Result
    ) {
        val sendSmsGranted = ContextCompat.checkSelfPermission(
            context, Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED

        if (!sendSmsGranted) {
            result.error("PERMISSION_DENIED", "SEND_SMS permission not granted by user", null)
            return
        }

        try {
            // Resolve SmsManager for the specified subscription ID (dual SIM support)
            val smsManager: SmsManager = if (subscriptionId != null && subscriptionId >= 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    context.getSystemService(SmsManager::class.java).createForSubscriptionId(subscriptionId)
                } else {
                    @Suppress("DEPRECATION")
                    SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
                }
            } else {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    context.getSystemService(SmsManager::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    SmsManager.getDefault()
                }
            }

            val uniqueSentAction = "com.klnce.transport.SMS_SENT_${System.currentTimeMillis()}_${(0..99999).random()}"
            val uniqueDeliveredAction = "com.klnce.transport.SMS_DELIVERED_${System.currentTimeMillis()}_${(0..99999).random()}"

            val intentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_ONE_SHOT
            }

            val sentIntent = PendingIntent.getBroadcast(
                context,
                0,
                Intent(uniqueSentAction),
                intentFlags
            )

            val deliveryIntent = PendingIntent.getBroadcast(
                context,
                0,
                Intent(uniqueDeliveredAction),
                intentFlags
            )

            // Register broadcast receiver to capture dispatch result from Android Telephony SMS stack
            val sentReceiver = object : BroadcastReceiver() {
                override fun onReceive(c: Context?, intent: Intent?) {
                    try {
                        context.unregisterReceiver(this)
                    } catch (_: Exception) {}

                    when (resultCode) {
                        Activity.RESULT_OK -> {
                            result.success(
                                mapOf(
                                    "success" to true,
                                    "status" to "submitted_to_sms_service",
                                    "message" to "Submitted to Android SMS service"
                                )
                            )
                        }
                        SmsManager.RESULT_ERROR_NO_SERVICE -> {
                            result.success(
                                mapOf(
                                    "success" to false,
                                    "status" to "failed",
                                    "error" to "NO_SERVICE (No cellular signal available)"
                                )
                            )
                        }
                        SmsManager.RESULT_ERROR_RADIO_OFF -> {
                            result.success(
                                mapOf(
                                    "success" to false,
                                    "status" to "failed",
                                    "error" to "RADIO_OFF (Cellular radio is off / Airplane mode active)"
                                )
                            )
                        }
                        SmsManager.RESULT_ERROR_NULL_PDU -> {
                            result.success(
                                mapOf(
                                    "success" to false,
                                    "status" to "failed",
                                    "error" to "NULL_PDU (SMS PDU creation failed)"
                                )
                            )
                        }
                        SmsManager.RESULT_ERROR_GENERIC_FAILURE -> {
                            result.success(
                                mapOf(
                                    "success" to false,
                                    "status" to "failed",
                                    "error" to "GENERIC_FAILURE (Insufficient balance, carrier limit, or invalid number)"
                                )
                            )
                        }
                        else -> {
                            result.success(
                                mapOf(
                                    "success" to false,
                                    "status" to "failed",
                                    "error" to "FAILED_CODE_$resultCode"
                                )
                            )
                        }
                    }
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(sentReceiver, IntentFilter(uniqueSentAction), Context.RECEIVER_NOT_EXPORTED)
            } else {
                context.registerReceiver(sentReceiver, IntentFilter(uniqueSentAction))
            }

            // Divide message if length exceeds standard SMS 160 characters
            val parts = smsManager.divideMessage(message)
            if (parts.size > 1) {
                val sentIntents = ArrayList<PendingIntent>()
                val deliveryIntents = ArrayList<PendingIntent>()
                for (i in parts.indices) {
                    sentIntents.add(sentIntent)
                    deliveryIntents.add(deliveryIntent)
                }
                smsManager.sendMultipartTextMessage(phoneNumber, null, parts, sentIntents, deliveryIntents)
            } else {
                smsManager.sendTextMessage(phoneNumber, null, message, sentIntent, deliveryIntent)
            }

        } catch (e: Exception) {
            result.success(
                mapOf(
                    "success" to false,
                    "status" to "failed",
                    "error" to (e.localizedMessage ?: "Exception sending SMS")
                )
            )
        }
    }

    /**
     * Fallback intent mechanism: launches system default SMS application.
     * 100% compliant with Google Play Store policies.
     */
    private fun sendSmsViaIntent(phoneNumber: String, message: String, result: MethodChannel.Result) {
        try {
            val uri = Uri.parse("smsto:$phoneNumber")
            val intent = Intent(Intent.ACTION_SENDTO, uri).apply {
                putExtra("sms_body", message)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (intent.resolveActivity(context.packageManager) != null) {
                context.startActivity(intent)
                result.success(true)
            } else {
                result.error("NO_SMS_APP", "No default SMS app installed on this device", null)
            }
        } catch (e: Exception) {
            result.error("INTENT_FAILED", e.localizedMessage, null)
        }
    }

    // ── Stage 8: WorkManager helpers ─────────────────────────────────────────

    private fun scheduleAutoSmsJobs(
        morningTime: String,
        afternoonTime: String,
        result: MethodChannel.Result
    ) {
        try {
            SmsScheduleManager.scheduleJobs(context, morningTime, afternoonTime)
            SmsScheduleManager.savePreferences(context, true, morningTime, afternoonTime)
            result.success(
                mapOf(
                    "success" to true,
                    "morningTime" to morningTime,
                    "afternoonTime" to afternoonTime,
                    "message" to "WorkManager jobs scheduled for $morningTime AM and $afternoonTime PM IST"
                )
            )
        } catch (e: Exception) {
            result.error("SCHEDULE_FAILED", e.localizedMessage, null)
        }
    }

    private fun cancelAutoSmsJobs(result: MethodChannel.Result) {
        try {
            SmsScheduleManager.cancelJobs(context)
            SmsScheduleManager.savePreferences(context, false, "06:30", "14:00")
            result.success(mapOf("success" to true, "message" to "WorkManager jobs cancelled"))
        } catch (e: Exception) {
            result.error("CANCEL_FAILED", e.localizedMessage, null)
        }
    }

    private fun getAutoSmsScheduleStatus(result: MethodChannel.Result) {
        try {
            val prefs = context.getSharedPreferences("klnce_auto_sms", Context.MODE_PRIVATE)
            val enabled = prefs.getBoolean("auto_sms_enabled", false)
            val morningTime = prefs.getString("morning_time", "06:30") ?: "06:30"
            val afternoonTime = prefs.getString("afternoon_time", "14:00") ?: "14:00"
            val morningDelayMs = SmsScheduleManager.computeDelayMs(morningTime)
            val afternoonDelayMs = SmsScheduleManager.computeDelayMs(afternoonTime)
            result.success(
                mapOf(
                    "enabled" to enabled,
                    "morningTime" to morningTime,
                    "afternoonTime" to afternoonTime,
                    "morningDelayMs" to morningDelayMs,
                    "afternoonDelayMs" to afternoonDelayMs
                )
            )
        } catch (e: Exception) {
            result.error("STATUS_FAILED", e.localizedMessage, null)
        }
    }
}
