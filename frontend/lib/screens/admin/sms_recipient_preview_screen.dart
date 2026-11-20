import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../main.dart';
import '../../models/sms_campaign.dart';
import '../../services/sms_service.dart';
import '../../utils/sms_calculator.dart';
import 'sms_campaign_detail_screen.dart';

/// Recipient Preview and Confirmation Flow for SMS Broadcast.
/// Stage 7 Requirements:
/// 1. Recipient Preview (Category, Route/Bus, Valid/Invalid/Duplicate counts,
///    Duplicate prevention safeguard, Masked mobile numbers).
/// 2. Confirmation Screen (Message content, Recipient category, Total SMS count,
///    Estimated SMS segments, Selected SIM, Sending device).
/// 3. Live bulk sending and status tracking.
class SmsRecipientPreviewScreen extends StatefulWidget {
  final String title;
  final String message;
  final String targetType; // 'all_active', 'route', 'bus', 'selected'
  final String? routeName;
  final String? busNumber;
  final List<int>? selectedStudentIds;

  const SmsRecipientPreviewScreen({
    super.key,
    required this.title,
    required this.message,
    required this.targetType,
    this.routeName,
    this.busNumber,
    this.selectedStudentIds,
  });

  @override
  State<SmsRecipientPreviewScreen> createState() => _SmsRecipientPreviewScreenState();
}

class _SmsRecipientPreviewScreenState extends State<SmsRecipientPreviewScreen> {
  int _currentStep = 0; // 0 = Recipient Preview, 1 = Confirmation
  bool _isLoadingPreview = true;
  String? _previewError;
  SmsRecipientPreview? _preview;

  // Duplicate Prevention State
  bool _allowDuplicates = false;

  // Live Dispatch State
  bool _isDispatching = false;
  int _dispatchSent = 0;
  int _dispatchFailed = 0;
  int _dispatchTotal = 0;
  String _currentLog = 'Preparing dispatch session...';
  final List<String> _liveLogs = [];
  SmsCampaign? _activeCampaign;

  @override
  void initState() {
    super.initState();
    _loadRecipientPreview();
  }

  Future<void> _loadRecipientPreview() async {
    setState(() {
      _isLoadingPreview = true;
      _previewError = null;
    });

    final smsService = Provider.of<SmsService>(context, listen: false);
    try {
      final p = await smsService.fetchRecipientPreview(
        target: widget.targetType,
        routeName: widget.routeName,
        busNumber: widget.busNumber,
        studentIds: widget.selectedStudentIds,
        allowDuplicates: _allowDuplicates,
      );
      if (!mounted) return;
      setState(() {
        _preview = p;
        _isLoadingPreview = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _previewError = 'Failed to load recipient preview: $e';
        _isLoadingPreview = false;
      });
    }
  }

  void _onToggleDuplicates(bool? value) {
    if (value == null) return;
    if (value == true) {
      // Explicit Approval Prompt
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.amber),
              SizedBox(width: 8),
              Text('Approve Duplicate SMS?'),
            ],
          ),
          content: const Text(
            'By approving duplicates, students or siblings sharing the same mobile number '
            'will each receive a separate SMS message.\n\n'
            'Are you sure you want to approve sending duplicate messages to shared numbers?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep Deduplication (Recommended)'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.amberDark),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Approve Duplicates'),
            ),
          ],
        ),
      ).then((approved) {
        if (approved == true) {
          setState(() => _allowDuplicates = true);
          _loadRecipientPreview();
        }
      });
    } else {
      setState(() => _allowDuplicates = false);
      _loadRecipientPreview();
    }
  }

  // ── Dispatch Initiation ────────────────────────────────────────────────────

  Future<void> _startBulkDispatch(SmsService smsService) async {
    if (_preview == null || _preview!.effectiveRecipientCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid recipients available for dispatch.')),
      );
      return;
    }

    setState(() {
      _isDispatching = true;
      _dispatchSent = 0;
      _dispatchFailed = 0;
      _dispatchTotal = _preview!.effectiveRecipientCount;
      _currentLog = 'Creating campaign in database...';
      _liveLogs.clear();
    });

    try {
      // 1. Create Campaign in MongoDB
      final campaign = await smsService.createCampaign(
        title: widget.title,
        message: widget.message,
        targetType: widget.targetType,
        routeName: widget.routeName,
        busNumber: widget.busNumber,
        selectedStudentIds: widget.selectedStudentIds,
        allowDuplicates: _allowDuplicates,
        deliveryMethod: 'direct_sim',
      );

      _activeCampaign = campaign;
      if (!mounted) return;

      // 2. Open Live Progress Dialog
      _showLiveProgressModal(smsService, campaign);

      // 3. Dispatch sequentially via physical SIM
      await smsService.dispatchCampaign(
        campaign: campaign,
        onProgress: (sent, failed, total, logMsg) {
          if (!mounted) return;
          setState(() {
            _dispatchSent = sent;
            _dispatchFailed = failed;
            _dispatchTotal = total;
            _currentLog = logMsg;
            _liveLogs.insert(0, logMsg);
            if (_liveLogs.length > 50) _liveLogs.removeLast();
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDispatching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to initiate bulk sending: $e')),
      );
    }
  }

  void _showLiveProgressModal(SmsService smsService, SmsCampaign campaign) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final double progress = _dispatchTotal > 0
                ? (_dispatchSent + _dispatchFailed) / _dispatchTotal
                : 0.0;
            final isDone = (_dispatchSent + _dispatchFailed) >= _dispatchTotal && _dispatchTotal > 0;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
              title: Row(
                children: [
                  Icon(
                    isDone ? Icons.check_circle_rounded : Icons.cell_tower_rounded,
                    color: isDone ? const Color(0xFF2E7D32) : AppColors.emerald,
                  ),
                  const SizedBox(width: 8),
                  Text(isDone ? 'Dispatch Finished' : 'Dispatching SMS via SIM'),
                ],
              ),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.emerald),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Progress: ${(progress * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('$_dispatchSent / $_dispatchTotal submitted', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatBox('Submitted', '$_dispatchSent', const Color(0xFF2E7D32)),
                        _buildStatBox('Failed', '$_dispatchFailed', const Color(0xFFC62828)),
                        _buildStatBox('Remaining', '${_dispatchTotal - _dispatchSent - _dispatchFailed}', Colors.grey.shade700),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _currentLog,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.navy),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 120,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: _liveLogs.isEmpty
                          ? const Center(child: Text('Connecting to Android SMS service...', style: TextStyle(fontSize: 11)))
                          : ListView.builder(
                              reverse: true,
                              itemCount: _liveLogs.length,
                              itemBuilder: (ctx, idx) => Text(
                                _liveLogs[idx],
                                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (!isDone) ...[
                  TextButton.icon(
                    icon: Icon(smsService.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                    label: Text(smsService.isPaused ? 'Resume' : 'Pause'),
                    onPressed: () {
                      if (smsService.isPaused) {
                        smsService.resumeDispatch(
                          campaign: campaign,
                          onProgress: (s, f, t, log) {
                            if (mounted) {
                              setState(() {
                                _dispatchSent = s;
                                _dispatchFailed = f;
                                _dispatchTotal = t;
                                _currentLog = log;
                                _liveLogs.insert(0, log);
                              });
                            }
                          },
                        );
                      } else {
                        smsService.pauseDispatch();
                      }
                      setDialogState(() {});
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 16),
                    label: const Text('Cancel Pending', style: TextStyle(color: Colors.red, fontSize: 12)),
                    onPressed: () async {
                      await smsService.cancelPendingDispatch(campaign);
                      setDialogState(() {});
                    },
                  ),
                ],
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy),
                  onPressed: isDone
                      ? () {
                          Navigator.pop(dialogCtx); // close dialog
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SmsCampaignDetailScreen(campaignId: campaign.id),
                            ),
                          );
                        }
                      : null,
                  child: Text(isDone ? 'View Status Tracking' : 'Please wait...'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStatBox(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final smsService = Provider.of<SmsService>(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(_currentStep == 0 ? 'Recipient Preview' : 'Confirm SMS Broadcast'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: _isLoadingPreview
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Analyzing recipients & validating mobile numbers...'),
                ],
              ),
            )
          : _previewError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_previewError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadRecipientPreview,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
              : _currentStep == 0
                  ? _buildRecipientPreviewStep(smsService)
                  : _buildConfirmationStep(smsService),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 1: RECIPIENT PREVIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRecipientPreviewStep(SmsService smsService) {
    final p = _preview!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Recipient Category Banner
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            elevation: 1,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.category_rounded, color: AppColors.navy, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          p.recipientCategory,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.navy.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                        child: Text(
                          widget.targetType.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (p.routeName != null || p.busNumber != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (p.routeName != null)
                          Chip(
                            avatar: const Icon(Icons.alt_route_rounded, size: 16),
                            label: Text('Route: ${p.routeName}'),
                            backgroundColor: AppColors.engBg,
                            padding: EdgeInsets.zero,
                          ),
                        if (p.busNumber != null)
                          Chip(
                            avatar: const Icon(Icons.directions_bus_rounded, size: 16),
                            label: Text('Bus: ${p.busNumber}'),
                            backgroundColor: AppColors.artsBg,
                            padding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 2. Metrics Cards Row (Total, Valid, Invalid, Duplicate)
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: 'Total Students',
                  count: p.totalSelectedStudents,
                  color: AppColors.navy,
                  icon: Icons.groups_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpiCard(
                  title: 'Valid Mobile',
                  count: p.validCount,
                  color: const Color(0xFF2E7D32),
                  icon: Icons.check_circle_outline_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: 'Invalid Mobile',
                  count: p.invalidCount,
                  color: const Color(0xFFC62828),
                  icon: Icons.error_outline_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpiCard(
                  title: 'Duplicate Numbers',
                  count: p.duplicateCount,
                  color: AppColors.amberDark,
                  icon: Icons.copy_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // 3. Duplicate Prevention Safeguard Box
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            elevation: 1,
            color: _allowDuplicates ? const Color(0xFFFFF9C4) : const Color(0xFFF1F8E9),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _allowDuplicates ? Icons.warning_rounded : Icons.shield_rounded,
                        color: _allowDuplicates ? AppColors.amberDark : const Color(0xFF2E7D32),
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _allowDuplicates ? 'Duplicate Sending Approved' : 'Duplicate Prevention Active',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _allowDuplicates ? AppColors.amberDark : const Color(0xFF2E7D32),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _allowDuplicates
                        ? '⚠️ Duplicates are approved. All ${p.validCount} student entries will receive an SMS, even if multiple students share the same mobile number.'
                        : 'Protection Active: Only 1 SMS will be sent per unique mobile number. '
                            '(${p.duplicatesPrevented} duplicate messages prevented).',
                    style: TextStyle(
                      fontSize: 12,
                      color: _allowDuplicates ? Colors.brown.shade900 : const Color(0xFF1B5E20),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: AppColors.amberDark,
                    title: const Text(
                      'Allow duplicate messages to shared numbers (Explicit approval)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    value: _allowDuplicates,
                    onChanged: _onToggleDuplicates,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 4. Effective Recipient Count Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.navy.withOpacity(0.06),
              borderRadius: BorderRadius.circular(AppRadii.sm),
              border: Border.all(color: AppColors.navy.withOpacity(0.15)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Effective Recipients to Message:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  '${p.effectiveRecipientCount} students',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 5. Expandable Recipient Detail Lists (Privacy Protected)
          _buildRecipientInspectors(p),
          const SizedBox(height: AppSpacing.lg),

          // 6. Action Button: Proceed to Confirmation
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            ),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(
              'Proceed to Confirmation (${p.effectiveRecipientCount} Students)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            onPressed: p.effectiveRecipientCount == 0
                ? null
                : () {
                    setState(() => _currentStep = 1);
                  },
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipientInspectors(SmsRecipientPreview p) {
    return Column(
      children: [
        // Valid Recipients Expansion
        ExpansionTile(
          initiallyExpanded: false,
          leading: const Icon(Icons.verified_user_rounded, color: Color(0xFF2E7D32)),
          title: Text(
            'Valid Recipients (${p.validRecipients.length})',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: const Text(
            'Numbers are masked for privacy (+91 XX*** **XXX)',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: p.validRecipients.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, idx) {
                  final r = p.validRecipients[idx];
                  return ListTile(
                    dense: true,
                    title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text('${r.registerNumber} • Stop: ${r.boardingStop ?? 'Campus'}', style: const TextStyle(fontSize: 11)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (r.isDuplicate)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.amber.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Duplicate', style: TextStyle(fontSize: 10, color: AppColors.amberDark, fontWeight: FontWeight.bold)),
                          ),
                        Text(
                          r.maskedMobile,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),

        // Invalid Recipients Expansion
        if (p.invalidRecipients.isNotEmpty)
          ExpansionTile(
            initiallyExpanded: false,
            leading: const Icon(Icons.cancel_outlined, color: Color(0xFFC62828)),
            title: Text(
              'Invalid Mobile Numbers (${p.invalidRecipients.length})',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFFC62828)),
            ),
            subtitle: const Text('These students will be excluded automatically', style: TextStyle(fontSize: 11)),
            children: [
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: p.invalidRecipients.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final inv = p.invalidRecipients[idx];
                    return ListTile(
                      dense: true,
                      title: Text(inv['name']?.toString() ?? 'Student', style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        '${inv['register_number']} • Reason: ${inv['error'] ?? 'Invalid number'}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFFC62828)),
                      ),
                      trailing: Text(
                        inv['masked_mobile']?.toString() ?? 'N/A',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

        // Duplicate Groups Expansion
        if (p.duplicateGroups.isNotEmpty)
          ExpansionTile(
            initiallyExpanded: false,
            leading: const Icon(Icons.people_outline_rounded, color: AppColors.amberDark),
            title: Text(
              'Shared Numbers (${p.duplicateGroups.length} groups)',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: const Text('Students sharing identical mobile numbers', style: TextStyle(fontSize: 11)),
            children: [
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: p.duplicateGroups.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final g = p.duplicateGroups[idx];
                    final students = (g['students'] as List<dynamic>? ?? []);
                    return ListTile(
                      dense: true,
                      title: Text(
                        'Shared Mobile: ${g['masked_mobile']}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
                      ),
                      subtitle: Text(
                        'Students (${g['count']}): ${students.map((s) => s['name']).join(', ')}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 2: CONFIRMATION SCREEN
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildConfirmationStep(SmsService smsService) {
    final p = _preview!;
    final segInfo = SmsCalculator.calculate(widget.message);
    final totalSmsCredits = segInfo.totalSms(p.effectiveRecipientCount);
    final sim = smsService.selectedSim;
    final device = smsService.deviceStatus;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Message Content Card
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
                          Icon(Icons.message_rounded, color: AppColors.navy, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Message Content',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: segInfo.isUnicode ? AppColors.amber.withOpacity(0.15) : AppColors.engBg,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                        child: Text(
                          segInfo.encoding,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: segInfo.isUnicode ? AppColors.amberDark : AppColors.navy,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  // Simulated Message Bubble
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.message,
                          style: const TextStyle(fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${segInfo.charCount} characters | ${segInfo.segments} segment${segInfo.segments == 1 ? '' : 's'} per student',
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 2. Dispatch Summary Table (Category, Total SMS, Segments, SIM, Device)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dispatch Parameters & Hardware Audit',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const Divider(height: 20),
                  _buildConfirmRow('Recipient Category', p.recipientCategory),
                  if (p.routeName != null) _buildConfirmRow('Assigned Route', p.routeName!),
                  if (p.busNumber != null) _buildConfirmRow('Assigned Bus', p.busNumber!),
                  _buildConfirmRow('Target Students', '${p.effectiveRecipientCount} students'),
                  _buildConfirmRow(
                    'Estimated SMS Segments',
                    '${segInfo.segments} segment${segInfo.segments == 1 ? '' : 's'} (${segInfo.encoding})',
                  ),
                  _buildConfirmRow(
                    'Total SMS Count',
                    '$totalSmsCredits SMS (${p.effectiveRecipientCount} × ${segInfo.segments})',
                    isHighlight: true,
                  ),
                  const Divider(height: 16),
                  _buildConfirmRow(
                    'Selected SIM',
                    sim != null
                        ? '${sim.displayName} (${sim.carrierName}) • Slot ${sim.simSlotIndex + 1}'
                        : 'Default Phone SIM',
                    isSuccess: sim != null,
                  ),
                  _buildConfirmRow(
                    'Sending Device',
                    '${device.deviceModel} (Android ${device.androidVersion.isNotEmpty ? device.androidVersion : 'Telephony'})',
                    isSuccess: device.isReady,
                  ),
                  _buildConfirmRow(
                    'Duplicate Policy',
                    _allowDuplicates ? 'Approved (All entries)' : 'Deduplicated (1 per unique number)',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 3. Technical Notice / Safeguard
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(AppRadii.sm),
              border: Border.all(color: const Color(0xFFFFE082)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: Color(0xFFF57F17), size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'SMS messages will be transmitted sequentially from this Android phone\'s cellular SIM. '
                    'Ensure your SIM has an active carrier SMS plan and stable cellular coverage.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF5D4037), height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // 4. Action Buttons (Back & Confirm Send)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                  ),
                  onPressed: () => setState(() => _currentStep = 0),
                  child: const Text('Back to Preview'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                  ),
                  icon: const Icon(Icons.send_rounded),
                  label: Text(
                    'Confirm & Send ($totalSmsCredits SMS)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  onPressed: _isDispatching ? null : () => _startBulkDispatch(smsService),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildConfirmRow(String label, String value, {bool? isSuccess, bool isHighlight = false}) {
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
                  fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
                  color: isHighlight
                      ? AppColors.emeraldDark
                      : (isSuccess == null
                          ? AppColors.textPrimary
                          : (isSuccess ? const Color(0xFF2E7D32) : const Color(0xFFC62828))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
