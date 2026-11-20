import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../main.dart';
import '../../models/sms_campaign.dart';
import '../../services/sms_service.dart';

class SmsCampaignDetailScreen extends StatefulWidget {
  final int campaignId;

  const SmsCampaignDetailScreen({super.key, required this.campaignId});

  @override
  State<SmsCampaignDetailScreen> createState() => _SmsCampaignDetailScreenState();
}

class _SmsCampaignDetailScreenState extends State<SmsCampaignDetailScreen> {
  SmsCampaign? _campaign;
  bool _isLoading = true;
  String? _errorMessage;
  String _statusFilter = ''; // '' = all, 'submitted_to_sms_service', 'delivery_confirmed', 'failed', 'pending', 'cancelled'
  final _searchController = TextEditingController();

  // Retry dispatch state
  bool _isRetrying = false;
  int _retrySent = 0;
  int _retryFailed = 0;
  int _retryTotal = 0;
  String _retryLog = '';

  @override
  void initState() {
    super.initState();
    _loadCampaign();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCampaign() async {
    setState(() => _isLoading = true);
    final smsService = Provider.of<SmsService>(context, listen: false);
    try {
      final camp = await smsService.getCampaignDetails(
        widget.campaignId,
        status: _statusFilter.isNotEmpty ? _statusFilter : null,
        search: _searchController.text.trim().isNotEmpty ? _searchController.text.trim() : null,
      );
      if (!mounted) return;
      setState(() {
        _campaign = camp;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load campaign details: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(_campaign?.title ?? 'Campaign Details'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadCampaign,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
                        const SizedBox(height: 8),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _loadCampaign,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final c = _campaign!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header Card ──────────────────────────────────────────────────
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
                      Expanded(
                        child: Text(
                          c.title,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: c.statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                        child: Text(
                          c.statusDisplay,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: c.statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Target: ${c.targetDisplay}',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  if (c.createdAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Created: ${c.createdAt!.toLocal().toString().split('.')[0]}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                  if (c.senderDevice.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Sender: ${c.senderDevice['device_model'] ?? 'Android'} • ${c.senderDevice['carrier'] ?? 'SIM'} (Slot ${c.senderDevice['sim_slot'] ?? 0})',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                  const Divider(height: 20),
                  const Text(
                    'Message Content:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: Text(
                      c.message,
                      style: const TextStyle(fontSize: 13, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Metrics Row ──────────────────────────────────────────────────
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMetric('Total', '${c.totalRecipients}', Colors.grey.shade700),
                  _buildMetric('Submitted', '${c.submittedCount}', const Color(0xFF2E7D32)),
                  _buildMetric('Delivered', '${c.deliveryConfirmedCount}', const Color(0xFF1B5E20)),
                  _buildMetric('Failed', '${c.failedCount}', const Color(0xFFC62828)),
                  _buildMetric('Pending', '${c.pendingCount}', const Color(0xFFE65100)),
                  _buildMetric('Cancelled', '${c.cancelledCount}', Colors.grey),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Retry Action if Any Failed / Cancelled ───────────────────────
          if (c.failedCount > 0 || c.cancelledCount > 0) ...[
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.amber,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
              ),
              icon: const Icon(Icons.replay_rounded),
              label: Text(
                'Retry Failed & Cancelled Messages (${c.failedCount + c.cancelledCount})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _isRetrying ? null : _confirmAndRetryFailed,
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Search & Filter Bar ──────────────────────────────────────────
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by student name or register number...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _loadCampaign();
                              },
                            )
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onSubmitted: (_) => _loadCampaign(),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('All (${c.totalRecipients})', ''),
                        _buildFilterChip('Submitted (${c.submittedCount})', 'submitted_to_sms_service'),
                        _buildFilterChip('Delivered (${c.deliveryConfirmedCount})', 'delivery_confirmed'),
                        _buildFilterChip('Failed (${c.failedCount})', 'failed'),
                        _buildFilterChip('Pending (${c.pendingCount})', 'pending'),
                        _buildFilterChip('Cancelled (${c.cancelledCount})', 'cancelled'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Recipient Status List ────────────────────────────────────────
          Text(
            'Recipients (${c.recipients.length}):',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (c.recipients.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              alignment: Alignment.center,
              child: const Text(
                'No recipients match the selected filter.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: c.recipients.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, idx) {
                final r = c.recipients[idx];
                return Card(
                  elevation: 0.5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            r.name.isNotEmpty ? r.name : 'Student #${r.studentId}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: r.statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
                          child: Text(
                            r.statusDisplay,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: r.statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          '${r.registerNumber} • Mobile: ${r.maskedMobile}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        if (r.errorReason != null && r.errorReason!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Reason: ${r.errorReason}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFC62828),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (r.sentAt != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Submitted: ${r.sentAt}',
                            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                          ),
                        ],
                      ],
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

  Widget _buildMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String statusKey) {
    final isSelected = _statusFilter == statusKey;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: isSelected,
        selectedColor: AppColors.emerald.withOpacity(0.2),
        labelStyle: TextStyle(
          color: isSelected ? AppColors.emeraldDark : null,
          fontWeight: isSelected ? FontWeight.bold : null,
        ),
        onSelected: (val) {
          setState(() => _statusFilter = val ? statusKey : '');
          _loadCampaign();
        },
      ),
    );
  }

  // ── Retry Confirmation Dialog & Execution ─────────────────────────────────

  Future<void> _confirmAndRetryFailed() async {
    final c = _campaign!;
    final failedCount = c.failedCount + c.cancelledCount;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Selective Retry'),
        content: Text(
          'This will retry sending to $failedCount student(s) whose previous attempt failed or was cancelled.\n\n'
          '⚠️ Previously successful messages will NOT be re-sent.\n\n'
          'Are you ready to dispatch via your phone SIM card?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.amber),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm & Retry'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isRetrying = true;
      _retrySent = 0;
      _retryFailed = 0;
      _retryTotal = failedCount;
      _retryLog = 'Resetting failed recipients in database...';
    });

    final smsService = Provider.of<SmsService>(context, listen: false);

    try {
      // 1. Reset failed recipients to pending in MongoDB
      final updatedCamp = await smsService.retryFailedRecipients(c.id);

      // 2. Dispatch the newly pending recipients via phone SIM
      await smsService.dispatchCampaign(
        campaign: updatedCamp,
        onProgress: (sent, failed, total, logMsg) {
          if (!mounted) return;
          setState(() {
            _retrySent = sent;
            _retryFailed = failed;
            _retryTotal = total;
            _retryLog = logMsg;
          });
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Retry failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRetrying = false);
        await _loadCampaign();
      }
    }
  }
}
