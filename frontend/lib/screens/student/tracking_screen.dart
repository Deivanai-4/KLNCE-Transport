import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../main.dart';
import '../../models/gps_location.dart';
import '../../services/gps_service.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GpsService>().fetchAllActiveBuses();
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<GpsService>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Bus locations'),
        actions: [
          IconButton(
            tooltip: 'Dashboard',
            onPressed: () => navigateToDashboard(context),
            icon: const KlnceBrandMark(size: 32),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: service.fetchAllActiveBuses,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text(
              'GPS updates',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Only locations received from the transport system are shown.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.map_outlined,
                    color: AppColors.navyMid,
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Map display is not configured in this build. The list below shows actual GPS updates when available.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Text(
                  'Active bus updates',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  onPressed:
                      service.isLoading ? null : service.fetchAllActiveBuses,
                  tooltip: 'Refresh GPS updates',
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            if (service.isLoading && service.allActiveBuses.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (service.errorMessage != null)
              _TrackingMessage(
                icon: Icons.location_searching_outlined,
                title: 'Locations unavailable',
                message: service.errorMessage!,
                action: OutlinedButton.icon(
                  onPressed: service.fetchAllActiveBuses,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              )
            else if (service.allActiveBuses.isEmpty)
              const _TrackingMessage(
                icon: Icons.location_off_outlined,
                title: 'No active GPS updates',
                message:
                    'No bus location has been reported recently. Check again later.',
              )
            else
              ...service.allActiveBuses.map(
                (location) => _GpsLocationTile(location: location),
              ),
          ],
        ),
      ),
    );
  }
}

class _GpsLocationTile extends StatelessWidget {
  final GpsLocation location;

  const _GpsLocationTile({required this.location});

  @override
  Widget build(BuildContext context) {
    final recordedAt = DateTime.tryParse(location.recordedAt)?.toLocal();
    final updateLabel = recordedAt == null
        ? 'Update time unavailable'
        : 'Last updated ${DateFormat('d MMM, h:mm a').format(recordedAt)}';

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const KlnceBrandMark(size: 42),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bus ${location.busCode}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(updateLabel, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const _TrackingMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppColors.textSecondary),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}
