// lib/screens/admin/announcement_management_screen.dart
// Stage 9 — Administrator Announcements & Schedule Change Alerts Management

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/announcement.dart';
import '../../services/announcement_service.dart';
import 'announcement_composer_screen.dart';
import 'sms_campaign_detail_screen.dart';

class AnnouncementManagementScreen extends StatefulWidget {
  const AnnouncementManagementScreen({super.key});

  @override
  State<AnnouncementManagementScreen> createState() =>
      _AnnouncementManagementScreenState();
}

class _AnnouncementManagementScreenState
    extends State<AnnouncementManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCategoryFilter;

  final List<String> _categories = [
    'All',
    'General Transport Notice',
    'Bus Delay',
    'Bus Cancellation',
    'Route Change',
    'Bus Replacement',
    'Schedule Change',
    'Emergency Notice',
    'Holiday Transport Notice',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  void _loadData() {
    final svc = Provider.of<AnnouncementService>(context, listen: false);
    svc.fetchAdminAnnouncements();
    svc.fetchHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _deleteAnnouncement(Announcement a) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Announcement'),
        content: Text('Are you sure you want to delete "${a.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final svc = Provider.of<AnnouncementService>(context, listen: false);
    final ok = await svc.deleteAnnouncement(a.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Announcement deleted.' : 'Failed to delete.'),
        backgroundColor: ok ? AppColors.emerald : Colors.red,
      ),
    );
  }

  Future<void> _publishDraft(Announcement a) async {
    final svc = Provider.of<AnnouncementService>(context, listen: false);
    final res = await svc.publishAnnouncement(a.id, sendSms: a.hasSms);
    if (!mounted) return;
    if (res != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Announcement published successfully.'),
          backgroundColor: AppColors.emerald,
        ),
      );
    }
  }

  void _openComposer({Announcement? editDraft}) async {
    final res = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnnouncementComposerScreen(existingAnnouncement: editDraft),
      ),
    );
    if (res == true) {
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Announcements & Alerts'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.emerald,
          indicatorWeight: 3,
          labelColor: AppColors.emerald,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: 'Published', icon: Icon(Icons.campaign_rounded, size: 20)),
            Tab(text: 'Drafts', icon: Icon(Icons.edit_note_rounded, size: 20)),
            Tab(text: 'History', icon: Icon(Icons.history_rounded, size: 20)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openComposer(),
        backgroundColor: AppColors.emerald,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Notice'),
      ),
      body: Consumer<AnnouncementService>(
        builder: (context, svc, _) {
          if (svc.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = svc.adminAnnouncements;
          final published = all.where((a) => a.isPublished).toList();
          final drafts = all.where((a) => a.isDraft).toList();

          return Column(
            children: [
              // ── Search & Filter Bar ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Search notices by title, message or route...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    isDense: true,
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              svc.fetchAdminAnnouncements();
                            },
                          )
                        : null,
                  ),
                  onSubmitted: (v) {
                    svc.fetchAdminAnnouncements(
                      category: _selectedCategoryFilter == 'All'
                          ? null
                          : _selectedCategoryFilter,
                      search: v.trim(),
                    );
                  },
                ),
              ),

              // Category Filter Chips
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  itemCount: _categories.length,
                  itemBuilder: (context, idx) {
                    final cat = _categories[idx];
                    final isSel = (_selectedCategoryFilter == cat) ||
                        (_selectedCategoryFilter == null && cat == 'All');
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(cat, style: const TextStyle(fontSize: 11)),
                        selected: isSel,
                        onSelected: (_) {
                          setState(() {
                            _selectedCategoryFilter = cat == 'All' ? null : cat;
                          });
                          svc.fetchAdminAnnouncements(
                            category: cat == 'All' ? null : cat,
                            search: _searchController.text.trim(),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),

              // ── Tab Views ──────────────────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Published Tab
                    _buildAnnouncementList(
                      announcements: published,
                      isDraftTab: false,
                      onRefresh: _loadData,
                    ),

                    // Drafts Tab
                    _buildAnnouncementList(
                      announcements: drafts,
                      isDraftTab: true,
                      onRefresh: _loadData,
                    ),

                    // History Tab
                    _buildHistoryTab(svc.history, _loadData),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAnnouncementList({
    required List<Announcement> announcements,
    required bool isDraftTab,
    required VoidCallback onRefresh,
  }) {
    if (announcements.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: ListView(
          children: [
            const SizedBox(height: 100),
            Center(
              child: Column(
                children: [
                  Icon(
                    isDraftTab
                        ? Icons.drafts_outlined
                        : Icons.notifications_none_rounded,
                    size: 56,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isDraftTab ? 'No draft notices' : 'No published notices yet',
                    style: const TextStyle(
                        fontSize: 15, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        itemCount: announcements.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, idx) {
          final a = announcements[idx];
          return _AnnouncementCard(
            announcement: a,
            isDraft: isDraftTab,
            onEdit: () => _openComposer(editDraft: a),
            onDelete: () => _deleteAnnouncement(a),
            onPublish: () => _publishDraft(a),
            onViewSms: a.smsCampaignId != null
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SmsCampaignDetailScreen(campaignId: a.smsCampaignId!),
                      ),
                    )
                : null,
          );
        },
      ),
    );
  }

  Widget _buildHistoryTab(List<Map<String, dynamic>> history, VoidCallback onRefresh) {
    if (history.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: ListView(
          children: const [
            SizedBox(height: 100),
            Center(
              child: Text(
                'No delivery history recorded yet.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        itemCount: history.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, idx) {
          final h = history[idx];
          final sms = h['sms_details'] as Map<String, dynamic>?;

          return Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          h['title']?.toString() ?? 'Notice',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                      Text(
                        h['published_at'] != null
                            ? h['published_at'].toString().substring(0, 10)
                            : '—',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    h['message']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _MiniTag(
                        icon: Icons.people_outline_rounded,
                        label: 'Reach: ${h['recipient_count'] ?? 0}',
                        color: AppColors.navy,
                      ),
                      const SizedBox(width: 8),
                      _MiniTag(
                        icon: Icons.mark_email_read_outlined,
                        label: 'Read: ${h['read_count'] ?? 0}',
                        color: AppColors.emerald,
                      ),
                      const SizedBox(width: 8),
                      if (sms != null)
                        _MiniTag(
                          icon: Icons.sms_rounded,
                          label: 'SMS: ${sms['status'] ?? "queued"}',
                          color: sms['status'] == 'completed'
                              ? Colors.green
                              : Colors.orange,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final Announcement announcement;
  final bool isDraft;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPublish;
  final VoidCallback? onViewSms;

  const _AnnouncementCard({
    required this.announcement,
    required this.isDraft,
    required this.onEdit,
    required this.onDelete,
    required this.onPublish,
    this.onViewSms,
  });

  @override
  Widget build(BuildContext context) {
    final a = announcement;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(
          color: a.isEmergency
              ? Colors.red.withValues(alpha: 0.5)
              : const Color(0xFFE2E8F0),
          width: a.isEmergency ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Category icon, Category label, Priority pill, Date
            Row(
              children: [
                Icon(a.categoryIcon, size: 16, color: a.categoryColor),
                const SizedBox(width: 6),
                Text(
                  a.category,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: a.categoryColor,
                  ),
                ),
                const SizedBox(width: 8),
                _PriorityPill(a.priority),
                const Spacer(),
                Text(
                  a.publishedAt != null
                      ? a.publishedAt!.toLocal().toString().substring(0, 16)
                      : a.createdAt != null
                          ? 'Draft (${a.createdAt!.toLocal().toString().substring(0, 10)})'
                          : '—',
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Title
            Text(
              a.title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),

            // Message Body
            Text(
              a.message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 10),

            // Target audience and channel tags
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _MiniTag(
                  icon: Icons.radar_rounded,
                  label: a.targetLabel,
                  color: AppColors.navy,
                ),
                if (a.channels.contains('in_app'))
                  const _MiniTag(
                    icon: Icons.smartphone_rounded,
                    label: 'In-App',
                    color: Color(0xFF0F766E),
                  ),
                if (a.hasSms)
                  _MiniTag(
                    icon: Icons.sms_rounded,
                    label: a.smsStatus != null
                        ? 'SMS: ${a.smsStatus}'
                        : 'SMS Queued',
                    color: const Color(0xFFD97706),
                  ),
              ],
            ),
            const Divider(height: 20),

            // Bottom action buttons
            Row(
              children: [
                if (!isDraft) ...[
                  Text(
                    'Read by ${a.readCount} student(s)',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  if (a.smsCampaignId != null && onViewSms != null) ...[
                    TextButton.icon(
                      onPressed: onViewSms,
                      icon: const Icon(Icons.visibility_rounded, size: 14),
                      label: const Text('SMS Campaign',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ],
                  IconButton(
                    tooltip: 'Edit Announcement',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: onEdit,
                  ),
                ] else ...[
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline,
                        size: 14, color: Colors.red),
                    label: const Text('Delete',
                        style: TextStyle(fontSize: 11, color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red)),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded, size: 14),
                    label: const Text('Edit Draft',
                        style: TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: onPublish,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.send_rounded, size: 14),
                    label: const Text('Publish',
                        style: TextStyle(fontSize: 11)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PriorityPill extends StatelessWidget {
  final String priority;
  const _PriorityPill(this.priority);

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (priority) {
      case 'emergency':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFDC2626);
        break;
      case 'high':
        bg = const Color(0xFFFFEDD5);
        fg = const Color(0xFFEA580C);
        break;
      case 'low':
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF64748B);
        break;
      case 'normal':
      default:
        bg = const Color(0xFFCCFBF1);
        fg = const Color(0xFF0F766E);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MiniTag({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
