import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../services/auth_service.dart';
import '../../services/schedule_service.dart';
import '../../services/daily_schedule_service.dart';
import '../../services/notification_service.dart';
import '../../services/api_service.dart';
import 'upload_screen.dart';
import 'schedule_list_screen.dart';
import 'manual_entry_screen.dart';
import 'daily_schedule_management_screen.dart';
import 'daily_schedule_history_screen.dart';
import 'student_management_screen.dart';
import 'fleet_management_screen.dart';
import 'route_allocation_screen.dart';
import 'student_excel_upload_screen.dart';
import 'sms_management_screen.dart';
import '../../services/sms_auto_service.dart';
import 'sms_auto_settings_screen.dart';
import 'sms_pending_confirmations_screen.dart';
import 'announcement_management_screen.dart';
import '../login_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoadingNotifications = false;
  String? _notificationError;

  // Real Database Statistics
  Map<String, dynamic> _scheduleStats = {};
  Map<String, dynamic> _userStats = {};
  bool _isLoadingStats = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ScheduleService>(context, listen: false).fetchAllSchedules();
      Provider.of<SmsAutoService>(context, listen: false).loadSettings();
      _loadNotifications();
      _loadDashboardStats();
    });
  }

  Future<void> _loadDashboardStats() async {
    if (!mounted) return;
    setState(() => _isLoadingStats = true);
    try {
      final svc = Provider.of<DailyScheduleService>(context, listen: false);
      final schedStats = await svc.fetchStats();
      final userRes = await ApiService.get('/users/stats');
      if (!mounted) return;
      setState(() {
        _scheduleStats = schedStats;
        _userStats = Map<String, dynamic>.from(userRes as Map);
        _isLoadingStats = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingStats = false);
    }
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoadingNotifications = true;
      _notificationError = null;
    });
    try {
      final notifications = await NotificationService.getHistory();
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _isLoadingNotifications = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notificationError = 'Could not load broadcast alerts.';
        _isLoadingNotifications = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final schedService = Provider.of<ScheduleService>(context);
    final activityNow = DateTime.now().toUtc();
    final recentActivity = schedService.allSchedules
        .where((schedule) => schedule.isActivityVisibleAt(activityNow))
        .toList(growable: false);

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Column(
        children: [
          // ── Dark Admin Header ───────────────────────────────
          _buildHeader(context, auth, schedService),

          // ── Light Content ──────────────────────────────────
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
                child: RefreshIndicator(
                  onRefresh: () async {
                    await _loadDashboardStats();
                    await _loadNotifications();
                    if (mounted) {
                      await Provider.of<ScheduleService>(context, listen: false)
                          .fetchAllSchedules();
                    }
                  },
                  color: AppColors.emerald,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      // ── 1. Dashboard Overview Header ───────────────────
                      _buildSectionHeader(
                        'Dashboard Overview',
                        trailing: IconButton(
                          icon: const Icon(Icons.refresh_rounded,
                              size: 18, color: AppColors.textSecondary),
                          tooltip: 'Refresh statistics',
                          onPressed: _loadDashboardStats,
                        ),
                      ),

                      // ── Real Database Stats Grid ───────────────────────
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _buildOverviewGrid(),
                        ),
                      ),

                      // ── 2. Daily Bus Schedules ─────────────────────────
                      _buildSectionHeader('Daily Bus Schedule Management'),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _buildDailyScheduleCard(context),
                        ),
                      ),

                      // ── 3. Schedule Sections Grid ──────────────────────
                      _buildSectionHeader('Schedule Publishing & Timetables'),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.15,
                            children: [
                              _ActionCard(
                                icon: Icons.playlist_add_check_rounded,
                                title: 'Published Schedules',
                                subtitle: 'View live bus runs',
                                color: AppColors.emerald,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const DailyScheduleHistoryScreen(),
                                  ),
                                ),
                              ),
                              _ActionCard(
                                icon: Icons.edit_calendar_rounded,
                                title: 'Draft Schedules',
                                subtitle: 'Pending daily plans',
                                color: AppColors.amber,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const DailyScheduleHistoryScreen(),
                                  ),
                                ),
                              ),
                              _ActionCard(
                                icon: Icons.history_rounded,
                                title: 'Schedule Updates',
                                subtitle: 'Audit log & versions',
                                color: const Color(0xFF5E6AD2),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const DailyScheduleHistoryScreen(),
                                  ),
                                ),
                              ),
                              _ActionCard(
                                icon: Icons.table_view_rounded,
                                title: 'Master Timetable',
                                subtitle: 'View master schedules',
                                color: AppColors.navy,
                                onTap: () => _openScheduleList(
                                    context, ScheduleListFilter.all),
                              ),
                              _ActionCard(
                                icon: Icons.document_scanner_rounded,
                                title: 'Update Timetable',
                                subtitle: 'Upload transport schedule',
                                color: AppColors.navy,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const UploadScheduleScreen(),
                                  ),
                                ),
                              ),
                              _ActionCard(
                                icon: Icons.edit_note_rounded,
                                title: 'Manual Entry',
                                subtitle: 'Add master routes',
                                color: AppColors.emerald,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const ManualEntryScreen(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── 4. Administration & Fleet Management ────────────
                      _buildSectionHeader('Administration & Fleet'),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.15,
                            children: [
                              _ActionCard(
                                icon: Icons.people_rounded,
                                title: 'Student Management',
                                subtitle: 'Directory & Search',
                                color: AppColors.navy,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const StudentManagementScreen(),
                                  ),
                                ),
                              ),
                              _ActionCard(
                                icon: Icons.file_upload_rounded,
                                title: 'Upload Student Excel',
                                subtitle: 'Import XLSX / CSV',
                                color: AppColors.emerald,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const StudentExcelUploadScreen(),
                                  ),
                                ),
                              ),
                              _ActionCard(
                                icon: Icons.hub_rounded,
                                title: 'Route Allocations',
                                subtitle: 'Per-route load & counts',
                                color: const Color(0xFF5E6AD2),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const RouteAllocationScreen(),
                                  ),
                                ),
                              ),
                              _ActionCard(
                                icon: Icons.alt_route_rounded,
                                title: 'Route Fleet',
                                subtitle: 'Stops & boarding points',
                                color: AppColors.emerald,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const FleetManagementScreen(
                                            initialTab: 1),
                                  ),
                                ),
                              ),
                              _ActionCard(
                                icon: Icons.directions_bus_rounded,
                                title: 'Bus Management',
                                subtitle: 'Active fleet & numbers',
                                color: const Color(0xFF0284C7),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const FleetManagementScreen(
                                            initialTab: 0),
                                  ),
                                ),
                              ),
                              _ActionCard(
                                icon: Icons.campaign_rounded,
                                title: 'Broadcast Alert',
                                subtitle: 'Emergency notification',
                                color: AppColors.arts,
                                onTap: () => _showBroadcastDialog(context),
                              ),
                              _ActionCard(
                                icon: Icons.campaign_rounded,
                                title: 'Announcements',
                                subtitle: 'Notices & Change Alerts',
                                color: const Color(0xFF0D9488),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const AnnouncementManagementScreen(),
                                  ),
                                ),
                              ),
                              _ActionCard(
                                icon: Icons.sms_rounded,
                                title: 'SMS Management',
                                subtitle: 'Phone SIM Broadcast',
                                color: AppColors.emerald,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SmsManagementScreen(),
                                  ),
                                ),
                              ),
                              _ActionCard(
                                icon: Icons.alarm_on_rounded,
                                title: 'Auto SMS Settings',
                                subtitle: 'Daily 6:30 AM & 2 PM',
                                color: const Color(0xFFD97706),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const SmsAutoSettingsScreen(),
                                  ),
                                ),
                              ),
                              _ActionCard(
                                icon: Icons.mark_email_unread_rounded,
                                title: 'Pending SMS Queue',
                                subtitle: 'Review & Confirm',
                                color: const Color(0xFF0F766E),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const SmsPendingConfirmationsScreen(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── 5. Automatic SMS Scheduling Section (Stage 8) ───
                      _buildSectionHeader('Automatic SMS Scheduling'),
                      _buildAutoSmsSection(),

                      // ── 6. Broadcast Alerts Section ────────────────────
                      _buildSectionHeader('Broadcast Alerts'),
                      if (_isLoadingNotifications)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.emerald),
                            ),
                          ),
                        )
                      else if (_notificationError != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              _notificationError!,
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .error),
                            ),
                          ),
                        )
                      else if (_notifications.isEmpty)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'No broadcast alerts yet.',
                              style:
                                  TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final notification = _notifications[index];
                              final title =
                                  notification['title']?.toString() ?? '';
                              final body =
                                  notification['body']?.toString() ?? '';
                              return Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 10),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.campaign_outlined,
                                        color: AppColors.emerald,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              body,
                                              maxLines: 2,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Edit alert',
                                        onPressed: () =>
                                            _editBroadcastAlert(notification),
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          color: AppColors.navy,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete alert',
                                        onPressed: () =>
                                            _deleteBroadcastAlert(
                                                notification),
                                        icon: Icon(
                                          Icons.delete_outline_rounded,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            childCount: _notifications.length,
                          ),
                        ),

                      // ── 6. Activity Log Section ────────────────────────
                      _buildSectionHeader('Activity Log'),

                      if (schedService.isLoading)
                        const SliverToBoxAdapter(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: CircularProgressIndicator(
                                  color: AppColors.emerald),
                            ),
                          ),
                        )
                      else if (recentActivity.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Container(
                              padding: const EdgeInsets.all(28),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color:
                                          AppColors.emerald.withAlpha(20),
                                      borderRadius:
                                          BorderRadius.circular(16),
                                    ),
                                    child: Icon(
                                      schedService.allSchedules.isEmpty
                                          ? Icons.upload_file_rounded
                                          : Icons.history_rounded,
                                      size: 36,
                                      color: AppColors.emerald,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                      schedService.allSchedules.isEmpty
                                          ? 'No schedules uploaded yet'
                                          : 'No activity in the last 7 days',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary)),
                                  const SizedBox(height: 6),
                                  Text(
                                      schedService.allSchedules.isEmpty
                                          ? 'Use "Update Timetable" to get started'
                                          : 'Older activity is hidden here. Schedules remain in Schedule History.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) {
                              final s = recentActivity[i];
                              final statusColor = s.isPublished
                                  ? AppColors.emerald
                                  : s.status == 'draft'
                                      ? AppColors.amber
                                      : AppColors.textSecondary;
                              return Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 10),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Row(
                                    children: [
                                      KlnceBrandMark(size: 44),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              s.title,
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w700,
                                                  fontSize: 14,
                                                  color:
                                                      AppColors.textPrimary),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Eff: ${s.effectiveDate}',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors
                                                      .textSecondary),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color:
                                              statusColor.withAlpha(25),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                              color: statusColor
                                                  .withAlpha(80)),
                                        ),
                                        child: Text(
                                          s.status.toUpperCase(),
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: statusColor),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            childCount: recentActivity.length,
                          ),
                        ),

                      const SliverToBoxAdapter(
                          child: SizedBox(height: 32)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Overview Stats Rows ─────────────────────────────────────────────

  Widget _buildOverviewGrid() {
    if (_isLoadingStats) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.emerald,
            strokeWidth: 2,
          ),
        ),
      );
    }

    final students = _userStats['students_count'] ?? 0;
    final totalBuses = _scheduleStats['total_buses'] ?? 0;
    final totalRoutes = _scheduleStats['total_routes'] ?? 0;
    final todayPub = _scheduleStats['today_published'] ?? 0;
    final pendingDrafts = _scheduleStats['total_drafts'] ?? 0;
    final updatedCount = _scheduleStats['recently_updated'] ?? 0;

    return Column(
      children: [
        // Row 1: System Master Numbers
        Row(
          children: [
            _StatCard(
              label: 'Students',
              value: '$students',
              icon: Icons.people_rounded,
              color: AppColors.navy,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const StudentManagementScreen()),
              ),
            ),
            const SizedBox(width: 8),
            _StatCard(
              label: 'Buses',
              value: '$totalBuses',
              icon: Icons.directions_bus_rounded,
              color: const Color(0xFF0284C7),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const FleetManagementScreen(initialTab: 0)),
              ),
            ),
            const SizedBox(width: 8),
            _StatCard(
              label: 'Routes',
              value: '$totalRoutes',
              icon: Icons.alt_route_rounded,
              color: AppColors.emerald,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const FleetManagementScreen(initialTab: 1)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Row 2: Daily Schedule Publishing Numbers
        Row(
          children: [
            _StatCard(
              label: 'Today Published',
              value: '$todayPub',
              icon: Icons.check_circle_rounded,
              color: AppColors.emerald,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const DailyScheduleHistoryScreen()),
              ),
            ),
            const SizedBox(width: 8),
            _StatCard(
              label: 'Draft Schedules',
              value: '$pendingDrafts',
              icon: Icons.edit_note_rounded,
              color: AppColors.amber,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const DailyScheduleHistoryScreen()),
              ),
            ),
            const SizedBox(width: 8),
            _StatCard(
              label: 'Updated',
              value: '$updatedCount',
              icon: Icons.update_rounded,
              color: const Color(0xFF5E6AD2),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const DailyScheduleHistoryScreen()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDailyScheduleCard(BuildContext context) {
    final todayPub = _scheduleStats['today_published'] ?? 0;
    final todayDraft = _scheduleStats['today_drafts'] ?? 0;

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const DailyScheduleManagementScreen(),
        ),
      ).then((_) => _loadDashboardStats()),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.navy, AppColors.navyMid],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withAlpha(45),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(38),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.event_note_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daily Schedule Management',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _scheduleStats.isNotEmpty
                        ? 'Today: $todayPub published · $todayDraft drafts'
                        : 'Configure date, session, buses & timings',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white70, size: 16),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildSectionHeader(String title, {Widget? trailing}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
        child: Row(
          children: [
            const _SectionBar(),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildAutoSmsSection() {
    return Consumer<SmsAutoService>(
      builder: (context, autoSvc, _) {
        final s = autoSvc.settings;
        final isEnabled = s?.isEffectivelyEnabled ?? false;
        final isEmergency = s?.emergencyDisabled ?? false;
        final pendingCount = s?.pendingConfirmationsCount ?? 0;
        final isAutomatic = s?.isAutomaticMode ?? false;

        Color statusColor;
        String statusLabel;
        if (isEmergency) {
          statusColor = Colors.red;
          statusLabel = 'Emergency Stopped';
        } else if (isEnabled) {
          statusColor = AppColors.emerald;
          statusLabel =
              isAutomatic ? 'Auto Dispatch Active' : 'Active (Confirmation Mode)';
        } else {
          statusColor = const Color(0xFF64748B);
          statusLabel = 'Auto SMS Disabled';
        }

        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isEnabled
                      ? AppColors.emerald.withValues(alpha: 0.3)
                      : const Color(0xFFE2E8F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isEnabled
                          ? AppColors.emerald.withValues(alpha: 0.08)
                          : const Color(0xFFF8FAFC),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.schedule_send_rounded,
                          size: 20,
                          color: isEnabled
                              ? AppColors.emerald
                              : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Automatic SMS Engine',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: statusColor.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7)
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: const Color(0xFFFDE68A)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.wb_sunny_rounded,
                                            size: 14, color: Color(0xFFD97706)),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Morning (${s?.morningTime ?? "06:30"})',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11,
                                            color: Color(0xFF92400E),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      s?.isReadyForMorning == true
                                          ? '✓ Schedule Published'
                                          : 'Schedule Pending',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: s?.isReadyForMorning == true
                                            ? const Color(0xFF065F46)
                                            : const Color(0xFF92400E),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0E7FF)
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: const Color(0xFFC7D2FE)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.wb_twilight_rounded,
                                            size: 14, color: Color(0xFF4338CA)),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Afternoon (${s?.afternoonTime ?? "14:00"})',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11,
                                            color: Color(0xFF3730A3),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      s?.isReadyForAfternoon == true
                                          ? '✓ Schedule Published'
                                          : 'Schedule Pending',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: s?.isReadyForAfternoon == true
                                            ? const Color(0xFF065F46)
                                            : const Color(0xFF3730A3),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (pendingCount > 0) ...[
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const SmsPendingConfirmationsScreen(),
                              ),
                            ),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: const Color(0xFFFDE68A)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded,
                                      color: Color(0xFFD97706), size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '$pendingCount SMS campaign(s) awaiting your review & send confirmation',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Color(0xFF92400E),
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios_rounded,
                                      size: 13, color: Color(0xFFD97706)),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const SmsAutoSettingsScreen(),
                                  ),
                                ),
                                icon: const Icon(
                                    Icons.settings_suggest_rounded,
                                    size: 16),
                                label: const Text('Configure Auto SMS',
                                    style: TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.navy,
                                  side: const BorderSide(
                                      color: Color(0xFFCBD5E1)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                ),
                              ),
                            ),
                            if (isEnabled) ...[
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: autoSvc.isEmergencyDisabling
                                    ? null
                                    : () async {
                                        final confirmed =
                                            await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text(
                                                'Emergency Stop Auto SMS?'),
                                            content: const Text(
                                                'Immediately stops background scheduled SMS dispatch.'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('Cancel'),
                                              ),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.red),
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                child: const Text(
                                                    'Stop Immediately'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirmed == true) {
                                          await autoSvc.emergencyDisable();
                                        }
                                      },
                                icon: const Icon(Icons.stop_circle_outlined,
                                    size: 16, color: Colors.red),
                                label: const Text('Stop',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.red)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.red),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(
      BuildContext context, AuthService auth, ScheduleService schedService) {
    return Container(
      color: AppColors.navy,
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KlnceBrandMark(
                size: 44,
                onTap: () => navigateToDashboard(context),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin Dashboard',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      'KLNCE Transport Control',
                      style:
                          TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              // Logout button
              GestureDetector(
                onTap: () async {
                  await auth.logout();
                  if (!context.mounted) return;
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()));
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(26),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.logout_rounded,
                          color: Colors.white70, size: 15),
                      SizedBox(width: 5),
                      Text('Logout',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Welcome back,',
            style: TextStyle(
                color: Colors.white.withAlpha(140), fontSize: 13),
          ),
          Text(
            auth.currentUser?.name ?? 'Transport Officer',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  void _showComingSoonSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.navy,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showBroadcastDialog(BuildContext context) async {
    await _showAlertEditor(context);
  }

  Future<void> _editBroadcastAlert(
    Map<String, dynamic> notification,
  ) async {
    await _showAlertEditor(context, notification: notification);
  }

  void _openScheduleList(
    BuildContext context,
    ScheduleListFilter filter,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScheduleListScreen(filter: filter),
      ),
    );
  }

  Future<void> _deleteBroadcastAlert(
    Map<String, dynamic> notification,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final rawId = notification['id'];
    if (rawId is! int) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This alert cannot be deleted.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete broadcast alert?'),
        content: const Text(
          'This removes the alert from app history. Any SMS or push messages already sent cannot be recalled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      await NotificationService.deleteBroadcast(id: rawId);
      if (!mounted) return;
      setState(() {
        _notifications.removeWhere((item) => item['id'] == rawId);
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Alert deleted from app history.'),
          backgroundColor: AppColors.emeraldDark,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              'Could not delete alert. Check the connection and try again.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showAlertEditor(
    BuildContext context, {
    Map<String, dynamic>? notification,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BroadcastAlertDialog(notification: notification),
    );
    if (!mounted || saved != true) return;

    await _loadNotifications();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          notification == null ? 'Alert sent.' : 'Alert updated.',
        ),
        backgroundColor: AppColors.emeraldDark,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ── Shared Widgets ───────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionBar extends StatelessWidget {
  const _SectionBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 18,
      decoration: BoxDecoration(
        color: AppColors.emerald,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;
  final bool comingSoon;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: comingSoon ? 0.65 : 1.0,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    if (comingSoon)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: const Text(
                          'Soon',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Broadcast Alert Dialog ────────────────────────────────────────────────────

class _BroadcastAlertDialog extends StatefulWidget {
  final Map<String, dynamic>? notification;

  const _BroadcastAlertDialog({this.notification});

  @override
  State<_BroadcastAlertDialog> createState() => _BroadcastAlertDialogState();
}

class _BroadcastAlertDialogState extends State<_BroadcastAlertDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _messageController;
  bool _sendSms = false;
  bool _isSaving = false;
  String? _errorMessage;

  bool get _isEditing => widget.notification != null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.notification?['title']?.toString() ?? '',
    );
    _messageController = TextEditingController(
      text: widget.notification?['body']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final body = _messageController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      setState(() => _errorMessage = 'Enter both a title and a message.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      if (_isEditing) {
        final id = widget.notification!['id'];
        if (id is! int) {
          throw const FormatException('Invalid alert identifier.');
        }
        await NotificationService.updateBroadcast(
          id: id,
          title: title,
          body: body,
        );
      } else {
        final sent = await NotificationService.sendBroadcast(
          title: title,
          body: body,
          sendSms: _sendSms,
        );
        if (!sent) {
          throw Exception('Alert could not be sent.');
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = _isEditing
            ? 'Alert could not be updated. Check the connection and try again.'
            : 'Alert could not be sent. Check the connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      title: Text(_isEditing ? 'Edit broadcast alert' : 'Broadcast alert'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Alert title'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _messageController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Message'),
            ),
            if (_isEditing)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'Editing changes the alert shown in the app. Already sent SMS or push messages cannot be changed.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            else
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _sendSms,
                onChanged: _isSaving
                    ? null
                    : (value) => setState(() => _sendSms = value ?? false),
                title: const Text('Also send SMS'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            if (_errorMessage != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _isSaving ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(_isEditing ? Icons.save_rounded : Icons.send_rounded),
          label: Text(
            _isSaving
                ? (_isEditing ? 'Saving' : 'Sending')
                : (_isEditing ? 'Save changes' : 'Send alert'),
          ),
        ),
      ],
    );
  }
}
