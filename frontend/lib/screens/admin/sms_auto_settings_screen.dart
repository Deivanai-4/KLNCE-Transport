// lib/screens/admin/sms_auto_settings_screen.dart
// Stage 8 — Automatic SMS Schedule Settings screen

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/sms_auto_settings.dart';
import '../../services/sms_auto_service.dart';

class SmsAutoSettingsScreen extends StatefulWidget {
  const SmsAutoSettingsScreen({super.key});

  @override
  State<SmsAutoSettingsScreen> createState() => _SmsAutoSettingsScreenState();
}

class _SmsAutoSettingsScreenState extends State<SmsAutoSettingsScreen> {
  // Form state (editable copies)
  bool _isEnabled = false;
  String _morningTime = '06:30';
  String _afternoonTime = '14:00';
  String _confirmationPolicy = 'confirmation';
  List<String> _enabledSessions = ['morning', 'afternoon'];
  String _recipientGroup = 'all_active';
  String _testPhone = '';
  String _templateMorning =
      'KLNCE Transport: Morning bus {bus_number} on {route_name} departs at {departure_time}. Check app for stop sequence.';
  String _templateAfternoon =
      'KLNCE Transport: Afternoon bus {bus_number} on {route_name} departs at {departure_time}. Check app for stop sequence.';

  bool _disclaimerExpanded = false;
  bool _isTestingNow = false;
  String? _testResult;

  final _testPhoneController = TextEditingController();
  final _templateMorningController = TextEditingController();
  final _templateAfternoonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Provider.of<SmsAutoService>(context, listen: false).loadSettings();
      _syncFromSettings();
    });
  }

  void _syncFromSettings() {
    final s = Provider.of<SmsAutoService>(context, listen: false).settings;
    if (s == null || !mounted) return;
    setState(() {
      _isEnabled = s.isEnabled;
      _morningTime = s.morningTime;
      _afternoonTime = s.afternoonTime;
      _confirmationPolicy = s.confirmationPolicy;
      _enabledSessions = List.from(s.enabledSessions);
      _recipientGroup = s.recipientGroup;
      _testPhone = s.testPhone;
      _templateMorning = s.messageTemplateMorning;
      _templateAfternoon = s.messageTemplateAfternoon;
      _testPhoneController.text = s.testPhone;
      _templateMorningController.text = s.messageTemplateMorning;
      _templateAfternoonController.text = s.messageTemplateAfternoon;
    });
  }

  @override
  void dispose() {
    _testPhoneController.dispose();
    _templateMorningController.dispose();
    _templateAfternoonController.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isMorning) async {
    final parts = isMorning ? _morningTime.split(':') : _afternoonTime.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? (isMorning ? 6 : 14),
      minute: int.tryParse(parts[1]) ?? 30,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (isMorning) {
        _morningTime = formatted;
      } else {
        _afternoonTime = formatted;
      }
    });
  }

  Future<void> _onToggleAutomatic(bool value) async {
    if (value) {
      // Warn before switching to automatic mode
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enable Automatic Mode?'),
          content: const Text(
            'In Automatic Mode, SMS messages are sent WITHOUT requiring your approval each time.\n\n'
            'Only enable this if you are certain the schedule data is always correct.\n\n'
            'Confirmation Mode (Recommended) is safer — it asks you to approve before each send.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enable Automatic Mode'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() {
      _confirmationPolicy = value ? 'automatic' : 'confirmation';
    });
  }

  Future<void> _save() async {
    final svc = Provider.of<SmsAutoService>(context, listen: false);
    final updated = SmsAutoSettings(
      isEnabled: _isEnabled,
      morningTime: _morningTime,
      afternoonTime: _afternoonTime,
      confirmationPolicy: _confirmationPolicy,
      enabledSessions: _enabledSessions,
      recipientGroup: _recipientGroup,
      testPhone: _testPhoneController.text.trim(),
      messageTemplateMorning: _templateMorningController.text.trim(),
      messageTemplateAfternoon: _templateAfternoonController.text.trim(),
    );
    final ok = await svc.updateSettings(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Settings saved and schedule updated.' : 'Error: ${svc.error}'),
        backgroundColor: ok ? AppColors.emerald : Colors.red,
      ),
    );
  }

  Future<void> _emergencyDisable() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Emergency Disable'),
          ],
        ),
        content: const Text(
          'This will immediately disable all automatic SMS sending and cancel all scheduled WorkManager jobs.\n\n'
          'You can re-enable automatic SMS at any time from this screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disable Now'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final svc = Provider.of<SmsAutoService>(context, listen: false);
    final ok = await svc.emergencyDisable();
    if (!mounted) return;
    if (ok) {
      _syncFromSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Automatic SMS has been disabled immediately.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _testNow() async {
    final phone = _testPhoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a test phone number first.')),
      );
      return;
    }
    final session = _enabledSessions.contains('morning') ? 'morning' : 'afternoon';
    setState(() {
      _isTestingNow = true;
      _testResult = null;
    });
    final svc = Provider.of<SmsAutoService>(context, listen: false);
    final result = await svc.prepareScheduledCampaign(
      session: session,
      forceTest: true,
      testPhone: phone,
    );
    if (!mounted) return;
    setState(() {
      _isTestingNow = false;
      if (result != null) {
        _testResult = 'Test campaign created. '
            '${result['recipient_count'] ?? 1} recipient(s). '
            'Check Pending Confirmations to approve and send.';
      } else {
        _testResult = 'Test failed: ${svc.error}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SmsAutoService>(
      builder: (context, svc, _) {
        final s = svc.settings;
        final isEmergencyDisabled = s?.emergencyDisabled ?? false;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Automatic SMS Settings'),
            actions: [
              TextButton.icon(
                onPressed: svc.isSaving ? null : _save,
                icon: svc.isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: const Text('Save'),
              ),
            ],
          ),
          body: svc.isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── Emergency disabled banner ──────────────────────────
                    if (isEmergencyDisabled)
                      _buildWarningBanner(
                        'Automatic SMS was emergency-disabled. '
                        'Enable the toggle below to re-activate.',
                        Colors.red,
                      ),

                    // ── 1. Enable / Disable ────────────────────────────────
                    _SectionCard(
                      title: 'Enable Automatic SMS',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            title: const Text('Enable automatic schedule SMS',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: const Text(
                                'When enabled, the app prepares and sends SMS at scheduled times each day.'),
                            value: _isEnabled,
                            activeColor: AppColors.emerald,
                            onChanged: (v) => setState(() => _isEnabled = v),
                          ),
                          if (_isEnabled && !isEmergencyDisabled)
                            _buildInfoChip(
                                '✓ Automatic SMS is active', AppColors.emerald),
                          if (!_isEnabled)
                            _buildInfoChip('Automatic SMS is OFF', Colors.grey),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── 2. Schedule Times ──────────────────────────────────
                    _SectionCard(
                      title: 'Schedule Times (IST)',
                      child: Column(
                        children: [
                          _TimeTile(
                            label: 'Morning SMS time',
                            icon: Icons.wb_sunny_rounded,
                            color: const Color(0xFFF59E0B),
                            time: _morningTime,
                            onTap: () => _pickTime(true),
                          ),
                          const Divider(height: 1),
                          _TimeTile(
                            label: 'Afternoon SMS time',
                            icon: Icons.wb_twilight_rounded,
                            color: AppColors.navyMid,
                            time: _afternoonTime,
                            onTap: () => _pickTime(false),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── 3. Sessions ────────────────────────────────────────
                    _SectionCard(
                      title: 'Enabled Sessions',
                      child: Column(
                        children: [
                          CheckboxListTile(
                            title: const Text('Morning schedule'),
                            value: _enabledSessions.contains('morning'),
                            activeColor: AppColors.emerald,
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _enabledSessions.add('morning');
                                } else {
                                  _enabledSessions.remove('morning');
                                }
                              });
                            },
                          ),
                          CheckboxListTile(
                            title: const Text('Afternoon schedule'),
                            value: _enabledSessions.contains('afternoon'),
                            activeColor: AppColors.emerald,
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _enabledSessions.add('afternoon');
                                } else {
                                  _enabledSessions.remove('afternoon');
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── 4. Recipient Group ─────────────────────────────────
                    _SectionCard(
                      title: 'Recipient Group',
                      child: DropdownButtonFormField<String>(
                        value: _recipientGroup,
                        decoration: const InputDecoration(
                          labelText: 'Send SMS to',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'all_active',
                            child: Text('All active transport students'),
                          ),
                          DropdownMenuItem(
                            value: 'by_route',
                            child: Text('Students by route'),
                          ),
                          DropdownMenuItem(
                            value: 'by_bus',
                            child: Text('Students by bus number'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _recipientGroup = v!),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── 5. Confirmation Policy ─────────────────────────────
                    _SectionCard(
                      title: 'Confirmation Policy',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RadioListTile<String>(
                            title: const Text('Confirmation Mode (Recommended)'),
                            subtitle: const Text(
                                'App notifies you before sending. You must approve each campaign.'),
                            value: 'confirmation',
                            groupValue: _confirmationPolicy,
                            activeColor: AppColors.emerald,
                            onChanged: (v) => _onToggleAutomatic(false),
                          ),
                          RadioListTile<String>(
                            title: const Text('Automatic Mode (Advanced)'),
                            subtitle: const Text(
                                'SMS sent without manual approval. Enable only if you trust all published schedules.'),
                            value: 'automatic',
                            groupValue: _confirmationPolicy,
                            activeColor: Colors.orange,
                            onChanged: (v) => _onToggleAutomatic(true),
                          ),
                          if (_confirmationPolicy == 'automatic')
                            _buildWarningBanner(
                              '⚠ Automatic Mode is active. SMS will be sent without approval.',
                              Colors.orange,
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── 6. Message Templates ───────────────────────────────
                    _SectionCard(
                      title: 'Message Templates',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Available variables: {bus_number} {route_name} {departure_time} {first_stop} {date} {session}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _templateMorningController,
                            decoration: const InputDecoration(
                              labelText: 'Morning message template',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _templateAfternoonController,
                            decoration: const InputDecoration(
                              labelText: 'Afternoon message template',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── 7. Test SMS ────────────────────────────────────────
                    _SectionCard(
                      title: 'Test Automatic SMS',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _testPhoneController,
                            decoration: const InputDecoration(
                              labelText: 'Test phone number (+91...)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.phone_rounded),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: (_isTestingNow || svc.isPreparing)
                                  ? null
                                  : _testNow,
                              icon: _isTestingNow
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child:
                                          CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.science_rounded),
                              label: const Text('Test Auto SMS Now'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.navyMid,
                                  foregroundColor: Colors.white),
                            ),
                          ),
                          if (_testResult != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _testResult!,
                                style: TextStyle(
                                  color: _testResult!.startsWith('Test failed')
                                      ? Colors.red
                                      : AppColors.emerald,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── 8. Device / Schedule Status ────────────────────────
                    if (s != null)
                      _SectionCard(
                        title: 'Schedule Status',
                        child: Column(
                          children: [
                            _StatusRow(
                                label: 'Today\'s date', value: s.todayDate ?? '—'),
                            _StatusRow(
                                label: 'Current time (IST)',
                                value: s.currentTimeIst ?? '—'),
                            _StatusRow(
                                label: 'Next morning job',
                                value: s.nextScheduledMorning ?? '—'),
                            _StatusRow(
                                label: 'Next afternoon job',
                                value: s.nextScheduledAfternoon ?? '—'),
                            _StatusRow(
                                label: 'Morning schedule ready',
                                value: s.isReadyForMorning ? '✓ Published' : '✗ Not published'),
                            _StatusRow(
                                label: 'Afternoon schedule ready',
                                value: s.isReadyForAfternoon ? '✓ Published' : '✗ Not published'),
                            _StatusRow(
                                label: 'Pending confirmations',
                                value: s.pendingConfirmationsCount.toString()),
                            _StatusRow(
                                label: 'Last morning run',
                                value: s.lastRunMorning ?? 'Never'),
                            _StatusRow(
                                label: 'Last afternoon run',
                                value: s.lastRunAfternoon ?? 'Never'),
                          ],
                        ),
                      ),

                    const SizedBox(height: 12),

                    // ── 9. Android limitations disclaimer ─────────────────
                    Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.md)),
                      child: ExpansionTile(
                        leading: const Icon(Icons.info_outline,
                            color: AppColors.textSecondary),
                        title: const Text('Android Background Limitations',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        initiallyExpanded: _disclaimerExpanded,
                        onExpansionChanged: (v) =>
                            setState(() => _disclaimerExpanded = v),
                        children: const [
                          Padding(
                            padding:
                                EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Text(
                              '• WorkManager may delay execution up to 15 minutes in Doze mode.\n'
                              '• Force-stopping the app prevents background work until reopened.\n'
                              '• OEM battery optimisation (Xiaomi, Huawei, Samsung One UI) may kill background jobs.\n'
                              '  → Go to Settings → Apps → KLNCE Transport → Battery → Unrestricted.\n'
                              '• Exact timing is not guaranteed by Android OS after API 23.\n'
                              '• A network connection is required at the scheduled time for backend calls.',
                              style:
                                  TextStyle(fontSize: 12, height: 1.6),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── 10. Emergency Disable ──────────────────────────────
                    if (_isEnabled || (s?.isEffectivelyEnabled ?? false))
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: svc.isEmergencyDisabling
                              ? null
                              : _emergencyDisable,
                          icon: svc.isEmergencyDisabling
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.stop_circle_rounded),
                          label: const Text('Emergency Disable All Automatic SMS'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),

                    const SizedBox(height: 32),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildWarningBanner(String text, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 13)),
    );
  }

  Widget _buildInfoChip(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Chip(
        label: Text(text, style: TextStyle(color: color, fontSize: 12)),
        backgroundColor: color.withValues(alpha: 0.1),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
    );
  }
}

// ── Reusable Widgets ──────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final String time;
  final VoidCallback onTap;

  const _TimeTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      trailing: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            time,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 16),
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatusRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ),
          Expanded(
            flex: 3,
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
