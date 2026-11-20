// lib/screens/admin/announcement_composer_screen.dart
// Stage 9 — Announcement Composer for administrators

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/announcement.dart';
import '../../models/student.dart';
import '../../services/announcement_service.dart';
import '../../services/bus_service.dart';
import '../../services/student_service.dart';

class AnnouncementComposerScreen extends StatefulWidget {
  final Announcement? existingAnnouncement; // For editing drafts
  final String? initialTitle;
  final String? initialMessage;
  final String? initialCategory;
  final String? initialPriority;
  final String? initialTargetType;
  final String? initialTargetRoute;
  final String? initialTargetBus;
  final Map<String, dynamic>? scheduleChangeMetadata;

  const AnnouncementComposerScreen({
    super.key,
    this.existingAnnouncement,
    this.initialTitle,
    this.initialMessage,
    this.initialCategory,
    this.initialPriority,
    this.initialTargetType,
    this.initialTargetRoute,
    this.initialTargetBus,
    this.scheduleChangeMetadata,
  });

  @override
  State<AnnouncementComposerScreen> createState() =>
      _AnnouncementComposerScreenState();
}

class _AnnouncementComposerScreenState
    extends State<AnnouncementComposerScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _messageController;

  late String _selectedCategory;
  late String _selectedPriority;
  late String _selectedTargetType;
  String? _selectedRoute;
  String? _selectedBus;
  List<int> _selectedStudentIds = [];

  bool _sendInApp = true;
  bool _sendSms = false;

  int _recipientCount = 0;
  int _duplicatesPrevented = 0;
  bool _isCalculatingRecipients = false;

  final List<String> _categories = [
    'General Transport Notice',
    'Bus Delay',
    'Bus Cancellation',
    'Route Change',
    'Bus Replacement',
    'Schedule Change',
    'Emergency Notice',
    'Holiday Transport Notice',
  ];

  final List<String> _priorities = ['low', 'normal', 'high', 'emergency'];

  @override
  void initState() {
    super.initState();
    final a = widget.existingAnnouncement;

    _titleController = TextEditingController(
      text: a?.title ?? widget.initialTitle ?? '',
    );
    _messageController = TextEditingController(
      text: a?.message ?? widget.initialMessage ?? '',
    );

    _selectedCategory = a?.category ??
        widget.initialCategory ??
        'General Transport Notice';
    _selectedPriority = a?.priority ?? widget.initialPriority ?? 'normal';
    _selectedTargetType =
        a?.targetType ?? widget.initialTargetType ?? 'all_active';
    _selectedRoute = a?.targetRoute ?? widget.initialTargetRoute;
    _selectedBus = a?.targetBus ?? widget.initialTargetBus;
    _selectedStudentIds = List.from(a?.targetStudentIds ?? []);

    _sendInApp = a?.channels.contains('in_app') ?? true;
    _sendSms = a?.channels.contains('sms') ?? false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRoutesAndBuses();
      _recalculateRecipients();
    });
  }

  Future<void> _loadRoutesAndBuses() async {
    try {
      await Provider.of<BusService>(context, listen: false).fetchAllRoutes();
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _recalculateRecipients() async {
    if (!mounted) return;
    setState(() => _isCalculatingRecipients = true);

    final svc = Provider.of<AnnouncementService>(context, listen: false);
    final res = await svc.previewRecipients(
      targetType: _selectedTargetType,
      targetRoute: _selectedRoute,
      targetBus: _selectedBus,
      targetStudentIds:
          _selectedTargetType == 'selected' ? _selectedStudentIds : null,
    );

    if (!mounted) return;
    setState(() {
      _isCalculatingRecipients = false;
      if (res != null) {
        _recipientCount = (res['total_recipients'] as num?)?.toInt() ?? 0;
        _duplicatesPrevented =
            (res['duplicates_prevented'] as num?)?.toInt() ?? 0;
      }
    });
  }

  Future<void> _pickIndividualStudents() async {
    final studentSvc = Provider.of<StudentService>(context, listen: false);
    await studentSvc.fetchStudents(perPage: 100);
    if (!mounted) return;

    final selected = Set<int>.from(_selectedStudentIds);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      ),
      builder: (modalCtx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final list = studentSvc.students.where((s) {
              if (searchQuery.isEmpty) return true;
              final q = searchQuery.toLowerCase();
              return s.name.toLowerCase().contains(q) ||
                  s.registerNumber.toLowerCase().contains(q) ||
                  s.routeName.toLowerCase().contains(q);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.people_outline_rounded,
                          color: AppColors.navy),
                      const SizedBox(width: 8),
                      Text(
                        'Select Students (${selected.length})',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.emerald),
                        onPressed: () => Navigator.pop(modalCtx),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search name, reg number, route...',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (v) => setModalState(() => searchQuery = v),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final s = list[index];
                        final isSel = selected.contains(s.id);
                        return CheckboxListTile(
                          value: isSel,
                          title: Text(s.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${s.registerNumber} • ${s.routeName} (${s.busNumber})'),
                          activeColor: AppColors.emerald,
                          onChanged: (val) {
                            setModalState(() {
                              if (val == true) {
                                selected.add(s.id);
                              } else {
                                selected.remove(s.id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    setState(() {
      _selectedStudentIds = selected.toList();
    });
    _recalculateRecipients();
  }

  Future<void> _submit({required bool publish}) async {
    if (!_formKey.currentState!.validate()) return;

    if (!_sendInApp && !_sendSms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one delivery channel (In-App or SMS).'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (publish && _sendSms) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.sms_rounded, color: AppColors.emerald),
              SizedBox(width: 8),
              Text('SMS Broadcast Confirmation'),
            ],
          ),
          content: Text(
            'This announcement will be published in the app and an SMS broadcast will be queued.\n\n'
            '• Estimated recipients: $_recipientCount\n'
            '• Channel: Administrator Android SIM\n\n'
            'Do you wish to publish now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Publish & Queue SMS'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    final channels = <String>[];
    if (_sendInApp) channels.add('in_app');
    if (_sendSms) channels.add('sms');

    final payload = <String, dynamic>{
      'title': _titleController.text.trim(),
      'message': _messageController.text.trim(),
      'category': _selectedCategory,
      'priority': _selectedPriority,
      'status': publish ? 'published' : 'draft',
      'target_type': _selectedTargetType,
      'target_route': _selectedTargetType == 'route' ? _selectedRoute : null,
      'target_bus': _selectedTargetType == 'bus' ? _selectedBus : null,
      'target_student_ids':
          _selectedTargetType == 'selected' ? _selectedStudentIds : null,
      'channels': channels,
      'send_sms': _sendSms,
      'schedule_change_metadata': widget.scheduleChangeMetadata ??
          widget.existingAnnouncement?.scheduleChangeMetadata,
    };

    final svc = Provider.of<AnnouncementService>(context, listen: false);
    bool ok = false;

    if (widget.existingAnnouncement != null) {
      ok = await svc.updateAnnouncement(widget.existingAnnouncement!.id, payload);
      if (ok && publish) {
        await svc.publishAnnouncement(widget.existingAnnouncement!.id, sendSms: _sendSms);
      }
    } else {
      final res = await svc.createAnnouncement(payload);
      ok = (res != null);
    }

    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(publish
              ? 'Announcement published successfully.'
              : 'Announcement saved as draft.'),
          backgroundColor: AppColors.emerald,
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${svc.error ?? "Failed to save announcement"}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busSvc = Provider.of<BusService>(context);
    final List<String> availableRoutes = busSvc.routes
        .map((r) => r.routeName)
        .where((r) => r.isNotEmpty)
        .toSet()
        .toList();
    final List<String> availableBuses = busSvc.routes
        .map((r) => r.busCode)
        .where((b) => b.isNotEmpty)
        .toSet()
        .toList();

    final isEmergency = _selectedPriority == 'emergency' ||
        _selectedCategory == 'Emergency Notice';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingAnnouncement != null
            ? 'Edit Announcement'
            : 'New Announcement'),
      ),
      body: Consumer<AnnouncementService>(
        builder: (context, svc, _) {
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Emergency Alert Banner ──────────────────────────────────
                if (isEmergency)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFF87171)),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.warning_rounded, color: Colors.red, size: 24),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'EMERGENCY PRIORITY: This notice will appear pinned with high prominence on student screens.',
                            style: TextStyle(
                              color: Color(0xFF991B1B),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── Title ──────────────────────────────────────────────────
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Announcement Title *',
                    hintText: 'e.g. Bus Delay Notice or Route 1 Change',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title_rounded),
                  ),
                  maxLength: 200,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter an announcement title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // ── Category & Priority Row ────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'Category *',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        items: _categories
                            .map<DropdownMenuItem<String>>((c) => DropdownMenuItem<String>(
                                  value: c,
                                  child: Text(c,
                                      style: const TextStyle(fontSize: 13)),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedCategory = val;
                              if (val == 'Emergency Notice') {
                                _selectedPriority = 'emergency';
                              }
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _selectedPriority,
                        decoration: const InputDecoration(
                          labelText: 'Priority *',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        items: _priorities
                            .map<DropdownMenuItem<String>>((p) => DropdownMenuItem<String>(
                                  value: p,
                                  child: Text(
                                    p.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: p == 'emergency'
                                          ? Colors.red
                                          : p == 'high'
                                              ? Colors.orange
                                              : AppColors.textPrimary,
                                    ),
                                  ),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedPriority = val);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Target Audience Card ───────────────────────────────────
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Target Audience',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('All Active Students'),
                              selected: _selectedTargetType == 'all_active',
                              selectedColor: AppColors.emerald.withValues(alpha: 0.2),
                              onSelected: (_) {
                                setState(() => _selectedTargetType = 'all_active');
                                _recalculateRecipients();
                              },
                            ),
                            ChoiceChip(
                              label: const Text('By Route'),
                              selected: _selectedTargetType == 'route',
                              selectedColor: AppColors.emerald.withValues(alpha: 0.2),
                              onSelected: (_) {
                                setState(() => _selectedTargetType = 'route');
                                _recalculateRecipients();
                              },
                            ),
                            ChoiceChip(
                              label: const Text('By Bus'),
                              selected: _selectedTargetType == 'bus',
                              selectedColor: AppColors.emerald.withValues(alpha: 0.2),
                              onSelected: (_) {
                                setState(() => _selectedTargetType = 'bus');
                                _recalculateRecipients();
                              },
                            ),
                            ChoiceChip(
                              label: Text(
                                  'Selected Students (${_selectedStudentIds.length})'),
                              selected: _selectedTargetType == 'selected',
                              selectedColor: AppColors.emerald.withValues(alpha: 0.2),
                              onSelected: (_) {
                                setState(() => _selectedTargetType = 'selected');
                                _recalculateRecipients();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Sub-selectors based on target type
                        if (_selectedTargetType == 'route') ...[
                          DropdownButtonFormField<String>(
                            value: availableRoutes.contains(_selectedRoute)
                                ? _selectedRoute
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Select Target Route',
                              border: OutlineInputBorder(),
                            ),
                            items: availableRoutes
                                .map<DropdownMenuItem<String>>((r) => DropdownMenuItem<String>(
                                      value: r,
                                      child: Text(r,
                                          style: const TextStyle(fontSize: 13)),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              setState(() => _selectedRoute = val);
                              _recalculateRecipients();
                            },
                          ),
                        ] else if (_selectedTargetType == 'bus') ...[
                          DropdownButtonFormField<String>(
                            value: availableBuses.contains(_selectedBus)
                                ? _selectedBus
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Select Target Bus',
                              border: OutlineInputBorder(),
                            ),
                            items: availableBuses
                                .map<DropdownMenuItem<String>>((b) => DropdownMenuItem<String>(
                                      value: b,
                                      child: Text('Bus $b',
                                          style: const TextStyle(fontSize: 13)),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              setState(() => _selectedBus = val);
                              _recalculateRecipients();
                            },
                          ),
                        ] else if (_selectedTargetType == 'selected') ...[
                          OutlinedButton.icon(
                            onPressed: _pickIndividualStudents,
                            icon: const Icon(Icons.person_add_rounded),
                            label: Text(_selectedStudentIds.isEmpty
                                ? 'Pick Students to Target'
                                : 'Edit Selected Students (${_selectedStudentIds.length})'),
                          ),
                        ],

                        const SizedBox(height: 10),
                        // Live Recipient Count Badge
                        Row(
                          children: [
                            const Icon(Icons.group_outlined,
                                size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 6),
                            _isCalculatingRecipients
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Text(
                                    'Reaching $_recipientCount student(s)' +
                                        (_duplicatesPrevented > 0
                                            ? ' • $_duplicatesPrevented duplicate phone(s) filtered'
                                            : ''),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.emerald,
                                    ),
                                  ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Message Content ────────────────────────────────────────
                TextFormField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    labelText: 'Announcement Message *',
                    hintText: 'Enter full announcement body details...',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 5,
                  onChanged: (_) => setState(() {}),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter the message body';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 4),
                // Character count / SMS segment estimate
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${_messageController.text.length} chars' +
                          (_sendSms
                              ? ' • ~${(_messageController.text.length / 160).ceil().clamp(1, 10)} SMS segment(s)'
                              : ''),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Delivery Channels Card ─────────────────────────────────
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Delivery Channels',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('In-App Announcement',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text(
                              'Displays inside the student application with read/unread tracking.'),
                          value: _sendInApp,
                          activeColor: AppColors.emerald,
                          onChanged: (v) => setState(() => _sendInApp = v ?? true),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('SMS Broadcast (Phone SIM)',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text(
                              'Sends SMS using the administrator Android phone SIM. Requires confirmation before dispatch.'),
                          value: _sendSms,
                          activeColor: AppColors.emerald,
                          onChanged: (v) => setState(() => _sendSms = v ?? false),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Action Buttons ─────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: svc.isSaving ? null : () => _submit(publish: false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Save as Draft'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: svc.isSaving ? null : () => _submit(publish: true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isEmergency
                              ? Colors.red
                              : AppColors.emerald,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: svc.isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          widget.existingAnnouncement?.status == 'published'
                              ? 'Update Published'
                              : 'Publish Announcement',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}
