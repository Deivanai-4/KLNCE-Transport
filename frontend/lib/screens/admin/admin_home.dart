import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../services/auth_service.dart';
import '../../services/schedule_service.dart';
import '../../services/notification_service.dart';
import 'upload_screen.dart';
import 'schedule_list_screen.dart';
import 'manual_entry_screen.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ScheduleService>(context, listen: false).fetchAllSchedules();
      _loadNotifications();
    });
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
                child: CustomScrollView(
                  slivers: [
                    // Stats
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                        child: Row(
                          children: [
                            _StatCard(
                              label: 'Total',
                              value: '${schedService.allSchedules.length}',
                              icon: Icons.calendar_month_rounded,
                              color: AppColors.navy,
                              onTap: () => _openScheduleList(
                                  context, ScheduleListFilter.all),
                            ),
                            const SizedBox(width: 10),
                            _StatCard(
                              label: 'Published',
                              value:
                                  '${schedService.allSchedules.where((s) => s.isPublished).length}',
                              icon: Icons.check_circle_rounded,
                              color: AppColors.emerald,
                              onTap: () => _openScheduleList(
                                context,
                                ScheduleListFilter.published,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _StatCard(
                              label: 'Drafts',
                              value:
                                  '${schedService.allSchedules.where((s) => s.status == "draft").length}',
                              icon: Icons.edit_rounded,
                              color: AppColors.amber,
                              onTap: () => _openScheduleList(
                                context,
                                ScheduleListFilter.drafts,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Quick Actions section
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                        child: Row(
                          children: [
                            _SectionBar(),
                            SizedBox(width: 8),
                            Text('Quick Actions',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: AppColors.textPrimary,
                                )),
                          ],
                        ),
                      ),
                    ),

                    // Action Cards grid
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
                              icon: Icons.document_scanner_rounded,
                              title: 'Update Timetable',
                              subtitle: 'Upload transport schedule',
                              color: AppColors.navy,
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const UploadScheduleScreen())),
                            ),
                            _ActionCard(
                              icon: Icons.edit_note_rounded,
                              title: 'Manual Entry',
                              subtitle: 'Add routes manually',
                              color: AppColors.emerald,
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const ManualEntryScreen())),
                            ),
                            _ActionCard(
                              icon: Icons.table_view_rounded,
                              title: 'Schedule History',
                              subtitle: 'View all timetables',
                              color: AppColors.amber,
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const ScheduleListScreen())),
                            ),
                            _ActionCard(
                              icon: Icons.campaign_rounded,
                              title: 'Broadcast Alert',
                              subtitle: 'Emergency notification',
                              color: AppColors.arts,
                              onTap: () => _showBroadcastDialog(context),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                        child: Row(
                          children: [
                            _SectionBar(),
                            SizedBox(width: 8),
                            Text(
                              'Broadcast Alerts',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isLoadingNotifications)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.emerald,
                            ),
                          ),
                        ),
                      )
                    else if (_notificationError != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            _notificationError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      )
                    else if (_notifications.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'No broadcast alerts yet.',
                            style: TextStyle(color: AppColors.textSecondary),
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
                            final body = notification['body']?.toString() ?? '';
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
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
                                            overflow: TextOverflow.ellipsis,
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
                                          _deleteBroadcastAlert(notification),
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        color:
                                            Theme.of(context).colorScheme.error,
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

                    // Activity log section
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                        child: Row(
                          children: [
                            _SectionBar(),
                            SizedBox(width: 8),
                            Text('Activity Log',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: AppColors.textPrimary,
                                )),
                          ],
                        ),
                      ),
                    ),

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
                              border:
                                  Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppColors.emerald.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(
                                    recentActivity.isEmpty &&
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
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary)),
                                const SizedBox(height: 6),
                                Text(
                                    schedService.allSchedules.isEmpty
                                        ? 'Use "Update Timetable" to get started'
                                        : 'Older activity is hidden here. Schedules remain in Schedule History.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
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
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
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
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                                color: AppColors.textPrimary),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Eff: ${s.effectiveDate}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                            color:
                                                statusColor.withOpacity(0.3)),
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

                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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
          // Top row
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
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              // Logout
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
                    color: Colors.white.withOpacity(0.1),
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
            style:
                TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13),
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

// ── Helper widgets ──────────────────────────────────────────────

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
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const Spacer(),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

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
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(height: 6),
                Text(value,
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: color)),
                const SizedBox(height: 2),
                Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
