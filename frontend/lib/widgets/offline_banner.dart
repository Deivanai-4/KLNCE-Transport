import 'package:flutter/material.dart';
import '../main.dart';

class OfflineBanner extends StatelessWidget {
  final String? lastSyncTime;
  const OfflineBanner({super.key, this.lastSyncTime});

  @override
  Widget build(BuildContext context) {
    String syncText = '';
    if (lastSyncTime != null) {
      try {
        final dt = DateTime.parse(lastSyncTime!).toLocal();
        final h = dt.hour.toString().padLeft(2, '0');
        final m = dt.minute.toString().padLeft(2, '0');
        syncText = ' · synced $h:$m';
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.amber.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded,
              color: AppColors.amber, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline — showing cached timetable$syncText',
              style: const TextStyle(
                color: AppColors.amber,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Icon(Icons.cloud_off_rounded,
              color: AppColors.amber, size: 14),
        ],
      ),
    );
  }
}
