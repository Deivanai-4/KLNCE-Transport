import 'package:flutter/material.dart';
import '../../main.dart';
import '../../models/bus_route.dart';

class BusDetailScreen extends StatelessWidget {
  final BusRoute route;

  const BusDetailScreen({super.key, required this.route});

  @override
  Widget build(BuildContext context) {
    final collegeLabel = switch (route.college) {
      'arts_science' => 'Arts & Science',
      'both' => 'Both campuses',
      _ => 'Engineering',
    };

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text('Bus ${route.busCode}')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            route.routeDisplayName?.isNotEmpty == true
                ? route.routeDisplayName!
                : 'Route details',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(collegeLabel, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _RouteStat(
                    label: 'Departure',
                    value: route.departureTime,
                    icon: Icons.schedule_outlined,
                  ),
                ),
                Container(
                  width: 1,
                  height: 44,
                  color: const Color(0xFFE2E8F0),
                ),
                Expanded(
                  child: _RouteStat(
                    label: 'Stops',
                    value: '${route.stops.length}',
                    icon: Icons.route_outlined,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Route stops', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.md),
          if (route.stops.isEmpty)
            const _StopsUnavailable()
          else
            ...route.stops.asMap().entries.map(
                  (entry) => _StopTimelineItem(
                    stop: entry.value,
                    index: entry.key,
                    count: route.stops.length,
                    departureTime: route.departureTime,
                  ),
                ),
        ],
      ),
    );
  }
}

class _RouteStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _RouteStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 19, color: AppColors.emeraldDark),
        const SizedBox(height: AppSpacing.xs),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _StopTimelineItem extends StatelessWidget {
  final dynamic stop;
  final int index;
  final int count;
  final String departureTime;

  const _StopTimelineItem({
    required this.stop,
    required this.index,
    required this.count,
    required this.departureTime,
  });

  @override
  Widget build(BuildContext context) {
    final isFirst = index == 0;
    final isLast = index == count - 1;
    final time = stop.arrivalTime ?? (isFirst ? departureTime : null);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    color: isFirst || isLast
                        ? AppColors.emerald
                        : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.emerald,
                      width: 2,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: const Color(0xFFD8E1E8),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stop.stopNameEn,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (stop.stopNameTa?.isNotEmpty == true &&
                            stop.stopNameTa != stop.stopNameEn) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            stop.stopNameTa!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (time != null)
                    Text(
                      time,
                      style: const TextStyle(
                        color: AppColors.emeraldDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StopsUnavailable extends StatelessWidget {
  const _StopsUnavailable();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        'Stop details are not available for this route.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
