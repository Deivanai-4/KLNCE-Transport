import 'package:flutter/material.dart';
import '../main.dart';
import '../models/bus_route.dart';
import '../screens/student/bus_detail_screen.dart';

class BusCard extends StatelessWidget {
  final BusRoute route;
  final String? highlightStop;

  const BusCard({super.key, required this.route, this.highlightStop});

  @override
  Widget build(BuildContext context) {
    final collegeLabel = switch (route.college) {
      'arts_science' => 'Arts & Science',
      'both' => 'Both campuses',
      _ => 'Engineering',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BusDetailScreen(route: route),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      child: Text(
                        'Bus ${route.busCode}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        collegeLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      Icons.schedule_outlined,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      route.departureTime,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                if (route.routeDisplayName?.isNotEmpty == true) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    route.routeDisplayName!,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (route.stops.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      ...route.stops.take(4).map((stop) {
                        final isHighlighted = highlightStop != null &&
                            stop.stopNameEn.toLowerCase().contains(
                                  highlightStop!.toLowerCase(),
                                );
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: isHighlighted
                                ? AppColors.engBg
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
                          child: Text(
                            stop.stopNameEn,
                            style: TextStyle(
                              color: isHighlighted
                                  ? AppColors.emeraldDark
                                  : AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: isHighlighted
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        );
                      }),
                      if (route.stops.length > 4)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: 5,
                          ),
                          child: Text(
                            '+${route.stops.length - 4} more',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Icon(
                      Icons.route_outlined,
                      size: 16,
                      color: AppColors.textSecondary.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '${route.stops.length} stops',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    const Text(
                      'View route',
                      style: TextStyle(
                        color: AppColors.emeraldDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: AppColors.emeraldDark,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
