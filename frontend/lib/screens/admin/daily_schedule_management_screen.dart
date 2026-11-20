import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/daily_schedule.dart';
import '../../services/daily_schedule_service.dart';
import '../../services/bus_service.dart';
import 'announcement_composer_screen.dart';

class DailyScheduleManagementScreen extends StatefulWidget {
  final String? initialDate;
  final String? initialSession;

  const DailyScheduleManagementScreen({
    super.key,
    this.initialDate,
    this.initialSession,
  });

  @override
  State<DailyScheduleManagementScreen> createState() =>
      _DailyScheduleManagementScreenState();
}

class _DailyScheduleManagementScreenState
    extends State<DailyScheduleManagementScreen> {
  late DateTime _selectedDate;
  String _selectedSession = 'morning'; // 'morning' or 'afternoon'

  DailySchedule? _currentSchedule;
  bool _isLoading = false;
  bool _isSaving = false;

  // Editable bus items
  final List<_BusEntry> _buses = [];

  // Route & Stop suggestions
  List<String> _knownStopNames = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialDate != null) {
      try {
        _selectedDate = DateTime.parse(widget.initialDate!);
      } catch (_) {
        _selectedDate = DateTime.now();
      }
    } else {
      _selectedDate = DateTime.now();
    }
    if (widget.initialSession != null) {
      _selectedSession = widget.initialSession!;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMasterStops();
      _fetchScheduleForSelection();

      final svc =
          Provider.of<DailyScheduleService>(context, listen: false);
      final changeSummary = svc.lastChangeSummary;
      if (changeSummary != null && changeSummary['has_changes'] == true) {
        svc.clearLastChangeSummary();
        _promptScheduleChangeAnnouncement(changeSummary);
      }
    });
  }

  Future<void> _loadMasterStops() async {
    final busSvc = Provider.of<BusService>(context, listen: false);
    await busSvc.fetchAllStops();
    if (mounted) {
      setState(() {
        _knownStopNames = busSvc.allStops
            .map((s) => s['standard_name_en'] as String? ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      });
    }
  }

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);

  Future<void> _fetchScheduleForSelection() async {
    setState(() => _isLoading = true);
    final svc = Provider.of<DailyScheduleService>(context, listen: false);
    final results = await svc.fetchDailySchedules(
      date: _dateStr,
      session: _selectedSession,
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (results.isNotEmpty) {
        _currentSchedule = results.first;
        _populateFromSchedule(_currentSchedule!);
      } else {
        _currentSchedule = null;
        _initEmptyOrExample();
      }
    });
  }

  void _populateFromSchedule(DailySchedule schedule) {
    _buses.clear();
    for (final bus in schedule.buses) {
      final entry = _BusEntry(
        busNumberCtrl: TextEditingController(text: bus.busNumber),
        routeNameCtrl: TextEditingController(text: bus.routeName),
        departureTimeCtrl: TextEditingController(text: bus.departureTime),
      );
      for (final stop in bus.stops) {
        entry.stops.add(_StopEntry(
          nameCtrl: TextEditingController(text: stop.stopName),
          timeCtrl: TextEditingController(text: stop.arrivalTime),
        ));
      }
      _buses.add(entry);
    }
  }

  void _initEmptyOrExample() {
    _buses.clear();
    // Default starting point: 1 blank bus with 2 stops
    final defaultDeparture =
        _selectedSession == 'morning' ? '07:00 AM' : '04:00 PM';
    final entry = _BusEntry(
      busNumberCtrl: TextEditingController(text: 'S1'),
      routeNameCtrl: TextEditingController(text: 'Route A'),
      departureTimeCtrl: TextEditingController(text: defaultDeparture),
    );
    entry.stops.add(_StopEntry(
      nameCtrl: TextEditingController(text: 'Arapalayam'),
      timeCtrl: TextEditingController(text: defaultDeparture),
    ));
    entry.stops.add(_StopEntry(
      nameCtrl: TextEditingController(text: 'Periyar'),
      timeCtrl: TextEditingController(
          text: _selectedSession == 'morning' ? '07:15 AM' : '04:15 PM'),
    ));
    _buses.add(entry);
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
      _fetchScheduleForSelection();
    }
  }

  void _addBus() {
    setState(() {
      final busCount = _buses.length + 1;
      final defaultTime =
          _selectedSession == 'morning' ? '07:15 AM' : '04:15 PM';
      final entry = _BusEntry(
        busNumberCtrl: TextEditingController(text: 'S$busCount'),
        routeNameCtrl:
            TextEditingController(text: 'Route ${String.fromCharCode(64 + busCount)}'),
        departureTimeCtrl: TextEditingController(text: defaultTime),
      );
      entry.stops.add(_StopEntry(
        nameCtrl: TextEditingController(text: 'Origin Stop'),
        timeCtrl: TextEditingController(text: defaultTime),
      ));
      _buses.add(entry);
    });
  }

  void _removeBus(int index) {
    if (_buses.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one bus is required in the schedule.')),
      );
      return;
    }
    setState(() {
      final removed = _buses.removeAt(index);
      removed.dispose();
    });
  }

  void _addStopToBus(int busIndex) {
    setState(() {
      final bus = _buses[busIndex];
      final lastTime = bus.stops.isNotEmpty
          ? bus.stops.last.timeCtrl.text
          : bus.departureTimeCtrl.text;
      bus.stops.add(_StopEntry(
        nameCtrl: TextEditingController(text: ''),
        timeCtrl: TextEditingController(text: lastTime),
      ));
    });
  }

  void _removeStopFromBus(int busIndex, int stopIndex) {
    setState(() {
      final bus = _buses[busIndex];
      if (bus.stops.length <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Each bus must have at least one stop.')),
        );
        return;
      }
      final removed = bus.stops.removeAt(stopIndex);
      removed.dispose();
    });
  }

  List<DailyBus>? _validateAndCollectBuses() {
    if (_buses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one bus.')),
      );
      return null;
    }

    final result = <DailyBus>[];
    final seenNumbers = <String>{};

    for (int i = 0; i < _buses.length; i++) {
      final b = _buses[i];
      final num = b.busNumberCtrl.text.trim().toUpperCase();
      final route = b.routeNameCtrl.text.trim();
      final depTime = b.departureTimeCtrl.text.trim();

      if (num.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bus #${i + 1} has an empty bus number.')),
        );
        return null;
      }
      if (seenNumbers.contains(num)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Duplicate bus number "$num" found.')),
        );
        return null;
      }
      seenNumbers.add(num);

      if (route.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bus "$num" requires a route name.')),
        );
        return null;
      }
      if (b.stops.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bus "$num" must have at least one stop.')),
        );
        return null;
      }

      final stops = <DailyStop>[];
      for (int j = 0; j < b.stops.length; j++) {
        final s = b.stops[j];
        final sName = s.nameCtrl.text.trim();
        final sTime = s.timeCtrl.text.trim();

        if (sName.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Bus "$num": Stop #${j + 1} name cannot be empty.')),
          );
          return null;
        }

        stops.add(DailyStop(
          stopOrder: j + 1,
          stopName: sName,
          arrivalTime: sTime.isNotEmpty ? sTime : depTime,
        ));
      }

      result.add(DailyBus(
        busNumber: num,
        routeName: route,
        departureTime: depTime.isNotEmpty ? depTime : stops.first.arrivalTime,
        stops: stops,
      ));
    }

    return result;
  }

  Future<void> _saveSchedule({required bool publish}) async {
    final validatedBuses = _validateAndCollectBuses();
    if (validatedBuses == null) return;

    setState(() => _isSaving = true);
    final svc = Provider.of<DailyScheduleService>(context, listen: false);

    try {
      if (_currentSchedule == null) {
        // Create new
        final created = await svc.createDailySchedule(
          date: _dateStr,
          session: _selectedSession,
          status: publish ? 'published' : 'draft',
          buses: validatedBuses,
        );
        setState(() => _currentSchedule = created);
      } else {
        // Update existing
        final updated = await svc.updateDailySchedule(
          _currentSchedule!.id,
          date: _dateStr,
          session: _selectedSession,
          status: publish ? 'published' : _currentSchedule!.status,
          buses: validatedBuses,
        );
        setState(() => _currentSchedule = updated);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.emerald,
          content: Text(
            publish
                ? 'Daily schedule published and visible to students!'
                : 'Daily schedule saved as draft.',
          ),
        ),
      );
      _fetchScheduleForSelection();

      final changeSummary = svc.lastChangeSummary;
      if (changeSummary != null && changeSummary['has_changes'] == true) {
        svc.clearLastChangeSummary();
        _promptScheduleChangeAnnouncement(changeSummary);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text('Failed to save: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteSchedule() async {
    if (_currentSchedule == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Daily Schedule'),
        content: Text(
          'Are you sure you want to delete the ${_selectedSession.toUpperCase()} schedule for $_dateStr?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final svc = Provider.of<DailyScheduleService>(context, listen: false);
      await svc.deleteDailySchedule(_currentSchedule!.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daily schedule deleted successfully.')),
      );
      _fetchScheduleForSelection();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text('Failed to delete: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _previewSchedule() {
    final validatedBuses = _validateAndCollectBuses();
    if (validatedBuses == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ListView(
            controller: scrollCtrl,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  const Icon(Icons.preview_rounded, color: AppColors.emerald),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Schedule Preview',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Text(
                '$_dateStr • ${_selectedSession.toUpperCase()}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ...validatedBuses.map((b) => _buildPreviewBusCard(b)),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _saveSchedule(publish: true);
                },
                icon: const Icon(Icons.send_rounded),
                label: const Text('Looks Good – Publish Schedule'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewBusCard(DailyBus bus) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      elevation: 0,
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
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Bus ${bus.busNumber}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
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
                    color: AppColors.emeraldDark,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            const Text(
              'Route Stops & Timings:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            ...bus.stops.map((s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.emerald,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s.stopName,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        s.arrivalTime,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.navyMid,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final bus in _buses) {
      bus.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Daily Schedule Management'),
        actions: [
          if (_currentSchedule != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              tooltip: 'Delete Schedule',
              onPressed: _isSaving ? null : _deleteSchedule,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                // ── Date & Session Picker Card ───────────────────
                _buildHeaderCard(),

                const SizedBox(height: AppSpacing.md),

                // ── Publication Status Badge (if existing) ───────
                if (_currentSchedule != null) _buildStatusBanner(),

                const SizedBox(height: AppSpacing.md),

                // ── Bus Cards List ──────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Buses (${_buses.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    TextButton.icon(
                      onPressed: _addBus,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Bus'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),

                ...List.generate(
                  _buses.length,
                  (index) => _buildBusEditorCard(index),
                ),

                const SizedBox(height: AppSpacing.lg),

                // ── Action Buttons ──────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _previewSchedule,
                        icon: const Icon(Icons.preview_rounded),
                        label: const Text('Preview'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _isSaving
                            ? null
                            : () => _saveSchedule(publish: false),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save Draft'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  onPressed:
                      _isSaving ? null : () => _saveSchedule(publish: true),
                  icon: const Icon(Icons.publish_rounded),
                  label: Text(
                    _currentSchedule?.isPublished == true
                        ? 'Update Published Schedule'
                        : 'Publish to Students',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
    );
  }

  Widget _buildHeaderCard() {
    final formattedDisplayDate =
        DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate);

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
            const Text(
              'Select Date & Session',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 20, color: AppColors.emerald),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formattedDisplayDate,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Target date: $_dateStr',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down_rounded,
                        color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'morning',
                  label: Text('Morning (To Campus)'),
                  icon: Icon(Icons.wb_sunny_outlined, size: 18),
                ),
                ButtonSegment(
                  value: 'afternoon',
                  label: Text('Afternoon (From Campus)'),
                  icon: Icon(Icons.wb_twilight_rounded, size: 18),
                ),
              ],
              selected: {_selectedSession},
              onSelectionChanged: (set) {
                if (set.isNotEmpty && set.first != _selectedSession) {
                  setState(() => _selectedSession = set.first);
                  _fetchScheduleForSelection();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    final sched = _currentSchedule!;
    final isPub = sched.isPublished;
    final isUpd = sched.isUpdated;

    Color bgColor = isPub
        ? (isUpd ? Colors.amber.shade50 : AppColors.engBg)
        : Colors.grey.shade100;
    Color borderColor = isPub
        ? (isUpd ? Colors.amber.shade300 : AppColors.emerald.withOpacity(0.3))
        : Colors.grey.shade300;
    Color textColor = isPub
        ? (isUpd ? AppColors.amber : AppColors.emeraldDark)
        : AppColors.textSecondary;

    String statusText = isPub
        ? (isUpd ? 'UPDATED & PUBLISHED (Rev v${sched.version})' : 'PUBLISHED TO STUDENTS')
        : 'SAVED AS DRAFT (Not visible to students)';

    String dateDetail = sched.updatedAt != null
        ? 'Last saved: ${DateFormat('MMM d, h:mm a').format(sched.updatedAt!.toLocal())}'
        : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            isPub ? Icons.check_circle_rounded : Icons.edit_note_rounded,
            size: 20,
            color: textColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                if (dateDetail.isNotEmpty)
                  Text(
                    dateDetail,
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

  Widget _buildBusEditorCard(int busIndex) {
    final bus = _buses[busIndex];

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
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.navy,
                  child: Text(
                    '${busIndex + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Bus Details',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent, size: 20),
                  tooltip: 'Remove Bus',
                  onPressed: () => _removeBus(busIndex),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: bus.busNumberCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Bus No.',
                      hintText: 'e.g. S1, M2',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 4,
                  child: TextField(
                    controller: bus.departureTimeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Departure',
                      hintText: 'e.g. 7:00 AM',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: bus.routeNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Route Name / Origin',
                hintText: 'e.g. Route A – Arapalayam to College',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Stops & Arrival Timings (${bus.stops.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _addStopToBus(busIndex),
                  icon: const Icon(Icons.add_location_alt_outlined, size: 16),
                  label: const Text('Add Stop', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            ...List.generate(
              bus.stops.length,
              (stopIdx) => _buildStopRow(busIndex, stopIdx),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopRow(int busIndex, int stopIndex) {
    final stop = _buses[busIndex].stops[stopIndex];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: AppColors.emerald.withOpacity(0.2),
            child: Text(
              '${stopIndex + 1}',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.emeraldDark,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: Autocomplete<String>(
              initialValue: TextEditingValue(text: stop.nameCtrl.text),
              optionsBuilder: (textVal) {
                if (textVal.text.trim().isEmpty) return const [];
                final q = textVal.text.toLowerCase();
                return _knownStopNames
                    .where((s) => s.toLowerCase().contains(q))
                    .take(5);
              },
              onSelected: (val) {
                stop.nameCtrl.text = val;
              },
              fieldViewBuilder:
                  (ctx, textController, focusNode, onFieldSubmitted) {
                textController.addListener(() {
                  stop.nameCtrl.text = textController.text;
                });
                return TextField(
                  controller: textController,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Stop Name',
                    hintText: 'e.g. Teppakulam',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: stop.timeCtrl,
              decoration: const InputDecoration(
                labelText: 'Time',
                hintText: '7:15 AM',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Remove stop',
            onPressed: () => _removeStopFromBus(busIndex, stopIndex),
          ),
        ],
      ),
    );
  }

  // ─── Schedule Change Announcement Prompt ───────────────────────────────────

  Future<void> _promptScheduleChangeAnnouncement(
      Map<String, dynamic> changeSummary) async {
    if (!mounted) return;

    final bullets =
        (changeSummary['change_bullets'] as List<dynamic>?)?.cast<String>() ??
            [];
    final affectedRoutes =
        (changeSummary['affected_routes'] as List<dynamic>?)?.cast<String>() ??
            [];
    final affectedBuses =
        (changeSummary['affected_buses'] as List<dynamic>?)?.cast<String>() ??
            [];
    final suggestedTitle =
        changeSummary['suggested_title'] as String? ?? 'Schedule Change';
    final suggestedMessage =
        changeSummary['suggested_message'] as String? ?? '';

    // Determine initial target
    String initialTargetType = 'all_active';
    String? initialTargetRoute;
    String? initialTargetBus;
    if (affectedRoutes.length == 1) {
      initialTargetType = 'route';
      initialTargetRoute = affectedRoutes.first;
    } else if (affectedBuses.length == 1) {
      initialTargetType = 'bus';
      initialTargetBus = affectedBuses.first;
    }

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.campaign_rounded,
                color: Colors.orange.shade700, size: 22),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Schedule Change Detected',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The following changes were detected. Would you like to notify students?',
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 10),
              if (bullets.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.orange.shade200, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: bullets
                        .map((b) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text('• ',
                                      style: TextStyle(fontSize: 13)),
                                  Expanded(
                                    child: Text(b,
                                        style:
                                            const TextStyle(fontSize: 13)),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              if (affectedRoutes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Affected routes: ${affectedRoutes.join(', ')}',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Dismiss'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.edit_notifications_rounded, size: 18),
            label: const Text('Create Announcement'),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade700),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (proceed == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AnnouncementComposerScreen(
            initialTitle: suggestedTitle,
            initialMessage: suggestedMessage,
            initialCategory: 'Schedule Change',
            initialPriority: 'high',
            initialTargetType: initialTargetType,
            initialTargetRoute: initialTargetRoute,
            initialTargetBus: initialTargetBus,
            scheduleChangeMetadata: changeSummary,
          ),
        ),
      );
    }
  }
}

class _BusEntry {
  final TextEditingController busNumberCtrl;
  final TextEditingController routeNameCtrl;
  final TextEditingController departureTimeCtrl;
  final List<_StopEntry> stops = [];

  _BusEntry({
    required this.busNumberCtrl,
    required this.routeNameCtrl,
    required this.departureTimeCtrl,
  });

  void dispose() {
    busNumberCtrl.dispose();
    routeNameCtrl.dispose();
    departureTimeCtrl.dispose();
    for (final s in stops) {
      s.dispose();
    }
  }
}

class _StopEntry {
  final TextEditingController nameCtrl;
  final TextEditingController timeCtrl;

  _StopEntry({
    required this.nameCtrl,
    required this.timeCtrl,
  });

  void dispose() {
    nameCtrl.dispose();
    timeCtrl.dispose();
  }
}
