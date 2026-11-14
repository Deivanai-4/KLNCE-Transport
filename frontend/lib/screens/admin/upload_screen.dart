import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../main.dart';
import '../../services/schedule_service.dart';
import 'ocr_review_screen.dart';

class UploadScheduleScreen extends StatefulWidget {
  const UploadScheduleScreen({super.key});

  @override
  State<UploadScheduleScreen> createState() => _UploadScheduleScreenState();
}

class _UploadScheduleScreenState extends State<UploadScheduleScreen> {
  final _titleCtrl = TextEditingController(
      text: 'College Bus Route Schedule for Staff & Student');
  String _tripDirection = 'incoming';
  String _college = 'both';
  DateTime _effectiveDate = DateTime.now();
  PlatformFile? _selectedFile;
  List<int>? _fileBytes;
  bool _isProcessing = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
      withReadStream: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final f = result.files.first;
      List<int>? bytes = f.bytes;
      if (bytes == null && f.readStream != null) {
        try {
          bytes = await f.readStream!.expand((chunk) => chunk).toList();
        } catch (_) {}
      }
      setState(() {
        _selectedFile = f;
        _fileBytes = bytes;
      });
    }
  }

  Future<void> _startOcr() async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please select an image or PDF timetable file.'),
        backgroundColor: AppColors.amber,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ));
      return;
    }

    setState(() => _isProcessing = true);
    final svc = Provider.of<ScheduleService>(context, listen: false);
    final dateStr =
        '${_effectiveDate.year}-${_effectiveDate.month.toString().padLeft(2, '0')}-${_effectiveDate.day.toString().padLeft(2, '0')}';

    try {
      final bytes = _fileBytes ?? _selectedFile!.bytes;
      final filePath = kIsWeb ? '' : (_selectedFile?.path ?? '');
      final draft = await svc.uploadAndExtractSchedule(
        title: _titleCtrl.text.trim(),
        tripDirection: _tripDirection,
        college: _college,
        effectiveDate: dateStr,
        filePath: filePath,
        fileBytes: bytes,
        fileName: _selectedFile!.name,
      );

      if (!mounted) return;
      if (draft != null) {
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => OcrReviewScreen(schedule: draft)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(svc.errorMessage ?? 'Upload failed. Try again.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: ${e.toString()}'),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ));
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPdf = _selectedFile?.extension?.toLowerCase() == 'pdf';

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Column(
        children: [
          // ── Dark Header ─────────────────────────────────────
          Container(
            color: AppColors.navy,
            padding: EdgeInsets.fromLTRB(
                16, MediaQuery.of(context).padding.top + 12, 16, 20),
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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Update Timetable',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Upload transport schedule',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Instructions Banner
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.emerald.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppColors.emerald.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.emerald.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.document_scanner_rounded,
                                  color: AppColors.emeraldDark, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Automated Schedule Reader',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.emeraldDark,
                                          fontSize: 13)),
                                  SizedBox(height: 2),
                                  Text(
                                    'Upload official bus timetable (JPG, PNG or PDF). Routes, stops, and timings will be extracted.',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // File Upload Drop Box
                      GestureDetector(
                        onTap: _isProcessing ? null : _pickFile,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 160,
                          decoration: BoxDecoration(
                            color: _selectedFile != null
                                ? AppColors.emerald.withOpacity(0.06)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _selectedFile != null
                                  ? AppColors.emerald
                                  : const Color(0xFFCBD5E1),
                              width: 2,
                              style: BorderStyle.solid,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  color: _selectedFile != null
                                      ? AppColors.emerald.withOpacity(0.15)
                                      : const Color(0xFFF1F5F9),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _selectedFile != null
                                      ? (isPdf
                                          ? Icons.picture_as_pdf_rounded
                                          : Icons.image_rounded)
                                      : Icons.cloud_upload_outlined,
                                  size: 28,
                                  color: _selectedFile != null
                                      ? AppColors.emerald
                                      : AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _selectedFile != null
                                    ? _selectedFile!.name
                                    : 'Tap to select Timetable Image or PDF',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: _selectedFile != null
                                      ? AppColors.emeraldDark
                                      : AppColors.textPrimary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectedFile != null
                                    ? '${(_selectedFile!.size / 1024).toStringAsFixed(1)} KB • Tap to change file'
                                    : 'Supports: JPG, PNG, PDF up to 10 MB',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Metadata Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Schedule Details',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _titleCtrl,
                              style: const TextStyle(fontSize: 14),
                              decoration: const InputDecoration(
                                labelText: 'Schedule Title',
                                prefixIcon: Icon(Icons.title_rounded, size: 20),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _tripDirection,
                                    decoration: const InputDecoration(
                                      labelText: 'Trip',
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'incoming',
                                          child: Text('Morning Incoming',
                                              style: TextStyle(fontSize: 13))),
                                      DropdownMenuItem(
                                          value: 'outgoing',
                                          child: Text('Evening Outgoing',
                                              style: TextStyle(fontSize: 13))),
                                    ],
                                    onChanged: (v) {
                                      if (v != null) {
                                        setState(() => _tripDirection = v);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _college,
                                    decoration: const InputDecoration(
                                      labelText: 'Campus',
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'both',
                                          child: Text('Both Campuses',
                                              style: TextStyle(fontSize: 13))),
                                      DropdownMenuItem(
                                          value: 'engineering',
                                          child: Text('Engineering',
                                              style: TextStyle(fontSize: 13))),
                                      DropdownMenuItem(
                                          value: 'arts_science',
                                          child: Text('Arts & Science',
                                              style: TextStyle(fontSize: 13))),
                                    ],
                                    onChanged: (v) {
                                      if (v != null) {
                                        setState(() => _college = v);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _effectiveDate,
                                  firstDate: DateTime(2025),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setState(() => _effectiveDate = picked);
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Effective Date',
                                  prefixIcon: Icon(Icons.calendar_today_rounded,
                                      size: 18),
                                ),
                                child: Text(
                                  '${_effectiveDate.day}/${_effectiveDate.month}/${_effectiveDate.year}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Submit Button
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _startOcr,
                          icon: _isProcessing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white)))
                              : const Icon(Icons.document_scanner_rounded,
                                  size: 20),
                          label: Text(
                            _isProcessing
                                ? 'Running OCR Extraction...'
                                : 'Extract Schedule with OCR',
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
