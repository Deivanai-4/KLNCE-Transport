import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/schedule.dart';
import '../../services/schedule_service.dart';

class OcrReviewScreen extends StatefulWidget {
  final Schedule schedule;
  const OcrReviewScreen({super.key, required this.schedule});

  @override
  State<OcrReviewScreen> createState() => _OcrReviewScreenState();
}

class _OcrReviewScreenState extends State<OcrReviewScreen> {
  late List<Map<String, dynamic>> _routes;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _routes = widget.schedule.busRoutes.map((r) {
      return {
        'bus_code': r.busCode,
        'departure_time': r.departureTime,
        'route_display_name': r.routeDisplayName ?? '',
        'college': r.college,
        'stops': r.stops.map((s) => s.stopNameEn).toList(),
      };
    }).toList();
  }

  void _addStop(int i) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Add Stop — Bus ${_routes[i]['bus_code']}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Stop name in English or Tamil',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald),
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                setState(() =>
                    (_routes[i]['stops'] as List).add(ctrl.text.trim()));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveDraft() async {
    setState(() => _isSaving = true);
    final svc = Provider.of<ScheduleService>(context, listen: false);
    final ok = await svc.updateDraftRoutes(widget.schedule.id, _routes);
    setState(() => _isSaving = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Draft saved successfully.' : 'Error saving draft.'),
      backgroundColor: ok ? AppColors.emerald : Colors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  Future<void> _publish() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.check_circle_rounded, color: AppColors.emerald, size: 26),
          SizedBox(width: 10),
          Text('Publish Schedule?'),
        ]),
        content: const Text(
          'This will make the verified schedule LIVE for all students and staff. '
          'A notification will be broadcast to all users.\n\nAre you sure you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Review Again'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve & Publish',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isSaving = true);
    final svc = Provider.of<ScheduleService>(context, listen: false);
    await svc.updateDraftRoutes(widget.schedule.id, _routes);
    final published = await svc.publishSchedule(widget.schedule.id);
    setState(() => _isSaving = false);

    if (!mounted) return;
    if (published) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.check_circle, color: AppColors.emerald, size: 28),
            SizedBox(width: 10),
            Text('Published!'),
          ]),
          content: const Text(
              'The schedule is now live. All students can search and view it instantly.'),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('Back to Dashboard'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Column(
        children: [
          // ── Dark Header ─────────────────────────────────────
          Container(
            color: AppColors.navy,
            padding: EdgeInsets.fromLTRB(
                16, MediaQuery.of(context).padding.top + 12, 16, 18),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Verify Schedule',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Review OCR results & corrections',
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (_isSaving)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.emerald),
                    ),
                  )
                else
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Save Draft', style: TextStyle(fontSize: 12)),
                    onPressed: _saveDraft,
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
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
                child: Column(
                  children: [
                    // Guidance banner
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.amber.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.amber.withOpacity(0.35)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.edit_note_rounded,
                              color: AppColors.amber, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Found ${_routes.length} routes. Review and correct any OCR errors before publishing.',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Routes list
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                        itemCount: _routes.length + 1,
                        itemBuilder: (ctx, i) {
                          if (i == _routes.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 20),
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                      color: AppColors.emerald.withOpacity(0.5)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () {
                                  setState(() => _routes.add({
                                        'bus_code': 'NEW',
                                        'departure_time': '08:00',
                                        'route_display_name': '',
                                        'college': 'engineering',
                                        'stops': <String>[],
                                      }));
                                },
                                icon: const Icon(Icons.add_circle_outline,
                                    color: AppColors.emerald),
                                label: const Text('Add Another Bus Route',
                                    style: TextStyle(
                                        color: AppColors.emeraldDark,
                                        fontWeight: FontWeight.w700)),
                              ),
                            );
                          }

                          final route = _routes[i];
                          final stops = route['stops'] as List;
                          final isArts = route['college'] == 'arts_science';
                          final isBoth = route['college'] == 'both';
                          final accentColor = isArts
                              ? AppColors.arts
                              : (isBoth ? AppColors.amber : AppColors.emerald);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    // Bus Code
                                    Container(
                                      width: 80,
                                      decoration: BoxDecoration(
                                        color: accentColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: accentColor.withOpacity(0.3)),
                                      ),
                                      child: TextFormField(
                                        initialValue: route['bus_code'],
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: accentColor,
                                            fontSize: 15),
                                        decoration: const InputDecoration(
                                          labelText: 'Bus',
                                          isDense: true,
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 8),
                                        ),
                                        onChanged: (v) => route['bus_code'] = v,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // Departure time
                                    Expanded(
                                      child: TextFormField(
                                        initialValue: route['departure_time'],
                                        style: const TextStyle(fontSize: 13),
                                        decoration: const InputDecoration(
                                          labelText: 'Departure',
                                          isDense: true,
                                          prefixIcon: Icon(Icons.access_time_rounded,
                                              size: 16),
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 8),
                                        ),
                                        onChanged: (v) =>
                                            route['departure_time'] = v,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // College dropdown
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: (route['college'] == 'arts_science' ||
                                                route['college'] == 'both')
                                            ? route['college'] as String
                                            : 'engineering',
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          labelText: 'Campus',
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 8),
                                        ),
                                        items: const [
                                          DropdownMenuItem(
                                              value: 'engineering',
                                              child: Text('Engg',
                                                  style: TextStyle(fontSize: 12))),
                                          DropdownMenuItem(
                                              value: 'arts_science',
                                              child: Text('Arts',
                                                  style: TextStyle(fontSize: 12))),
                                          DropdownMenuItem(
                                              value: 'both',
                                              child: Text('Both',
                                                  style: TextStyle(fontSize: 12))),
                                        ],
                                        onChanged: (v) {
                                          if (v != null) {
                                            setState(() => route['college'] = v);
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded,
                                          color: Colors.redAccent, size: 20),
                                      onPressed: () =>
                                          setState(() => _routes.removeAt(i)),
                                      tooltip: 'Remove bus',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),

                                // Route name
                                TextFormField(
                                  initialValue:
                                      route['route_display_name'] as String,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: const InputDecoration(
                                    labelText: 'Route Description (Optional)',
                                    isDense: true,
                                    prefixIcon: Icon(Icons.route_outlined, size: 16),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 10),
                                  ),
                                  onChanged: (v) =>
                                      route['route_display_name'] = v,
                                ),
                                const SizedBox(height: 12),

                                // Stops header
                                Row(
                                  children: [
                                    Text('Stops (${stops.length})',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                            color: AppColors.textPrimary)),
                                    const Spacer(),
                                    TextButton.icon(
                                      icon: const Icon(Icons.add, size: 14),
                                      label: const Text('Add Stop',
                                          style: TextStyle(fontSize: 12)),
                                      onPressed: () => _addStop(i),
                                      style: TextButton.styleFrom(
                                        foregroundColor: accentColor,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                      ),
                                    ),
                                  ],
                                ),
                                if (stops.isEmpty)
                                  const Text('No stops extracted — tap Add Stop',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary))
                                else
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: stops.asMap().entries.map((e) {
                                      return InputChip(
                                        label: Text(e.value.toString(),
                                            style: const TextStyle(fontSize: 11)),
                                        deleteIcon: const Icon(Icons.close_rounded,
                                            size: 13),
                                        onDeleted: () => setState(
                                            () => stops.removeAt(e.key)),
                                        backgroundColor:
                                            accentColor.withOpacity(0.08),
                                        labelStyle: TextStyle(
                                            color: accentColor,
                                            fontWeight: FontWeight.w600),
                                        deleteIconColor: accentColor,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          side: BorderSide(
                                              color:
                                                  accentColor.withOpacity(0.25)),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 0),
                                      );
                                    }).toList(),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, -3),
            )
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : _saveDraft,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save Draft'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor: AppColors.emerald,
                  side: const BorderSide(color: AppColors.emerald, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _publish,
                icon: const Icon(Icons.check_circle_rounded, size: 18),
                label: const Text('Publish Schedule',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppColors.emerald,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
