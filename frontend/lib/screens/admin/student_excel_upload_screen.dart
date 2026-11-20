import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/student.dart';
import '../../services/student_service.dart';

class StudentExcelUploadScreen extends StatefulWidget {
  const StudentExcelUploadScreen({super.key});

  @override
  State<StudentExcelUploadScreen> createState() =>
      _StudentExcelUploadScreenState();
}

class _StudentExcelUploadScreenState extends State<StudentExcelUploadScreen> {
  PlatformFile? _selectedFile;
  ExcelPreviewSummary? _preview;
  bool _isProcessing = false;
  bool _isImporting = false;
  String? _error;
  bool _updateExisting = false;

  // Filter in preview list
  String _previewFilter = 'all'; // 'all', 'valid', 'invalid', 'exists'

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;

      setState(() {
        _selectedFile = file;
        _isProcessing = true;
        _preview = null;
      });

      final studentService =
          Provider.of<StudentService>(context, listen: false);
      final preview = await studentService.uploadAndPreview(
        filePath: file.path ?? '',
        fileBytes: file.bytes,
        fileName: file.name,
      );

      if (!mounted) return;
      setState(() {
        _preview = preview;
        _isProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isProcessing = false;
      });
    }
  }

  Future<void> _downloadTemplate(String format) async {
    try {
      final studentService =
          Provider.of<StudentService>(context, listen: false);
      final bytes = await studentService.downloadTemplate(format: format);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Template (${format.toUpperCase()}) downloaded (${bytes.length} bytes). '
            'Fill student details and upload.',
          ),
          backgroundColor: AppColors.emeraldDark,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not download template: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmAndImport() async {
    if (_preview == null) return;

    final validRecords = _preview!.records
        .where((r) => r.status == 'valid' || (_updateExisting && r.status == 'exists'))
        .map((r) => r.toImportJson())
        .toList();

    if (validRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid records to import. Please check validation errors.'),
          backgroundColor: AppColors.amber,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Require confirmation before importing or updating
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Student Import'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ready to import ${validRecords.length} student records into MongoDB Atlas.'),
            const SizedBox(height: 8),
            if (_updateExisting)
              const Text(
                'Note: Existing students with matching register numbers will be safely updated.',
                style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.navy),
              )
            else
              const Text(
                'Note: Existing register numbers will be skipped.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emeraldDark,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Import'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() => _isImporting = true);

    try {
      final studentService =
          Provider.of<StudentService>(context, listen: false);
      final res = await studentService.confirmImport(
        records: validRecords,
        updateExisting: _updateExisting,
      );

      if (!mounted) return;
      setState(() => _isImporting = false);

      final imported = res['imported_count'] ?? 0;
      final updated = res['updated_count'] ?? 0;
      final failed = res['failed_count'] ?? 0;

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppColors.emerald),
              SizedBox(width: 8),
              Text('Import Completed'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New Students Registered: $imported'),
              if (updated > 0) Text('Existing Students Updated: $updated'),
              if (failed > 0) Text('Failed / Skipped: $failed', style: const TextStyle(color: Colors.red)),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop(true); // Return to student list
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isImporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import failed: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text(
          'Upload Student Excel',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Download Template',
            icon: const Icon(Icons.download_rounded),
            onSelected: _downloadTemplate,
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'xlsx',
                child: Text('Download Excel Template (.xlsx)'),
              ),
              PopupMenuItem(
                value: 'csv',
                child: Text('Download CSV Template (.csv)'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildUploadHeader(),
          if (_isProcessing)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.emerald),
                    SizedBox(height: 14),
                    Text('Analyzing and validating student records...',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 48, color: AppColors.amber),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _pickFile,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Select Another File'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_preview != null) ...[
            _buildSummaryRow(),
            _buildFilterChips(),
            Expanded(child: _buildPreviewList()),
            _buildBottomActionBar(),
          ] else
            Expanded(child: _buildEmptyState()),
        ],
      ),
    );
  }

  Widget _buildUploadHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedFile == null
                          ? 'Select Student Registration File'
                          : _selectedFile!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Supports .xlsx (Excel) and .csv files',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isProcessing || _isImporting ? null : _pickFile,
                icon: const Icon(Icons.file_upload_rounded, size: 18),
                label: Text(_selectedFile == null ? 'Browse File' : 'Change'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.navy.withAlpha(15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.table_chart_rounded,
                  size: 52, color: AppColors.navy),
            ),
            const SizedBox(height: 16),
            const Text(
              'No file uploaded yet',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Download the official template or browse an existing .xlsx / .csv student list to preview validation.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => _downloadTemplate('xlsx'),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download Excel Template'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.navy),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow() {
    final p = _preview!;
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          _StatMiniCard(
            label: 'Total',
            value: '${p.totalRows}',
            color: AppColors.navy,
          ),
          const SizedBox(width: 6),
          _StatMiniCard(
            label: 'Valid',
            value: '${p.validCount}',
            color: AppColors.emerald,
          ),
          const SizedBox(width: 6),
          _StatMiniCard(
            label: 'Errors',
            value: '${p.invalidCount}',
            color: Colors.red,
          ),
          const SizedBox(width: 6),
          _StatMiniCard(
            label: 'In MongoDB',
            value: '${p.existingInDbCount}',
            color: AppColors.amber,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          const Text('Filter:',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(width: 8),
          for (final f in [
            ('all', 'All (${_preview!.records.length})'),
            ('valid', 'Valid (${_preview!.validCount})'),
            ('invalid', 'Errors (${_preview!.invalidCount})'),
            ('exists', 'In DB (${_preview!.existingInDbCount})'),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _previewFilter = f.$1),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _previewFilter == f.$1
                        ? AppColors.navy
                        : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    f.$2,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _previewFilter == f.$1
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreviewList() {
    final filtered = _preview!.records.where((r) {
      if (_previewFilter == 'valid') return r.status == 'valid';
      if (_previewFilter == 'invalid') return r.status == 'invalid';
      if (_previewFilter == 'exists') return r.status == 'exists';
      return true;
    }).toList();

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final r = filtered[index];
        final isInvalid = r.status == 'invalid';
        final isSample = r.status == 'sample';
        final isExists = r.status == 'exists';

        Color badgeColor = AppColors.emerald;
        String badgeText = 'Valid';
        if (isSample) {
          badgeColor = Colors.grey;
          badgeText = 'Sample (Excluded)';
        } else if (isInvalid) {
          badgeColor = Colors.red;
          badgeText = 'Invalid';
        } else if (isExists) {
          badgeColor = AppColors.amber;
          badgeText = 'In MongoDB';
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isInvalid
                  ? Colors.red.withAlpha(120)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.navy.withAlpha(15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Row ${r.rowNumber}',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.registerNumber.isNotEmpty
                            ? r.registerNumber
                            : '(Missing Reg No)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: badgeColor.withAlpha(80)),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: badgeColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${r.name} · ${r.department} ${r.year} ${r.section.isNotEmpty ? '(${r.section})' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Bus: ${r.busNumber} · Route: ${r.routeName} · Stop: ${r.boardingStop}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  'Tel: ${r.studentMobile}${r.parentMobile.isNotEmpty ? ' · Parent: ${r.parentMobile}' : ''}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (r.errors.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final err in r.errors)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• ',
                                    style: TextStyle(
                                        color: Colors.red, fontSize: 11)),
                                Expanded(
                                  child: Text(
                                    err,
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomActionBar() {
    final p = _preview!;
    final canImport = p.validCount > 0;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        children: [
          if (p.existingInDbCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Checkbox(
                    value: _updateExisting,
                    activeColor: AppColors.navy,
                    onChanged: (val) {
                      setState(() => _updateExisting = val ?? false);
                    },
                  ),
                  const Expanded(
                    child: Text(
                      'Update existing students matching register number',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed:
                  _isImporting || !canImport ? null : _confirmAndImport,
              icon: _isImporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_upload_rounded),
              label: Text(
                _isImporting
                    ? 'Importing...'
                    : 'Import Valid Students (${p.validCount})',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emeraldDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatMiniCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatMiniCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(16),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(45)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
