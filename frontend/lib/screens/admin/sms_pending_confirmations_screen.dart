// lib/screens/admin/sms_pending_confirmations_screen.dart
// Stage 8 — List of campaigns awaiting admin approval before SIM dispatch

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/sms_campaign.dart';
import '../../services/sms_auto_service.dart';
import '../../services/sms_service.dart';
import 'sms_campaign_detail_screen.dart';

class SmsPendingConfirmationsScreen extends StatefulWidget {
  const SmsPendingConfirmationsScreen({super.key});

  @override
  State<SmsPendingConfirmationsScreen> createState() =>
      _SmsPendingConfirmationsScreenState();
}

class _SmsPendingConfirmationsScreenState
    extends State<SmsPendingConfirmationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SmsAutoService>(context, listen: false)
          .loadPendingConfirmations();
    });
  }

  Future<void> _approve(SmsCampaign campaign) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm & Send'),
        content: Text(
          'Send ${campaign.sessionLabel} SMS campaign?\n\n'
          '• ${campaign.totalRecipients} recipients\n'
          '• Via your phone SIM\n'
          '• This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.emerald),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Confirm & Send'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final autoSvc = Provider.of<SmsAutoService>(context, listen: false);
    final smsSvc = Provider.of<SmsService>(context, listen: false);
    final ok = await autoSvc.approveCampaign(campaign.id, smsSvc);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Campaign approved. SMS dispatch started.'
            : 'Error: ${autoSvc.error}'),
        backgroundColor: ok ? AppColors.emerald : Colors.red,
      ),
    );
  }

  Future<void> _reject(SmsCampaign campaign) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Campaign'),
        content: const Text(
            'This campaign will be cancelled and not sent. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final autoSvc = Provider.of<SmsAutoService>(context, listen: false);
    await autoSvc.rejectCampaign(campaign.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Campaign rejected and cancelled.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Confirmations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                Provider.of<SmsAutoService>(context, listen: false)
                    .loadPendingConfirmations(),
          ),
        ],
      ),
      body: Consumer<SmsAutoService>(
        builder: (context, svc, _) {
          if (svc.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final campaigns = svc.pendingConfirmations;

          if (campaigns.isEmpty) {
            return RefreshIndicator(
              onRefresh: svc.loadPendingConfirmations,
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                            size: 56, color: AppColors.emerald),
                        SizedBox(height: 12),
                        Text(
                          'No pending confirmations',
                          style: TextStyle(
                              fontSize: 16, color: AppColors.textSecondary),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Automatic campaigns will appear here\nwhen a schedule is published.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: svc.loadPendingConfirmations,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: campaigns.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final campaign = campaigns[index];
                return _PendingCampaignCard(
                  campaign: campaign,
                  isApproving: svc.isApproving,
                  onApprove: () => _approve(campaign),
                  onReject: () => _reject(campaign),
                  onViewDetails: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SmsCampaignDetailScreen(campaignId: campaign.id),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _PendingCampaignCard extends StatelessWidget {
  final SmsCampaign campaign;
  final bool isApproving;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onViewDetails;

  const _PendingCampaignCard({
    required this.campaign,
    required this.isApproving,
    required this.onApprove,
    required this.onReject,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final sessionColor =
        campaign.session == 'morning' ? const Color(0xFFF59E0B) : AppColors.navyMid;
    final sessionIcon =
        campaign.session == 'morning' ? Icons.wb_sunny_rounded : Icons.wb_twilight_rounded;

    return Card(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(sessionIcon, color: sessionColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  campaign.sessionLabel,
                  style: TextStyle(
                    color: sessionColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 8),
                _StatusBadge('Awaiting Approval', Colors.orange),
                const Spacer(),
                Text(
                  campaign.scheduleDate ?? '—',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Stats
            Row(
              children: [
                _Stat(
                    icon: Icons.people_rounded,
                    label: 'Recipients',
                    value: '${campaign.totalRecipients}'),
                const SizedBox(width: 16),
                _Stat(
                    icon: Icons.directions_bus_rounded,
                    label: 'Buses',
                    value: campaign.busCount?.toString() ?? '—'),
                const SizedBox(width: 16),
                _Stat(
                    icon: Icons.route_rounded,
                    label: 'Routes',
                    value: campaign.routeCount?.toString() ?? '—'),
              ],
            ),

            const SizedBox(height: 10),

            // Message preview
            if (campaign.message.isNotEmpty) ...[
              Text(
                'Message preview:',
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  campaign.message.length > 120
                      ? '${campaign.message.substring(0, 120)}…'
                      : campaign.message,
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isApproving ? null : onReject,
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: isApproving ? null : onApprove,
                    icon: isApproving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Approve & Send'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: onViewDetails,
              child: const Text('View full campaign details →',
                  style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Stat({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13)),
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary)),
          ],
        ),
      ],
    );
  }
}
