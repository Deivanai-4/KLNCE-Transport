import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../main.dart';
import '../../services/schedule_service.dart';
import '../../services/auth_service.dart';
import '../../services/offline_service.dart';
import '../../services/notification_service.dart';
import '../../services/api_service.dart';
import '../../models/schedule.dart';
import '../../widgets/bus_card.dart';
import '../../widgets/offline_banner.dart';
import 'search_screen.dart';
import 'tracking_screen.dart';
import 'daily_schedule_screen.dart';
import 'announcements_screen.dart';
import '../../services/announcement_service.dart';
import '../login_screen.dart';

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen>
    with WidgetsBindingObserver {
  String _selectedTrip = 'incoming';
  Timer? _scheduleTransitionTimer;
  bool _isOffline = false;
  bool _awaitingScheduleRefresh = false;
  String? _lastSyncTime;
  Schedule? _offlineSchedule;
  List<Map<String, dynamic>> _notifications = [];
  String? _notificationError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSchedule();
      _loadNotifications();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scheduleTransitionTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSchedule();
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_loadSchedule(), _loadNotifications()]);
  }

  Future<void> _loadNotifications() async {
    try {
      Provider.of<AnnouncementService>(context, listen: false).fetchStudentAnnouncements();
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

  Future<void> _loadSchedule({String? trip}) async {
    final service = context.read<ScheduleService>();
    await service.fetchPublishedSchedule(trip: trip);

    if (!mounted) return;
    if (service.lastPublishedFetchSucceeded) {
      final activeTrip = service.activeTrip;
      if (trip == null && activeTrip != null) {
        _selectedTrip = activeTrip;
      }
      final published = service.publishedSchedule;
      if (published != null) {
        await OfflineService.cacheSchedule(published);
        if (!mounted) return;
      }
      setState(() {
        _isOffline = false;
        _awaitingScheduleRefresh = false;
        _lastSyncTime = null;
        _offlineSchedule = null;
      });
      _scheduleNextTransition(service.nextTransitionIst, service.serverTimeIst);
      return;
    }

    final activeTrip = trip ?? Schedule.activeTripAtIst(DateTime.now().toUtc());
    if (trip == null && activeTrip != null) {
      _selectedTrip = activeTrip;
    }
    final cached = activeTrip == null
        ? null
        : await OfflineService.getCachedSchedule(trip: activeTrip);
    final visibleCached =
        cached != null && cached.isVisibleAtIst(DateTime.now().toUtc())
            ? cached
            : null;
    final lastSync = activeTrip == null
        ? null
        : await OfflineService.getLastSyncTime(trip: activeTrip);
    if (!mounted) return;
    setState(() {
      _awaitingScheduleRefresh = false;
      _offlineSchedule = visibleCached;
      _lastSyncTime = visibleCached == null ? null : lastSync;
      _isOffline = visibleCached != null;
    });
    _scheduleNextTransition(null, null);
  }

  void _scheduleNextTransition(
      DateTime? serverTransition, DateTime? serverTime) {
    _scheduleTransitionTimer?.cancel();
    final now = DateTime.now().toUtc();
    final nextTransition =
        serverTransition ?? Schedule.nextTransitionIstUtc(now);
    var delay = serverTransition != null && serverTime != null
        ? serverTransition.difference(serverTime)
        : nextTransition.difference(now);
    if (delay.isNegative || delay == Duration.zero) {
      delay = Schedule.nextTransitionIstUtc(now).difference(now);
    }
    _scheduleTransitionTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() {
        _awaitingScheduleRefresh = true;
        _isOffline = false;
        _offlineSchedule = null;
      });
      _loadSchedule();
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

  void _openDailySchedule() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DailyScheduleScreen()),
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
    final schedule = _awaitingScheduleRefresh
        ? null
        : _isOffline
            ? _offlineSchedule
            : service.publishedSchedule;
    final dateTime = service.serverTimeIst?.toUtc().add(
              const Duration(hours: 5, minutes: 30),
            ) ??
        DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final date = DateFormat('EEEE, d MMMM').format(dateTime);

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
            onPressed: _openDailySchedule,
            tooltip: 'Daily Bus Schedule',
            icon: const Icon(Icons.calendar_month_rounded),
          ),
          Consumer<AnnouncementService>(
            builder: (context, annSvc, _) {
              final unread = annSvc.studentUnreadCount;
              return IconButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const StudentAnnouncementsScreen(),
                  ),
                ),
                tooltip: 'Transport Notices',
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread', style: const TextStyle(fontSize: 10)),
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.notifications_outlined),
                ),
              );
            },
          ),
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
                    const SizedBox(height: AppSpacing.md),
                    Consumer<AnnouncementService>(
                      builder: (context, annSvc, _) {
                        final notices = annSvc.studentAnnouncements;
                        final emergency =
                            notices.where((a) => a.isEmergency).firstOrNull;
                        final unread = annSvc.studentUnreadCount;

                        if (emergency != null) {
                          return Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.md),
                            child: InkWell(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const StudentAnnouncementsScreen(),
                                ),
                              ),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: const Color(0xFFEF4444),
                                      width: 1.5),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.warning_rounded,
                                        color: Colors.red, size: 22),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'EMERGENCY ALERT',
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            emergency.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.arrow_forward_ios_rounded,
                                        size: 14, color: Colors.red),
                                  ],
                                ),
                              ),
                            ),
                          );
                        } else if (unread > 0) {
                          return Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.md),
                            child: InkWell(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const StudentAnnouncementsScreen(),
                                ),
                              ),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFCCFBF1),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: AppColors.emerald
                                          .withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.campaign_rounded,
                                        color: AppColors.emerald, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '$unread new transport notice(s) available',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          color: Color(0xFF0F766E),
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.arrow_forward_ios_rounded,
                                        size: 13, color: AppColors.emerald),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    // Quick banner to Daily Bus Schedule
                    InkWell(
                      onTap: _openDailySchedule,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.navy, AppColors.navyMid],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.navy.withOpacity(0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.calendar_month_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Daily Bus Schedule',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'View date-specific bus numbers & stop timings',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Colors.white70,
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
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
                    _loadSchedule(trip: selection.first);
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
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: ValueListenableBuilder<String?>(
                    valueListenable: ApiService.statusNotifier,
                    builder: (context, status, _) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          if (status != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              status,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              )
            else if (schedule == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ScheduleUnavailable(
                  message: service.errorMessage ??
                      (service.lastPublishedFetchSucceeded &&
                              service.activeTrip == null
                          ? 'No schedule is active now. The morning schedule returns at midnight (IST).'
                          : null),
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
