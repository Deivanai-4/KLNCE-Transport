import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/schedule.dart';
import '../../services/schedule_service.dart';
import 'ocr_review_screen.dart';

enum ScheduleListFilter {
  all('Schedule History', 'No schedules yet'),
  published('Published Schedules', 'No published schedules'),
  drafts('Draft Schedules', 'No draft schedules');

  final String title;
  final String emptyMessage;

  const ScheduleListFilter(this.title, this.emptyMessage);

  bool matches(Schedule schedule) {
    switch (this) {
      case ScheduleListFilter.all:
        return true;
      case ScheduleListFilter.published:
        return schedule.isPublished;
      case ScheduleListFilter.drafts:
        return schedule.status == 'draft';
    }
  }
}

class ScheduleListScreen extends StatefulWidget {
  final ScheduleListFilter filter;

  const ScheduleListScreen({
    super.key,
    this.filter = ScheduleListFilter.all,
  });

  @override
  State<ScheduleListScreen> createState() => _ScheduleListScreenState();
}

class _ScheduleListScreenState extends State<ScheduleListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ScheduleService>(context, listen: false).fetchAllSchedules();
    });
  }

  @override
  Widget build(BuildContext context) {
    final svc = Provider.of<ScheduleService>(context);
    final schedules =
        svc.allSchedules.where(widget.filter.matches).toList(growable: false);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) navigateToDashboard(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.navy,
        body: Column(
          children: [
            // ── Dark Header ─────────────────────────────────────
            Container(
              color: AppColors.navy,
              padding: EdgeInsets.fromLTRB(
                  16, MediaQuery.of(context).padding.top + 12, 16, 20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => navigateToDashboard(context),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.filter.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => svc.fetchAllSchedules(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.refresh_rounded,
                          color: Colors.white70, size: 18),
                    ),
                  ),
                ],
              ),
            ),

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
                child: svc.isLoading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: AppColors.emerald))
                    : schedules.isEmpty
                        ? _buildEmpty()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                            itemCount: schedules.length,
                            itemBuilder: (ctx, i) =>
                                _ScheduleCard(schedule: schedules[i]),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.emerald.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.upload_file_rounded,
                size: 48, color: AppColors.emerald),
          ),
          const SizedBox(height: 16),
          Text(widget.filter.emptyMessage,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('Update the timetable from the admin dashboard',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final Schedule schedule;
  const _ScheduleCard({required this.schedule});

  @override
  Widget build(BuildContext context) {
    final s = schedule;
    final Color statusColor;
    final String statusLabel;

    if (s.isPublished) {
      statusColor = AppColors.emerald;
      statusLabel = 'PUBLISHED';
    } else if (s.status == 'verified') {
      statusColor = AppColors.navy;
      statusLabel = 'VERIFIED';
    } else if (s.status == 'draft') {
      statusColor = AppColors.amber;
      statusLabel = 'DRAFT';
    } else {
      statusColor = AppColors.textSecondary;
      statusLabel = s.status.toUpperCase();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => OcrReviewScreen(schedule: s)),
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                // File type icon
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    s.fileType == 'pdf'
                        ? Icons.picture_as_pdf_rounded
                        : Icons.image_rounded,
                    color: statusColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                // Title + meta
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${s.tripDirection.toUpperCase()}  •  Eff: ${s.effectiveDate}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Status badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusColor),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textSecondary, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
