// lib/screens/student/announcements_screen.dart
// Stage 9 — Student View for Transport Announcements & Schedule Change Alerts

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/announcement.dart';
import '../../services/announcement_service.dart';

class StudentAnnouncementsScreen extends StatefulWidget {
  const StudentAnnouncementsScreen({super.key});

  @override
  State<StudentAnnouncementsScreen> createState() =>
      _StudentAnnouncementsScreenState();
}

class _StudentAnnouncementsScreenState
    extends State<StudentAnnouncementsScreen> {
  String _selectedFilter = 'All';

  final List<String> _filterChips = [
    'All',
    'Emergency',
    'Bus Delay',
    'Route Change',
    'Schedule Change',
    'Holiday',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AnnouncementService>(context, listen: false)
          .fetchStudentAnnouncements();
    });
  }

  void _showNoticeDetail(Announcement a) {
    // Mark as read
    if (!a.isRead) {
      Provider.of<AnnouncementService>(context, listen: false).markAsRead(a.id);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(a.categoryIcon, color: a.categoryColor, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    a.category,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: a.categoryColor,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                a.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                a.publishedAt != null
                    ? 'Published on ${a.publishedAt!.toLocal().toString().substring(0, 16)} IST'
                    : 'Recent notice',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
              const Divider(height: 24),
              Text(
                a.message,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 20),
              if (a.targetType != 'all_active')
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        'Targeted to: ${a.targetLabel}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transport Notices'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                Provider.of<AnnouncementService>(context, listen: false)
                    .fetchStudentAnnouncements(),
          ),
        ],
      ),
      body: Consumer<AnnouncementService>(
        builder: (context, svc, _) {
          if (svc.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final allNotices = svc.studentAnnouncements;
          final emergencyNotices = allNotices.where((a) => a.isEmergency).toList();

          final filteredNotices = allNotices.where((a) {
            if (_selectedFilter == 'All') return true;
            if (_selectedFilter == 'Emergency') return a.isEmergency;
            if (_selectedFilter == 'Holiday') return a.category.contains('Holiday');
            return a.category.toLowerCase().contains(_selectedFilter.toLowerCase());
          }).toList();

          return RefreshIndicator(
            onRefresh: svc.fetchStudentAnnouncements,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Pinned Emergency Banner ──────────────────────────────────
                if (emergencyNotices.isNotEmpty) ...[
                  ...emergencyNotices.map((em) => _buildEmergencyCard(em)),
                  const SizedBox(height: 16),
                ],

                // ── Filter Chips ─────────────────────────────────────────────
                SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _filterChips.length,
                    itemBuilder: (context, idx) {
                      final f = _filterChips[idx];
                      final isSel = _selectedFilter == f;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(f, style: const TextStyle(fontSize: 12)),
                          selected: isSel,
                          selectedColor: AppColors.emerald.withValues(alpha: 0.2),
                          onSelected: (_) => setState(() => _selectedFilter = f),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),

                // ── Notices List ─────────────────────────────────────────────
                if (filteredNotices.isEmpty) ...[
                  const SizedBox(height: 80),
                  Center(
                    child: Column(
                      children: [
                        const Icon(Icons.notifications_off_outlined,
                            size: 48, color: AppColors.textSecondary),
                        const SizedBox(height: 12),
                        Text(
                          _selectedFilter == 'All'
                              ? 'No transport notices at this time'
                              : 'No notices found for "$_selectedFilter"',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  ...filteredNotices.map((a) => _buildNoticeTile(a)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmergencyCard(Announcement a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md),
          onTap: () => _showNoticeDetail(a),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_rounded, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'EMERGENCY ALERT',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (!a.isRead)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 9),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  a.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF991B1B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  a.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF7F1D1D)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      a.publishedAt != null
                          ? a.publishedAt!.toLocal().toString().substring(0, 16)
                          : '',
                      style: const TextStyle(fontSize: 10, color: Color(0xFFB91C1C)),
                    ),
                    const Spacer(),
                    const Text(
                      'Tap to read full alert →',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFDC2626)),
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

  Widget _buildNoticeTile(Announcement a) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(
          color: a.isRead
              ? const Color(0xFFE2E8F0)
              : AppColors.emerald.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: () => _showNoticeDetail(a),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                  const Spacer(),
                  if (!a.isRead) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.emerald,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    a.publishedAt != null
                        ? a.publishedAt!.toLocal().toString().substring(0, 10)
                        : '',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                a.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: a.isRead ? FontWeight.w600 : FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                a.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    a.targetLabel,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  const Text(
                    'Read more →',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.emerald,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
