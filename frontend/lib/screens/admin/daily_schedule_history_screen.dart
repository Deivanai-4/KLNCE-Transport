import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/daily_schedule.dart';
import '../../services/daily_schedule_service.dart';
import 'daily_schedule_management_screen.dart';

class DailyScheduleHistoryScreen extends StatefulWidget {
  const DailyScheduleHistoryScreen({super.key});

  @override
  State<DailyScheduleHistoryScreen> createState() =>
      _DailyScheduleHistoryScreenState();
}

class _DailyScheduleHistoryScreenState
    extends State<DailyScheduleHistoryScreen> {
  List<DailySchedule> _schedules = [];
  bool _isLoading = false;
  String? _error;

  // Filters
  DateTime? _filterDate;
  final TextEditingController _busController = TextEditingController();
  String _statusFilter = 'all'; // 'all', 'published', 'draft'

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  @override
  void dispose() {
    _busController.dispose();
    super.dispose();
  }

  Future<void> _loadSchedules() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final svc = Provider.of<DailyScheduleService>(context, listen: false);
      final dateStr = _filterDate != null
          ? '${_filterDate!.year.toString().padLeft(4, '0')}-'
              '${_filterDate!.month.toString().padLeft(2, '0')}-'
              '${_filterDate!.day.toString().padLeft(2, '0')}'
          : null;
      final busNum =
          _busController.text.trim().isNotEmpty ? _busController.text.trim() : null;
      final status = _statusFilter == 'all' ? null : _statusFilter;

      final list = await svc.fetchDailySchedules(
        date: dateStr,
        status: status,
        busNumber: busNum,
      );

      setState(() {
        _schedules = list;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.navy),
        ),
        child: child!,
      ),
    );
    if (!mounted || picked == null) return;
    setState(() => _filterDate = picked);
    _loadSchedules();
  }

  void _clearDateFilter() {
    setState(() => _filterDate = null);
    _loadSchedules();
  }

  Future<void> _confirmDelete(DailySchedule schedule) async {
    if (schedule.status == 'published') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Published schedule history is preserved and cannot be deleted.'),
          backgroundColor: AppColors.amber,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Draft?'),
        content: Text(
            'Delete the ${schedule.session} schedule draft for ${schedule.date}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      final svc = Provider.of<DailyScheduleService>(context, listen: false);
      await svc.deleteDailySchedule(schedule.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Draft deleted successfully.'),
          backgroundColor: AppColors.emeraldDark,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _loadSchedules();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openEdit(DailySchedule schedule) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DailyScheduleManagementScreen(
          initialDate: schedule.date,
          initialSession: schedule.session,
        ),
      ),
    ).then((_) => _loadSchedules());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text(
          'Schedule History',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadSchedules,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: [
          Row(
            children: [
              // Date filter chip
              Expanded(
                child: GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: _filterDate != null
                          ? AppColors.navy.withAlpha(20)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _filterDate != null
                              ? AppColors.navy
                              : const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            size: 15,
                            color: _filterDate != null
                                ? AppColors.navy
                                : AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _filterDate != null
                                ? '${_filterDate!.day.toString().padLeft(2, '0')}/'
                                    '${_filterDate!.month.toString().padLeft(2, '0')}/'
                                    '${_filterDate!.year}'
                                : 'Filter by date',
                            style: TextStyle(
                              fontSize: 12,
                              color: _filterDate != null
                                  ? AppColors.navy
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        if (_filterDate != null)
                          GestureDetector(
                            onTap: _clearDateFilter,
                            child: const Icon(Icons.close_rounded,
                                size: 15, color: AppColors.navy),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Status dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _statusFilter,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All')),
                      DropdownMenuItem(
                          value: 'published', child: Text('Published')),
                      DropdownMenuItem(value: 'draft', child: Text('Drafts')),
                    ],
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() => _statusFilter = val);
                      _loadSchedules();
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Bus number filter
          TextField(
            controller: _busController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'Filter by bus number (e.g. S1, M2)',
              hintStyle: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
              prefixIcon: const Icon(Icons.directions_bus_rounded,
                  size: 18, color: AppColors.textSecondary),
              suffixIcon: _busController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () {
                        _busController.clear();
                        _loadSchedules();
                      })
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: AppColors.navy, width: 1.5)),
            ),
            onSubmitted: (_) => _loadSchedules(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.emerald),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 48, color: AppColors.amber),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadSchedules,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
    if (_schedules.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history_rounded,
                  size: 56, color: AppColors.textSecondary),
              const SizedBox(height: 14),
              const Text('No schedules found',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              const Text('Try adjusting your date, bus number or status filters.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSchedules,
      color: AppColors.emerald,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _schedules.length,
        itemBuilder: (context, index) {
          final s = _schedules[index];
          return _ScheduleHistoryTile(
            schedule: s,
            onEdit: () => _openEdit(s),
            onDelete: () => _confirmDelete(s),
          );
        },
      ),
    );
  }
}

class _ScheduleHistoryTile extends StatelessWidget {
  final DailySchedule schedule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ScheduleHistoryTile({
    required this.schedule,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isPublished = schedule.status == 'published';
    final statusColor = isPublished ? AppColors.emerald : AppColors.amber;
    final statusLabel = isPublished ? 'Published' : 'Draft';
    final busSummary = schedule.buses.map((b) => b.busNumber).join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Session icon
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: schedule.session == 'morning'
                      ? const Color(0xFFFFF8E1)
                      : const Color(0xFFE8EAF6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  schedule.session == 'morning'
                      ? Icons.wb_sunny_rounded
                      : Icons.nights_stay_rounded,
                  color: schedule.session == 'morning'
                      ? AppColors.amber
                      : AppColors.navy,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          schedule.date,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.textPrimary),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'v${schedule.version}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${schedule.session[0].toUpperCase()}${schedule.session.substring(1)} · '
                      '${schedule.buses.length} bus${schedule.buses.length == 1 ? '' : 'es'}'
                      '${busSummary.isNotEmpty ? ' ($busSummary)' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    if (schedule.updatedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Updated: ${_formatTs(schedule.updatedAt!)}',
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withAlpha(80)),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusColor),
                    ),
                  ),
                  if (schedule.isUpdated) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.amber.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'UPDATED',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.amber),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: onEdit,
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.edit_rounded,
                              size: 16, color: AppColors.navy),
                        ),
                      ),
                      if (!isPublished) ...[
                        const SizedBox(width: 2),
                        InkWell(
                          onTap: onDelete,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.delete_outline_rounded,
                                size: 16,
                                color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTs(DateTime ts) {
    final local = ts.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
