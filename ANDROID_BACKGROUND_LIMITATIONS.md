# KLNCE Transport — Android Background SMS Scheduling & Limitations

## Overview
Stage 8 implements automatic morning (06:30 AM IST) and afternoon (02:00 PM IST) bus schedule SMS broadcasts sent directly from the transport administrator's Android device SIM card using Android `WorkManager` (`androidx.work:work-runtime-ktx`).

The Render Flask backend **never** sends SMS directly; it only stores settings, validates schedules, prevents duplicates, and prepares recipient lists. The Android phone SIM executes all dispatches.

---

## 1. Operating System & Hardware Boundaries

### A. Android WorkManager Timing (Non-Exact by Design)
- **Doze Mode & App Standby**: Starting in Android 6.0 (API 23), Android puts the device into Doze mode during periods of inactivity. Background jobs scheduled with WorkManager may be deferred until the next maintenance window (typically 5–15 minutes later).
- **Exact Timing**: Android does not guarantee execution to the exact second. Morning (06:30 AM) and Afternoon (02:00 PM) jobs will trigger within a standard WorkManager window (±10–15 minutes) when the device enters a maintenance window.
- **Network Constraint**: The background job requires `NetworkType.CONNECTED` to communicate with the Render Flask API to fetch the latest published schedule and recipient list. If the device has no cellular data or Wi-Fi, the task is automatically deferred until connectivity is restored.

### B. Device Reboot & Boot Receiver
- The app registers `SmsBootReceiver` with `android.permission.RECEIVE_BOOT_COMPLETED` and `android.intent.action.QUICKBOOT_POWERON`.
- When the phone restarts, `SmsScheduleManager.rescheduleOnBoot()` automatically queries saved preferences and reenqueues WorkManager jobs.
- If the device is powered off at the scheduled trigger time (e.g., 06:30 AM), the job will fire as soon as the device boots and reconnects to the network.

### C. Force Stop Behavior
- If the administrator **Force Stops** the app from Android Settings (`Settings → Apps → KLNCE Transport → Force Stop`), Android cancels all pending WorkManager alarms and disables BroadcastReceivers.
- The administrator must open the KLNCE Transport application at least once after a Force Stop to reactivate background scheduling.

---

## 2. OEM Battery Optimization Whitelisting (Crucial Setup)

Many Android device manufacturers (Xiaomi/MIUI, Samsung/One UI, OnePlus/OxygenOS, Huawei, Oppo, Vivo) enforce aggressive proprietary battery managers that terminate background workers.

To ensure uninterrupted daily SMS scheduling:

### General Android Setup (Android 10+)
1. Go to **Settings → Apps → KLNCE Transport**.
2. Tap **Battery** (or **App Battery Usage**).
3. Select **Unrestricted** (allow app to use battery in background without restrictions).

### Manufacturer-Specific Instructions

#### Xiaomi / Redmi / POCO (MIUI / HyperOS)
1. **Autostart**: Settings → Apps → Permissions → Autostart → Enable **KLNCE Transport**.
2. **Battery Saver**: Settings → Battery → App Battery Saver → KLNCE Transport → Select **No Restrictions**.
3. **App Pinning**: In the Recent Apps screen, long-press KLNCE Transport and tap the **Lock** icon.

#### Samsung (One UI)
1. Settings → Battery and Device Care → Battery → Background Usage Limits.
2. Ensure KLNCE Transport is **not** in *Sleeping Apps* or *Deep Sleeping Apps*.
3. Add KLNCE Transport to **Never Sleeping Apps**.

#### OnePlus / Oppo / Realme (OxygenOS / ColorOS)
1. Settings → Apps → App Management → KLNCE Transport → Battery Usage.
2. Enable **Allow background activity** and **Allow auto-launch**.

#### Vivo / iQOO (Funtouch OS)
1. Settings → Battery → High background power consumption → Enable **KLNCE Transport**.

---

## 3. Confirmation Mode vs. Automatic Mode

| Mode | Behavior | Safety |
|---|---|---|
| **Confirmation Mode (Default / Recommended)** | At 06:30 AM / 02:00 PM, app prepares the campaign, validates today's published schedule, and posts a high-priority Android notification to the admin. Admin reviews recipients in the app and taps **Approve & Send**. | High — zero chance of accidental broadcasts with incomplete schedules. |
| **Automatic Mode** | At 06:30 AM / 02:00 PM, app prepares the campaign and immediately begins sequential SMS dispatch via `SmsManager` without prompting. | Requires explicit admin activation with confirmation warning dialog. |

---

## 4. Emergency Kill Switch
If a schedule is published incorrectly or urgent cancellation is needed:
1. Tap **Emergency Stop** on the Admin Dashboard Automatic SMS card, OR
2. Open **Auto SMS Settings** and tap **Emergency Disable All Automatic SMS**, OR
3. Backend API: `POST /api/sms/auto-schedule/emergency-disable`.
This immediately revokes automatic dispatch, cancels all scheduled WorkManager tasks, and locks out auto-preparation until explicitly re-enabled.

---

## 5. Duplicate Campaign Prevention
- Each auto-campaign receives an idempotent key: `AUTO_{date}_{session}_v{schedule_version}`.
- If WorkManager runs multiple times for the same time window, the backend verifies `find_by_auto_campaign_key()` and returns the existing campaign rather than duplicating SMS dispatches.
