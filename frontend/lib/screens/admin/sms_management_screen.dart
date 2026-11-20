import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../main.dart';
import '../../models/sms_campaign.dart';
import '../../models/student.dart';
import '../../services/sms_service.dart';
import '../../services/student_service.dart';
import '../../utils/sms_calculator.dart';
import 'sms_campaign_detail_screen.dart';
import 'sms_recipient_preview_screen.dart';
import 'sms_auto_settings_screen.dart';

class SmsManagementScreen extends StatefulWidget {
  const SmsManagementScreen({super.key});

  @override
  State<SmsManagementScreen> createState() => _SmsManagementScreenState();
}

class _SmsManagementScreenState extends State<SmsManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Test SMS State
  final _testPhoneController = TextEditingController();
  final _testMessageController = TextEditingController(
    text: 'KLNCE Transport: This is a test SMS alert from the administrator phone SIM.',
  );
  bool _isSendingTest = false;
  String? _testResultStatus;
  bool _testSuccess = false;

  // Broadcast Campaign State
  final _campaignTitleController = TextEditingController(text: 'Bus Schedule Update');
  final _campaignMessageController = TextEditingController(
    text: 'KLNCE Transport: Evening buses will depart from the main campus gate at 4:30 PM today.',
  );
  String _selectedTargetType = 'all_active'; // 'all_active', 'route', 'bus', 'selected'
  String? _selectedRoute;
  String? _selectedBus;
  final List<int> _selectedStudentIds = [];
  final List<Student> _selectedStudentObjects = [];

  List<Map<String, dynamic>> _targetedRecipients = [];
  bool _isLoadingRecipients = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final smsService = Provider.of<SmsService>(context, listen: false);
      smsService.checkDeviceStatus();
      smsService.loadCampaignHistory();
      _loadTargetRecipients();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _testPhoneController.dispose();
    _testMessageController.dispose();
    _campaignTitleController.dispose();
    _campaignMessageController.dispose();
    super.dispose();
  }

  Future<void> _loadTargetRecipients() async {
    setState(() => _isLoadingRecipients = true);
    final smsService = Provider.of<SmsService>(context, listen: false);
    try {
      final recipients = await smsService.fetchEligibleRecipients(
        target: _selectedTargetType,
        routeName: _selectedRoute,
        busNumber: _selectedBus,
        studentIds: _selectedTargetType == 'selected' ? _selectedStudentIds : null,
      );
      if (!mounted) return;
      setState(() {
        _targetedRecipients = recipients;
        _isLoadingRecipients = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingRecipients = false);
    }
  }

  // ── Searchable Individual Student Picker Modal ──────────────────────────────

  Future<void> _openStudentSelectorModal() async {
    final studentSvc = Provider.of<StudentService>(context, listen: false);
    await studentSvc.fetchStudents(perPage: 100);

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      ),
      builder: (modalCtx) {
        String searchQuery = '';
        final localSelectedIds = Set<int>.from(_selectedStudentIds);

        return StatefulBuilder(
          builder: (context, setModalState) {
            final allStudents = studentSvc.students;
            final filtered = allStudents.where((s) {
              if (searchQuery.isEmpty) return true;
              final q = searchQuery.toLowerCase();
              return s.name.toLowerCase().contains(q) ||
                  s.registerNumber.toLowerCase().contains(q) ||
                  s.routeName.toLowerCase().contains(q) ||
                  s.busNumber.toLowerCase().contains(q);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person_search_rounded, color: AppColors.navy),
                          const SizedBox(width: 8),
                          Text(
                            'Select Students (${localSelectedIds.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(modalCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search by name, register number, route, bus...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (val) {
                      setModalState(() => searchQuery = val);
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.select_all_rounded, size: 16),
                        label: const Text('Select All Filtered', style: TextStyle(fontSize: 12)),
                        onPressed: filtered.isEmpty
                            ? null
                            : () {
                                setModalState(() {
                                  for (final s in filtered) {
                                    localSelectedIds.add(s.id);
                                  }
                                });
                              },
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.deselect_rounded, size: 16),
                        label: const Text('Clear All', style: TextStyle(fontSize: 12)),
                        onPressed: localSelectedIds.isEmpty
                            ? null
                            : () {
                                setModalState(() => localSelectedIds.clear());
                              },
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No students found matching search.'))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, idx) {
                              final st = filtered[idx];
                              final isChecked = localSelectedIds.contains(st.id);
                              final maskedPhone = SmsCalculator.maskPhone(st.studentMobile);

                              return CheckboxListTile(
                                value: isChecked,
                                activeColor: AppColors.emerald,
                                dense: true,
                                title: Text(
                                  st.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                                subtitle: Text(
                                  '${st.registerNumber} • Route: ${st.routeName} (Bus ${st.busNumber}) • $maskedPhone',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onChanged: (val) {
                                  setModalState(() {
                                    if (val == true) {
                                      localSelectedIds.add(st.id);
                                    } else {
                                      localSelectedIds.remove(st.id);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
                    ),
                    onPressed: () {
                      Navigator.pop(modalCtx);
                      setState(() {
                        _selectedStudentIds.clear();
                        _selectedStudentIds.addAll(localSelectedIds);
                        _selectedStudentObjects.clear();
                        _selectedStudentObjects.addAll(
                          allStudents.where((s) => localSelectedIds.contains(s.id)),
                        );
                      });
                      _loadTargetRecipients();
                    },
                    child: Text('Apply Selection (${localSelectedIds.length} Students)'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final smsService = Provider.of<SmsService>(context);
    final status = smsService.deviceStatus;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('SMS Management & Dispatch'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Auto SMS Settings',
            icon: const Icon(Icons.alarm_on_rounded, color: Colors.white),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SmsAutoSettingsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Refresh SIM Status',
            icon: smsService.isCheckingStatus
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: smsService.isCheckingStatus
                ? null
                : () async {
                    await smsService.checkDeviceStatus();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Device SIM and Telephony status refreshed.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.emerald,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          tabs: const [
            Tab(icon: Icon(Icons.edit_note_rounded), text: 'SMS Composer'),
            Tab(icon: Icon(Icons.phonelink_setup_rounded), text: 'SIM & Test'),
            Tab(icon: Icon(Icons.history_rounded), text: 'History & Status'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildComposerTab(smsService),
          _buildSimAndTestTab(smsService, status),
          _buildHistoryTab(smsService),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 1: SMS COMPOSER & RECIPIENT TARGETING
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildComposerTab(SmsService smsService) {
    final status = smsService.deviceStatus;
    final isReady = status.isReady;
    final segInfo = SmsCalculator.calculate(_campaignMessageController.text);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Readiness Banner
          if (!isReady)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: const Color(0xFFFFEEBA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFF856404), size: 28),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SMS Dispatch Readiness Notice',
                          style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF856404)),
                        ),
                        Text(
                          !status.sendSmsGranted
                              ? 'SEND_SMS permission not granted. Open "SIM & Test" tab to grant permission.'
                              : !status.isSimReady
                                  ? 'Active SIM not ready or missing in phone.'
                                  : 'Device does not support cellular telephony.',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF856404)),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _tabController.animateTo(1),
                    child: const Text('Setup', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

          // Active SIM Info Card
          _buildSimSelectionCard(smsService),
          const SizedBox(height: AppSpacing.md),

          // 1. Recipient Targeting Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.people_alt_rounded, color: AppColors.navy, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Target Recipients',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('All Active Students'),
                        selected: _selectedTargetType == 'all_active',
                        selectedColor: AppColors.emerald.withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: _selectedTargetType == 'all_active' ? AppColors.emeraldDark : null,
                          fontWeight: _selectedTargetType == 'all_active' ? FontWeight.bold : null,
                        ),
                        onSelected: (val) {
                          if (val) {
                            setState(() => _selectedTargetType = 'all_active');
                            _loadTargetRecipients();
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('By Route'),
                        selected: _selectedTargetType == 'route',
                        selectedColor: AppColors.emerald.withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: _selectedTargetType == 'route' ? AppColors.emeraldDark : null,
                          fontWeight: _selectedTargetType == 'route' ? FontWeight.bold : null,
                        ),
                        onSelected: (val) {
                          if (val) {
                            setState(() => _selectedTargetType = 'route');
                            _loadTargetRecipients();
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('By Bus'),
                        selected: _selectedTargetType == 'bus',
                        selectedColor: AppColors.emerald.withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: _selectedTargetType == 'bus' ? AppColors.emeraldDark : null,
                          fontWeight: _selectedTargetType == 'bus' ? FontWeight.bold : null,
                        ),
                        onSelected: (val) {
                          if (val) {
                            setState(() => _selectedTargetType = 'bus');
                            _loadTargetRecipients();
                          }
                        },
                      ),
                      ChoiceChip(
                        label: Text('Individual Students (${_selectedStudentIds.length})'),
                        selected: _selectedTargetType == 'selected',
                        selectedColor: AppColors.emerald.withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: _selectedTargetType == 'selected' ? AppColors.emeraldDark : null,
                          fontWeight: _selectedTargetType == 'selected' ? FontWeight.bold : null,
                        ),
                        onSelected: (val) {
                          if (val) {
                            setState(() => _selectedTargetType = 'selected');
                            if (_selectedStudentIds.isEmpty) {
                              _openStudentSelectorModal();
                            } else {
                              _loadTargetRecipients();
                            }
                          }
                        },
                      ),
                    ],
                  ),

                  // Route dropdown if 'route' selected
                  if (_selectedTargetType == 'route') ...[
                    const SizedBox(height: AppSpacing.sm),
                    Consumer<StudentService>(
                      builder: (context, studentSvc, _) {
                        final routes = studentSvc.students
                            .map((s) => s.routeName)
                            .where((r) => r.isNotEmpty)
                            .toSet()
                            .toList();
                        return DropdownButtonFormField<String>(
                          value: _selectedRoute,
                          decoration: const InputDecoration(
                            labelText: 'Select Bus Route',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: routes
                              .map<DropdownMenuItem<String>>((r) => DropdownMenuItem<String>(value: r, child: Text(r)))
                              .toList(),
                          onChanged: (val) {
                            setState(() => _selectedRoute = val);
                            _loadTargetRecipients();
                          },
                        );
                      },
                    ),
                  ],

                  // Bus dropdown if 'bus' selected
                  if (_selectedTargetType == 'bus') ...[
                    const SizedBox(height: AppSpacing.sm),
                    Consumer<StudentService>(
                      builder: (context, studentSvc, _) {
                        final buses = studentSvc.students
                            .map((s) => s.busNumber)
                            .where((b) => b.isNotEmpty)
                            .toSet()
                            .toList();
                        return DropdownButtonFormField<String>(
                          value: _selectedBus,
                          decoration: const InputDecoration(
                            labelText: 'Select Regular Bus',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: buses
                              .map<DropdownMenuItem<String>>((b) => DropdownMenuItem<String>(value: b, child: Text(b)))
                              .toList(),
                          onChanged: (val) {
                            setState(() => _selectedBus = val);
                            _loadTargetRecipients();
                          },
                        );
                      },
                    ),
                  ],

                  // Individual student picker button & chips if 'selected'
                  if (_selectedTargetType == 'selected') ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.navy,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
                          ),
                          icon: const Icon(Icons.person_add_rounded, size: 16),
                          label: const Text('Choose / Edit Students'),
                          onPressed: _openStudentSelectorModal,
                        ),
                        const SizedBox(width: 10),
                        if (_selectedStudentIds.isNotEmpty)
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectedStudentIds.clear();
                                _selectedStudentObjects.clear();
                              });
                              _loadTargetRecipients();
                            },
                            child: const Text('Clear All', style: TextStyle(color: Colors.red, fontSize: 12)),
                          ),
                      ],
                    ),
                    if (_selectedStudentObjects.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _selectedStudentObjects.take(8).map((st) {
                          return Chip(
                            label: Text('${st.name} (${st.registerNumber})', style: const TextStyle(fontSize: 11)),
                            deleteIcon: const Icon(Icons.close, size: 14),
                            onDeleted: () {
                              setState(() {
                                _selectedStudentIds.remove(st.id);
                                _selectedStudentObjects.remove(st);
                              });
                              _loadTargetRecipients();
                            },
                          );
                        }).toList(),
                      ),
                      if (_selectedStudentObjects.length > 8)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '+ ${_selectedStudentObjects.length - 8} more student(s) selected',
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                          ),
                        ),
                    ],
                  ],

                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.engBg,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _isLoadingRecipients
                            ? const Row(
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                  SizedBox(width: 8),
                                  Text('Counting eligible students...', style: TextStyle(fontSize: 13)),
                                ],
                              )
                            : Text(
                                'Eligible Recipients: ${_targetedRecipients.length} students',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.emeraldDark,
                                  fontSize: 13,
                                ),
                              ),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 18),
                          onPressed: _loadTargetRecipients,
                          tooltip: 'Refresh count',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 2. Message Composer Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.edit_note_rounded, color: AppColors.navy, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Compose SMS Alert',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  TextField(
                    controller: _campaignTitleController,
                    decoration: const InputDecoration(
                      labelText: 'Campaign / Alert Title',
                      hintText: 'e.g. Bus S1 Delay Notice',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _campaignMessageController,
                    maxLines: 4,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'SMS Content (English / தமிழ்)',
                      hintText: 'Enter student notification text...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Accurate Segment & Character Counter Box
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${segInfo.charCount} chars',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: segInfo.isUnicode ? AppColors.amber.withOpacity(0.15) : AppColors.engBg,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    segInfo.encoding,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: segInfo.isUnicode ? AppColors.amberDark : AppColors.navy,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${segInfo.segments} SMS segment${segInfo.segments == 1 ? '' : 's'} / student',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: segInfo.segments > 1 ? AppColors.amberDark : AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${segInfo.remainingInSegment} characters remaining in current segment',
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                            Text(
                              'Total units: ${segInfo.totalSms(_targetedRecipients.length)} SMS',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.navy),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // Quick Template Chips
                  const Text(
                    'Quick Templates:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ActionChip(
                        label: const Text('Bus Delayed 15m', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          setState(() {
                            _campaignTitleController.text = 'Bus Delay Notice';
                            _campaignMessageController.text =
                                'KLNCE Transport: Bus ${_selectedBus ?? 'S1'} is delayed by 15 minutes due to traffic. Please wait at your boarding stop.';
                          });
                        },
                      ),
                      ActionChip(
                        label: const Text('Schedule Published', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          setState(() {
                            _campaignTitleController.text = 'Daily Schedule Published';
                            _campaignMessageController.text =
                                'KLNCE Transport: Bus schedule for today is published. Please check the KLNCE Transport app for departure timings.';
                          });
                        },
                      ),
                      ActionChip(
                        label: const Text('Route Update', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          setState(() {
                            _campaignTitleController.text = 'Bus Route Update';
                            _campaignMessageController.text =
                                'KLNCE Transport Alert: Route ${_selectedRoute ?? 'A'} will operate via alternative stops today. Check app for details.';
                          });
                        },
                      ),
                      ActionChip(
                        label: const Text('Tamil Alert (தமிழ்)', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          setState(() {
                            _campaignTitleController.text = 'பேருந்து அறிவிப்பு (Bus Alert)';
                            _campaignMessageController.text =
                                'KLNCE போக்குவரத்து அறிவிப்பு: இன்றைய பேருந்து அட்டவணை வெளியிடப்பட்டுள்ளது. செயலில் பார்க்கவும்.';
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 3. Phone Simulation Message Preview Widget (Requirement 1: Preview before sending)
          _buildPhoneMessagePreview(),
          const SizedBox(height: AppSpacing.lg),

          // 4. Action Button: Review Recipients & Proceed
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
              elevation: 2,
            ),
            icon: const Icon(Icons.preview_rounded),
            label: Text(
              'Review Recipients & Proceed (${_targetedRecipients.length} Students)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            onPressed: _targetedRecipients.isEmpty || _campaignMessageController.text.trim().isEmpty
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SmsRecipientPreviewScreen(
                          title: _campaignTitleController.text.trim(),
                          message: _campaignMessageController.text.trim(),
                          targetType: _selectedTargetType,
                          routeName: _selectedRoute,
                          busNumber: _selectedBus,
                          selectedStudentIds: _selectedTargetType == 'selected' ? _selectedStudentIds : null,
                        ),
                      ),
                    );
                  },
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  /// Interactive visual phone mockup showing how the message looks on student's mobile screen.
  Widget _buildPhoneMessagePreview() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
      elevation: 1,
      color: const Color(0xFFF8FAFC),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.smartphone_rounded, color: AppColors.navy, size: 20),
                SizedBox(width: 8),
                Text(
                  'Message Preview (Student Handset View)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                children: [
                  // Phone Status Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.md)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('12:30 PM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        Row(
                          children: [
                            Icon(Icons.signal_cellular_alt_rounded, size: 12),
                            SizedBox(width: 4),
                            Icon(Icons.battery_std_rounded, size: 12),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Chat / SMS Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: AppColors.navy,
                    child: const Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.white24,
                          child: Icon(Icons.directions_bus_rounded, size: 14, color: Colors.white),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'KLNCE Transport Alert',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              Text(
                                'SMS Broadcast Gateway',
                                style: TextStyle(color: Colors.white70, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Message Bubble
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: const Color(0xFFF1F5F9),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 280),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_campaignTitleController.text.isNotEmpty)
                              Text(
                                _campaignTitleController.text,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.navy),
                              ),
                            const SizedBox(height: 2),
                            Text(
                              _campaignMessageController.text.isNotEmpty
                                  ? _campaignMessageController.text
                                  : 'Message text will appear here...',
                              style: const TextStyle(fontSize: 12, height: 1.3),
                            ),
                            const SizedBox(height: 4),
                            const Align(
                              alignment: Alignment.bottomRight,
                              child: Text(
                                'Just now • Delivered',
                                style: TextStyle(fontSize: 9, color: Colors.grey),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 2: SIM CARDS, TELEPHONY & TEST SMS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSimAndTestTab(SmsService smsService, DeviceTelephonyStatus status) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Device Telephony Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.phone_android_rounded, color: AppColors.navy, size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Administrator Device Status',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: status.isReady
                              ? const Color(0xFFE8F5E9)
                              : const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                        child: Text(
                          status.isReady ? 'READY' : 'ACTION REQUIRED',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: status.isReady
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFC62828),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _buildStatusRow('Phone Model', status.deviceModel),
                  _buildStatusRow('Telephony Hardware', status.hasTelephony ? 'Supported' : 'No Cellular Radio', isSuccess: status.hasTelephony),
                  _buildStatusRow('SIM Card State', status.simState, isSuccess: status.isSimReady),
                  _buildStatusRow('SEND_SMS Permission', status.sendSmsGranted ? 'Granted' : 'Not Granted', isSuccess: status.sendSmsGranted),
                  _buildStatusRow('READ_PHONE_STATE Permission', status.readPhoneStateGranted ? 'Granted' : 'Not Granted', isSuccess: status.readPhoneStateGranted),

                  if (!status.sendSmsGranted || !status.readPhoneStateGranted) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
                      ),
                      icon: const Icon(Icons.security_rounded, size: 18),
                      label: const Text('Request SMS & Phone Permissions'),
                      onPressed: () async {
                        final granted = await smsService.requestPermissions();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                granted
                                    ? 'SMS permissions granted successfully.'
                                    : 'Permissions were not granted.',
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Dual SIM Selection Card
          _buildSimSelectionCard(smsService),
          const SizedBox(height: AppSpacing.md),

          // Test SMS Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.network_check_rounded, color: AppColors.emerald, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Test SMS Dispatch',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  const Text(
                    'Verify that your phone SIM and mobile carrier can send SMS before broadcasting to students.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _testPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Test Mobile Number (10 digits)',
                      hintText: 'e.g. 9876543210',
                      prefixText: '+91 ',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _testMessageController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Test Message',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  if (_testResultStatus != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _testSuccess
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _testSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
                            color: _testSuccess ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _testResultStatus!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _testSuccess
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFFC62828),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navyMid,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
                    ),
                    icon: _isSendingTest
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_to_mobile_rounded, size: 18),
                    label: Text(_isSendingTest ? 'Sending Test SMS...' : 'Confirm & Send Test SMS'),
                    onPressed: _isSendingTest ? null : () => _sendTestSms(smsService),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Google Play Policy Notice Accordion / Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            elevation: 1,
            color: const Color(0xFFF8FAFC),
            child: ExpansionTile(
              initiallyExpanded: false,
              leading: const Icon(Icons.info_outline_rounded, color: AppColors.arts),
              title: const Text(
                'Google Play Policy & Technical Architecture',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              subtitle: const Text(
                'Direct SIM sending vs Google Play requirements',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              childrenPadding: const EdgeInsets.all(AppSpacing.md),
              children: [
                const Text(
                  '1. Native SIM Dispatch (Current Mode):\n'
                  'Uses Android SmsManager directly from the administrator\'s phone SIM card. '
                  'Requires SEND_SMS permission. Ideal for enterprise APKs distributed privately to college staff.\n\n'
                  '2. Google Play Store Compliance Policy:\n'
                  'Google Play policies restrict SEND_SMS permission exclusively to apps configured as the default SMS handler. '
                  'For Play Store distribution, this system provides the compliant system SMS Intent (ACTION_SENDTO) fallback.\n\n'
                  '3. "Sent to Android SMS Service" vs Cellular Delivery:\n'
                  'When the phone successfully submits the message to the cellular modem, the status is marked as "Sent to Android SMS service". '
                  'Handset-level carrier delivery reports depend on network availability and carrier routing.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(Icons.launch_rounded, size: 16),
                  label: const Text('Test Fallback System Intent (ACTION_SENDTO)'),
                  onPressed: () {
                    final phone = _testPhoneController.text.trim();
                    smsService.sendSmsViaIntent(
                      phoneNumber: phone.isNotEmpty ? phone : '9876543210',
                      message: _testMessageController.text,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 3: CAMPAIGN DISPATCH HISTORY & STATUS TRACKING
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHistoryTab(SmsService smsService) {
    final campaigns = smsService.campaigns;

    if (campaigns.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_toggle_off_rounded, size: 64, color: AppColors.textSecondary.withOpacity(0.5)),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'No SMS campaigns dispatched yet.',
              style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Sent SMS alerts will be catalogued here with full recipient audits.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: campaigns.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final c = campaigns[index];
        final isComplete = c.status == 'completed';
        final isPartiallyFailed = c.status == 'partially_failed';
        final badgeColor = isComplete
            ? const Color(0xFF2E7D32)
            : isPartiallyFailed
                ? AppColors.amber
                : AppColors.navy;

        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
          elevation: 1,
          child: ExpansionTile(
            title: Text(
              c.title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            subtitle: Text(
              '${c.targetDisplay} • ${c.createdAt != null ? c.createdAt!.toLocal().toString().split('.')[0] : ''}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: Text(
                c.statusDisplay,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: badgeColor,
                ),
              ),
            ),
            childrenPadding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Message Text:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                    const SizedBox(height: 2),
                    Text(c.message, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatBadge('Total', '${c.totalRecipients}', Colors.grey),
                  _buildStatBadge('Submitted', '${c.submittedCount}', const Color(0xFF2E7D32)),
                  _buildStatBadge('Delivered', '${c.deliveryConfirmedCount}', const Color(0xFF1B5E20)),
                  _buildStatBadge('Failed', '${c.failedCount}', const Color(0xFFC62828)),
                  _buildStatBadge('Pending', '${c.pendingCount}', Colors.blueGrey),
                ],
              ),
              if (c.senderDevice.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Sender: ${c.senderDevice['device_model'] ?? 'Android'} • ${c.senderDevice['carrier'] ?? 'SIM'} (Slot ${c.senderDevice['sim_slot'] ?? 0})',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              // Button to open full message status tracking
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
                ),
                icon: const Icon(Icons.manage_search_rounded, size: 18),
                label: const Text('View Message Status & Audit Log'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SmsCampaignDetailScreen(campaignId: c.id),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSimSelectionCard(SmsService smsService) {
    final status = smsService.deviceStatus;
    final cards = status.simCards;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.sim_card_rounded, color: AppColors.emerald, size: 20),
                SizedBox(width: 8),
                Text(
                  'Active SIM Selection',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ],
            ),
            const Divider(height: 20),
            if (cards.isEmpty)
              const Text(
                'No active SIM detected or READ_PHONE_STATE permission pending.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              )
            else ...[
              const Text(
                'Select which physical SIM slot on your phone will send the SMS:',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              for (int i = 0; i < cards.length; i++)
                RadioListTile<int>(
                  value: i,
                  groupValue: smsService.selectedSimIndex,
                  onChanged: (val) {
                    if (val != null) smsService.selectSimIndex(val);
                  },
                  dense: true,
                  activeColor: AppColors.emerald,
                  title: Text(
                    cards[i].slotLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Carrier: ${cards[i].carrierName} • Sub ID: ${cards[i].subscriptionId}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, {bool? isSuccess}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          Row(
            children: [
              if (isSuccess != null)
                Icon(
                  isSuccess ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  size: 14,
                  color: isSuccess ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                ),
              if (isSuccess != null) const SizedBox(width: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSuccess == null
                      ? AppColors.textPrimary
                      : (isSuccess ? const Color(0xFF2E7D32) : const Color(0xFFC62828)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Future<void> _sendTestSms(SmsService smsService) async {
    final phone = _testPhoneController.text.trim();
    final message = _testMessageController.text.trim();

    if (phone.isEmpty || phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 10-digit mobile number')),
      );
      return;
    }
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Test message cannot be empty')),
      );
      return;
    }

    // Require Administrator Confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Test SMS Dispatch'),
        content: Text(
          'A test SMS will be dispatched immediately from your phone\'s '
          '${smsService.selectedSim?.slotLabel ?? 'SIM'} to +91 $phone.\n\n'
          'Standard carrier SMS charges (or balance) may apply.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send Test SMS'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isSendingTest = true;
      _testResultStatus = null;
    });

    try {
      final campaign = await smsService.createCampaign(
        title: 'Admin Test SMS',
        message: message,
        targetType: 'test',
        testPhone: phone,
      );

      final result = await smsService.sendSingleDirectSms(
        phoneNumber: phone,
        message: message,
      );

      final isSuccess = result['success'] == true;
      setState(() {
        _testSuccess = isSuccess;
        _testResultStatus = isSuccess
            ? 'Success: Sent to Android SMS service via ${smsService.selectedSim?.carrierName ?? 'SIM'}'
            : 'Dispatch Failed: ${result['error'] ?? 'Unknown carrier error'}';
      });

      await smsService.dispatchCampaign(
        campaign: campaign,
        onProgress: (_, __, ___, ____) {},
      );
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResultStatus = 'Error: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isSendingTest = false);
      }
    }
  }
}
