import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../main.dart';
import '../../services/schedule_service.dart';
import '../../services/auth_service.dart';
import '../../services/offline_service.dart';
import '../../services/notification_service.dart';
import '../../models/schedule.dart';
import '../../widgets/bus_card.dart';
import '../../widgets/offline_banner.dart';
import 'search_screen.dart';
import 'tracking_screen.dart';
import '../login_screen.dart';

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  String _selectedTrip = 'incoming';
  bool _isOffline = false;
  String? _lastSyncTime;
  Schedule? _offlineSchedule;
  List<Map<String, dynamic>> _notifications = [];
  String? _notificationError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSchedule();
      _loadNotifications();
    });
  }

  Future<void> _refresh() async {
    await Future.wait([_loadSchedule(), _loadNotifications()]);
  }

  Future<void> _loadNotifications() async {
    try {
      final notifications = await NotificationService.getHistory();
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _notificationError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _notificationError = 'Transport alerts are unavailable.');
    }
  }

  Future<void> _loadSchedule() async {
    final service = context.read<ScheduleService>();
    await service.fetchPublishedSchedule(trip: _selectedTrip);

    if (!mounted) return;
    if (service.errorMessage == null && service.publishedSchedule != null) {
      await OfflineService.cacheSchedule(service.publishedSchedule!);
      if (!mounted) return;
      setState(() {
        _isOffline = false;
        _lastSyncTime = null;
        _offlineSchedule = null;
      });
      return;
    }

    final cached = await OfflineService.getCachedSchedule(trip: _selectedTrip);
    final lastSync = await OfflineService.getLastSyncTime(trip: _selectedTrip);
    if (!mounted) return;
    setState(() {
      _offlineSchedule = cached;
      _lastSyncTime = lastSync;
      _isOffline = cached != null;
    });
  }

  void _openSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SearchScreen()),
    );
  }

  void _openTracking() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TrackingScreen()),
    );
  }

  Future<void> _logout(AuthService auth) async {
    await auth.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ScheduleService>();
    final auth = context.watch<AuthService>();
    final schedule = _isOffline ? _offlineSchedule : service.publishedSchedule;
    final date = DateFormat('EEEE, d MMMM').format(DateTime.now());

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: KlnceBrandMark(
            size: 36,
            onTap: () => navigateToDashboard(context),
          ),
        ),
        leadingWidth: 60,
        title: const Text('KLNCE Transport'),
        actions: [
          IconButton(
            onPressed: _openSearch,
            tooltip: 'Search buses',
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            onPressed: _openTracking,
            tooltip: 'Live bus updates',
            icon: const Icon(Icons.location_on_outlined),
          ),
          if (auth.isLoggedIn)
            IconButton(
              onPressed: () => _logout(auth),
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout_rounded),
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bus schedules',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Find your route and plan your trip to campus.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(date, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'incoming',
                      icon: Icon(Icons.login_rounded),
                      label: Text('To campus'),
                    ),
                    ButtonSegment(
                      value: 'outgoing',
                      icon: Icon(Icons.logout_rounded),
                      label: Text('From campus'),
                    ),
                  ],
                  selected: {_selectedTrip},
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) return;
                    setState(() => _selectedTrip = selection.first);
                    _loadSchedule();
                  },
                ),
              ),
            ),
            if (_notifications.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  0,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final notification = _notifications[index];
                      final title = notification['title']?.toString() ??
                          'Transport alert';
                      final body = notification['body']?.toString() ?? '';
                      final sentAt = DateTime.tryParse(
                        notification['sent_at']?.toString() ?? '',
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF5F2),
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            border: Border.all(
                              color: AppColors.emerald.withOpacity(0.22),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.campaign_outlined,
                                color: AppColors.emeraldDark,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    if (sentAt != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        DateFormat('d MMM, h:mm a')
                                            .format(sentAt),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: AppColors.textSecondary,
                                            ),
                                      ),
                                    ],
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      body,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount:
                        _notifications.length > 3 ? 3 : _notifications.length,
                  ),
                ),
              )
            else if (_notificationError != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    0,
                  ),
                  child: Text(
                    _notificationError!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ),
              ),
            if (_isOffline)
              SliverToBoxAdapter(
                child: OfflineBanner(lastSyncTime: _lastSyncTime),
              ),
            if (schedule != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          '${schedule.busRoutes.length} routes',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Effective ${schedule.effectiveDate}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            if (service.isLoading && schedule == null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              )
            else if (schedule == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ScheduleUnavailable(
                  message: service.errorMessage,
                  onRetry: _loadSchedule,
                ),
              )
            else if (schedule.busRoutes.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ScheduleUnavailable(
                  message: 'No routes are included in this schedule yet.',
                  onRetry: _loadSchedule,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  0,
                  AppSpacing.xs,
                  0,
                  AppSpacing.lg,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => BusCard(
                      route: schedule.busRoutes[index],
                    ),
                    childCount: schedule.busRoutes.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleUnavailable extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;

  const _ScheduleUnavailable({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.directions_bus_outlined,
            size: 40,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Schedule unavailable',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message ?? 'There is no published schedule for this trip yet.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
