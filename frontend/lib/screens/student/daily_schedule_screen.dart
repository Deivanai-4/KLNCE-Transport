import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/daily_schedule.dart';
import '../../services/daily_schedule_service.dart';

class DailyScheduleScreen extends StatefulWidget {
  final DateTime? initialDate;

  const DailyScheduleScreen({super.key, this.initialDate});

  @override
  State<DailyScheduleScreen> createState() => _DailyScheduleScreenState();
}

class _DailyScheduleScreenState extends State<DailyScheduleScreen> {
  late DateTime _selectedDate;
  String _selectedSession = 'morning'; // 'morning' or 'afternoon'

  DailySchedule? _schedule;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();

    // Determine initial session from current time: if after 12:00 PM, show afternoon by default
    final nowHour = DateTime.now().hour;
    if (nowHour >= 12 && nowHour < 21) {
      _selectedSession = 'afternoon';
    } else {
      _selectedSession = 'morning';
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchSchedule();
    });
  }

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);

  Future<void> _fetchSchedule() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final svc = Provider.of<DailyScheduleService>(context, listen: false);
    final results = await svc.fetchDailySchedules(
      date: _dateStr,
      session: _selectedSession,
      status: 'published', // Students only see published
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _schedule = results.isNotEmpty ? results.first : null;
      _errorMessage = svc.errorMessage;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime(2028, 12, 31),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _fetchSchedule();
    }
  }

  void _selectToday() {
    setState(() => _selectedDate = DateTime.now());
    _fetchSchedule();
  }

  void _selectTomorrow() {
    setState(() => _selectedDate = DateTime.now().add(const Duration(days: 1)));
    _fetchSchedule();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Daily Bus Schedule'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _fetchSchedule,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchSchedule,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            // ── Date Selector Card ──────────────────────────────
            _buildDateSelector(),

            const SizedBox(height: AppSpacing.md),

            // ── Session Segmented Button ────────────────────────
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'morning',
                  label: Text('Morning'),
                  icon: Icon(Icons.wb_sunny_outlined, size: 18),
                ),
                ButtonSegment(
                  value: 'afternoon',
                  label: Text('Afternoon'),
                  icon: Icon(Icons.wb_twilight_rounded, size: 18),
                ),
              ],
              selected: {_selectedSession},
              onSelectionChanged: (set) {
                if (set.isNotEmpty && set.first != _selectedSession) {
                  setState(() => _selectedSession = set.first);
                  _fetchSchedule();
                }
              },
            ),

            const SizedBox(height: AppSpacing.md),

            // ── Schedule Body / Loading / Empty State ───────────
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40.0),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage != null)
              _buildErrorCard(_errorMessage!)
            else if (_schedule == null)
              _buildEmptyState()
            else ...[
              // Publication & Update Status Banner
              _buildStatusBanner(_schedule!),

              const SizedBox(height: AppSpacing.md),

              // Bus List Header
              Row(
                children: [
                  const Icon(Icons.directions_bus_rounded,
                      size: 20, color: AppColors.navy),
                  const SizedBox(width: 8),
                  Text(
                    'Operating Buses (${_schedule!.buses.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // Bus Cards
              ..._schedule!.buses.map((bus) => _buildBusCard(bus)),
            ],

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    final displayDate = DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate);
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = _selectedDate.year == tomorrow.year &&
        _selectedDate.month == tomorrow.month &&
        _selectedDate.day == tomorrow.day;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayDate,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        isToday
                            ? 'Today\'s Schedule'
                            : (isTomorrow ? 'Tomorrow\'s Schedule' : 'Schedule for $_dateStr'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_month_rounded,
                      color: AppColors.emerald),
                  tooltip: 'Pick date',
                  onPressed: _pickDate,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                ActionChip(
                  label: const Text('Today', style: TextStyle(fontSize: 12)),
                  backgroundColor: isToday ? AppColors.engBg : Colors.white,
                  side: BorderSide(
                    color: isToday ? AppColors.emerald : Colors.grey.shade300,
                  ),
                  onPressed: _selectToday,
                ),
                const SizedBox(width: AppSpacing.sm),
                ActionChip(
                  label: const Text('Tomorrow', style: TextStyle(fontSize: 12)),
                  backgroundColor: isTomorrow ? AppColors.engBg : Colors.white,
                  side: BorderSide(
                    color: isTomorrow ? AppColors.emerald : Colors.grey.shade300,
                  ),
                  onPressed: _selectTomorrow,
                ),
                const SizedBox(width: AppSpacing.sm),
                ActionChip(
                  avatar: const Icon(Icons.calendar_today_rounded, size: 14),
                  label: const Text('Select Date', style: TextStyle(fontSize: 12)),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: Colors.grey.shade300),
                  onPressed: _pickDate,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(DailySchedule schedule) {
    final isUpdated = schedule.isUpdated;
    final lastUpdated = schedule.updatedAt != null
        ? DateFormat('MMM d, h:mm a').format(schedule.updatedAt!.toLocal())
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUpdated ? Colors.amber.shade50 : AppColors.engBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUpdated ? Colors.amber.shade300 : AppColors.emerald.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isUpdated ? Icons.update_rounded : Icons.verified_rounded,
            size: 20,
            color: isUpdated ? AppColors.amber : AppColors.emeraldDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isUpdated
                      ? 'UPDATED SCHEDULE (Rev v${schedule.version})'
                      : 'OFFICIAL PUBLISHED SCHEDULE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isUpdated ? AppColors.amber : AppColors.emeraldDark,
                  ),
                ),
                if (lastUpdated != null)
                  Text(
                    'Last updated: $lastUpdated',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusCard(DailyBus bus) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Bus ${bus.busNumber}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    bus.routeName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const Icon(Icons.schedule_rounded,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  bus.departureTime,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.emeraldDark,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.route_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  '${bus.stops.length} Stops & Arrival Times:',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...List.generate(bus.stops.length, (idx) {
              final stop = bus.stops[idx];
              final isLast = idx == bus.stops.length - 1;

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Timeline bar
                    SizedBox(
                      width: 20,
                      child: Column(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: idx == 0
                                  ? AppColors.emerald
                                  : (isLast ? AppColors.navy : Colors.white),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: idx == 0
                                    ? AppColors.emerald
                                    : (isLast ? AppColors.navy : AppColors.emerald),
                                width: 2,
                              ),
                            ),
                          ),
                          if (!isLast)
                            Expanded(
                              child: Container(
                                width: 2,
                                color: Colors.grey.shade300,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Text(
                          stop.stopName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: idx == 0 || isLast
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Text(
                        stop.arrivalTime,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navyMid,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.event_busy_rounded,
              size: 48,
              color: AppColors.amber,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No Schedule Published Yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The transport office hasn\'t published a ${_selectedSession.toUpperCase()} schedule for $_dateStr. Please check back soon or consult the master timetable.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Card(
      color: Colors.red.shade50,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.red, size: 32),
            const SizedBox(height: 8),
            Text(
              'Could not load schedule',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red.shade900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _fetchSchedule,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
