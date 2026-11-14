import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../main.dart';
import '../../services/schedule_service.dart';
import 'ocr_review_screen.dart';

class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  final _titleController = TextEditingController();
  String _tripDirection = 'incoming';
  String _college = 'both';
  DateTime _effectiveDate = DateTime.now();
  final List<Map<String, dynamic>> _routes = [];
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _addNewBusRow() {
    setState(() {
      _routes.add({
        'bus_code': '',
        'departure_time': '',
        'route_name': '',
        'college': _college == 'arts_science' ? 'arts_science' : 'engineering',
        'stops_text': '',
      });
    });
  }

  Future<void> _pickEffectiveDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _effectiveDate = picked);
    }
  }

  Future<void> _proceedToReview() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showMessage('Enter a schedule title.');
      return;
    }
    if (_routes.isEmpty) {
      _showMessage('Add at least one route.');
      return;
    }

    final routes = <Map<String, dynamic>>[];
    for (var index = 0; index < _routes.length; index++) {
      final route = _routes[index];
      final busCode = (route['bus_code'] as String).trim();
      final departureTime = (route['departure_time'] as String).trim();
      final stops = (route['stops_text'] as String)
          .split(',')
          .map((stop) => stop.trim())
          .where((stop) => stop.isNotEmpty)
          .toList();

      if (busCode.isEmpty || departureTime.isEmpty) {
        _showMessage('Enter a bus code and departure time for route ${index + 1}.');
        return;
      }
      if (stops.isEmpty) {
        _showMessage('Add at least one stop to route ${index + 1}.');
        return;
      }

      routes.add({
        'bus_code': busCode,
        'departure_time': departureTime,
        'route_display_name': (route['route_name'] as String).trim(),
        'college': route['college'],
        'stops': stops,
      });
    }

    setState(() => _isSaving = true);
    final service = context.read<ScheduleService>();
    final effectiveDate = DateFormat('yyyy-MM-dd').format(_effectiveDate);
    final draft = await service.createManualSchedule(
      title: title,
      tripDirection: _tripDirection,
      college: _college,
      effectiveDate: effectiveDate,
      routes: routes,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (draft == null) {
      _showMessage(service.errorMessage ?? 'Could not save this schedule.');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OcrReviewScreen(schedule: draft),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Manual timetable'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _proceedToReview,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Review'),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            'Create a schedule',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Enter verified timetable details. The schedule remains a draft until it is reviewed and published.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _titleController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Schedule title',
              hintText: 'For example, Semester bus schedule',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'incoming',
                label: Text('To campus'),
              ),
              ButtonSegment(
                value: 'outgoing',
                label: Text('From campus'),
              ),
            ],
            selected: {_tripDirection},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) {
                setState(() => _tripDirection = selection.first);
              }
            },
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _college,
            decoration: const InputDecoration(labelText: 'Campus'),
            items: const [
              DropdownMenuItem(
                value: 'both',
                child: Text('Both campuses'),
              ),
              DropdownMenuItem(
                value: 'engineering',
                child: Text('Engineering'),
              ),
              DropdownMenuItem(
                value: 'arts_science',
                child: Text('Arts & Science'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _college = value);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          InkWell(
            onTap: _pickEffectiveDate,
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Effective date',
                prefixIcon: Icon(Icons.calendar_today_outlined),
              ),
              child: Text(DateFormat('d MMMM yyyy').format(_effectiveDate)),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Routes (${_routes.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _addNewBusRow,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add bus'),
              ),
            ],
          ),
          if (_routes.isEmpty)
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                'No routes added. Add a bus to enter its departure time and stops.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ..._routes.asMap().entries.map((entry) {
            final index = entry.key;
            final route = entry.value;
            return _RouteEditorCard(
              key: ValueKey(route),
              index: index,
              route: route,
              onRemove: () => setState(() => _routes.removeAt(index)),
            );
          }),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _proceedToReview,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: Text(_isSaving ? 'Saving draft' : 'Save draft and review'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteEditorCard extends StatelessWidget {
  final int index;
  final Map<String, dynamic> route;
  final VoidCallback onRemove;

  const _RouteEditorCard({
    super.key,
    required this.index,
    required this.route,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Route ${index + 1}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                onPressed: onRemove,
                tooltip: 'Remove route',
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: route['bus_code'] as String,
                  decoration: const InputDecoration(
                    labelText: 'Bus code',
                    hintText: 'K or S1',
                  ),
                  onChanged: (value) => route['bus_code'] = value,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextFormField(
                  initialValue: route['departure_time'] as String,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(
                    labelText: 'Departure',
                    hintText: '08:00',
                  ),
                  onChanged: (value) => route['departure_time'] = value,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: route['college'] as String,
            decoration: const InputDecoration(labelText: 'Assigned campus'),
            items: const [
              DropdownMenuItem(
                value: 'engineering',
                child: Text('Engineering'),
              ),
              DropdownMenuItem(
                value: 'arts_science',
                child: Text('Arts & Science'),
              ),
            ],
            onChanged: (value) {
              if (value != null) route['college'] = value;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            initialValue: route['route_name'] as String,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Route name',
              hintText: 'Optional',
            ),
            onChanged: (value) => route['route_name'] = value,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            initialValue: route['stops_text'] as String,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Stops in order',
              hintText: 'Separate stops with commas',
              alignLabelWithHint: true,
            ),
            onChanged: (value) => route['stops_text'] = value,
          ),
        ],
      ),
    );
  }
}
