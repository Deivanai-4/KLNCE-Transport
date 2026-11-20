import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/student.dart';
import '../../services/student_service.dart';
import 'student_excel_upload_screen.dart';
import 'route_allocation_screen.dart';

class StudentManagementScreen extends StatefulWidget {
  const StudentManagementScreen({super.key});

  @override
  State<StudentManagementScreen> createState() =>
      _StudentManagementScreenState();
}

class _StudentManagementScreenState extends State<StudentManagementScreen> {
  List<Student> _students = [];
  int _totalCount = 0;
  bool _isLoading = false;
  String? _error;

  // Search & Filters
  final TextEditingController _searchCtrl = TextEditingController();
  String? _selectedDept;
  String? _selectedYear;
  bool? _filterActive;
  int _page = 1;
  static const int _perPage = 20;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStudents({bool reset = false}) async {
    if (reset) {
      _page = 1;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final svc = Provider.of<StudentService>(context, listen: false);
      final list = await svc.fetchStudents(
        page: _page,
        perPage: _perPage,
        q: _searchCtrl.text.trim().isNotEmpty ? _searchCtrl.text.trim() : null,
        department: _selectedDept,
        year: _selectedYear,
        isTransportActive: _filterActive,
      );
      if (!mounted) return;
      setState(() {
        _students = list;
        _totalCount = svc.totalCount;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleStatus(Student student) async {
    try {
      final svc = Provider.of<StudentService>(context, listen: false);
      final updated = await svc.toggleTransportStatus(student.id);
      if (!mounted) return;
      setState(() {
        final idx = _students.indexWhere((s) => s.id == student.id);
        if (idx >= 0) _students[idx] = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${student.name} transport status: ${updated.isTransportActive ? "Active" : "Inactive"}',
          ),
          backgroundColor: updated.isTransportActive
              ? AppColors.emeraldDark
              : Colors.grey[800],
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update status: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showEditDialog(Student student) async {
    final nameCtrl = TextEditingController(text: student.name);
    final regCtrl = TextEditingController(text: student.registerNumber);
    final deptCtrl = TextEditingController(text: student.department);
    final yearCtrl = TextEditingController(text: student.year);
    final secCtrl = TextEditingController(text: student.section);
    final mobCtrl = TextEditingController(text: student.studentMobile);
    final parentMobCtrl = TextEditingController(text: student.parentMobile);
    final routeCtrl = TextEditingController(text: student.routeName);
    final busCtrl = TextEditingController(text: student.busNumber);
    final stopCtrl = TextEditingController(text: student.boardingStop);

    bool isSaving = false;
    String? dialogError;

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: Text('Edit ${student.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: regCtrl,
                  decoration: const InputDecoration(labelText: 'Register Number *'),
                ),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Student Name *'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: deptCtrl,
                        decoration: const InputDecoration(labelText: 'Dept *'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: yearCtrl,
                        decoration: const InputDecoration(labelText: 'Year *'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: secCtrl,
                        decoration: const InputDecoration(labelText: 'Sec'),
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: mobCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Student Mobile * (10 digits)'),
                ),
                TextField(
                  controller: parentMobCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Parent Mobile (Optional)'),
                ),
                const SizedBox(height: 8),
                const Text('Route & Bus Allocation',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.navy)),
                TextField(
                  controller: routeCtrl,
                  decoration: const InputDecoration(labelText: 'Assigned Route *'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: busCtrl,
                        decoration: const InputDecoration(labelText: 'Regular Bus *'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: stopCtrl,
                        decoration: const InputDecoration(labelText: 'Boarding Stop *'),
                      ),
                    ),
                  ],
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 8),
                  Text(dialogError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() {
                        isSaving = true;
                        dialogError = null;
                      });
                      try {
                        final svc = Provider.of<StudentService>(context, listen: false);
                        await svc.updateStudent(student.id, {
                          'register_number': regCtrl.text.trim(),
                          'name': nameCtrl.text.trim(),
                          'department': deptCtrl.text.trim(),
                          'year': yearCtrl.text.trim(),
                          'section': secCtrl.text.trim(),
                          'student_mobile': mobCtrl.text.trim(),
                          'parent_mobile': parentMobCtrl.text.trim(),
                          'route_name': routeCtrl.text.trim(),
                          'bus_number': busCtrl.text.trim(),
                          'boarding_stop': stopCtrl.text.trim(),
                        });
                        if (!mounted) return;
                        Navigator.of(dialogCtx).pop(true);
                      } catch (e) {
                        setDialogState(() {
                          dialogError = e.toString().replaceAll('Exception: ', '');
                          isSaving = false;
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
              child: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );

    if (updated == true) {
      _loadStudents();
    }
  }

  Future<void> _showManualAddDialog() async {
    final nameCtrl = TextEditingController();
    final regCtrl = TextEditingController();
    final deptCtrl = TextEditingController();
    final yearCtrl = TextEditingController();
    final secCtrl = TextEditingController();
    final mobCtrl = TextEditingController();
    final parentMobCtrl = TextEditingController();
    final routeCtrl = TextEditingController();
    final busCtrl = TextEditingController();
    final stopCtrl = TextEditingController();

    bool isSaving = false;
    String? dialogError;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Add Student Manually'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: regCtrl,
                  decoration: const InputDecoration(labelText: 'Register Number * (e.g. 910621104001)'),
                ),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Student Name *'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: deptCtrl,
                        decoration: const InputDecoration(labelText: 'Dept * (CSE)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: yearCtrl,
                        decoration: const InputDecoration(labelText: 'Year * (III)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: secCtrl,
                        decoration: const InputDecoration(labelText: 'Sec (A)'),
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: mobCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Student Mobile * (10 digits)'),
                ),
                TextField(
                  controller: parentMobCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Parent Mobile (Optional)'),
                ),
                const SizedBox(height: 8),
                const Text('Route & Regular Bus',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.navy)),
                TextField(
                  controller: routeCtrl,
                  decoration: const InputDecoration(labelText: 'Assigned Route * (e.g. Route A - Periyar)'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: busCtrl,
                        decoration: const InputDecoration(labelText: 'Bus No * (S1)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: stopCtrl,
                        decoration: const InputDecoration(labelText: 'Boarding Stop * (Teppakulam)'),
                      ),
                    ),
                  ],
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 8),
                  Text(dialogError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() {
                        isSaving = true;
                        dialogError = null;
                      });
                      try {
                        final svc = Provider.of<StudentService>(context, listen: false);
                        await svc.addStudent({
                          'register_number': regCtrl.text.trim(),
                          'name': nameCtrl.text.trim(),
                          'department': deptCtrl.text.trim(),
                          'year': yearCtrl.text.trim(),
                          'section': secCtrl.text.trim(),
                          'student_mobile': mobCtrl.text.trim(),
                          'parent_mobile': parentMobCtrl.text.trim(),
                          'route_name': routeCtrl.text.trim(),
                          'bus_number': busCtrl.text.trim(),
                          'boarding_stop': stopCtrl.text.trim(),
                        });
                        if (!mounted) return;
                        Navigator.of(dialogCtx).pop(true);
                      } catch (e) {
                        setDialogState(() {
                          dialogError = e.toString().replaceAll('Exception: ', '');
                          isSaving = false;
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.emeraldDark, foregroundColor: Colors.white),
              child: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Register Student'),
            ),
          ],
        ),
      ),
    );

    if (created == true) {
      _loadStudents();
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
          'Student Management',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.alt_route_rounded),
            tooltip: 'Route Allocations',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RouteAllocationScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_rounded),
            tooltip: 'Upload Excel',
            onPressed: () async {
              final refreshed = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const StudentExcelUploadScreen()),
              );
              if (refreshed == true) {
                _loadStudents(reset: true);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => _loadStudents(reset: true),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showManualAddDialog,
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Student'),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildFilterChips(),
          _buildCountHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Search by Register No, Name, or Stop...',
          hintStyle: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.navy),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: () {
                    _searchCtrl.clear();
                    _loadStudents(reset: true);
                  },
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF1F5F9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.navy, width: 1.5),
          ),
        ),
        onSubmitted: (_) => _loadStudents(reset: true),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Dept chips
            _FilterPill(
              label: _selectedDept == null ? 'All Depts' : _selectedDept!,
              isSelected: _selectedDept != null,
              onTap: () {
                _showDeptPicker();
              },
            ),
            const SizedBox(width: 6),
            // Year chips
            _FilterPill(
              label: _selectedYear == null ? 'All Years' : 'Year $_selectedYear',
              isSelected: _selectedYear != null,
              onTap: () {
                _showYearPicker();
              },
            ),
            const SizedBox(width: 6),
            // Status chips
            _FilterPill(
              label: _filterActive == null
                  ? 'All Status'
                  : (_filterActive! ? 'Active Pass' : 'Inactive'),
              isSelected: _filterActive != null,
              onTap: () {
                setState(() {
                  if (_filterActive == null) {
                    _filterActive = true;
                  } else if (_filterActive == true) {
                    _filterActive = false;
                  } else {
                    _filterActive = null;
                  }
                });
                _loadStudents(reset: true);
              },
            ),
            if (_selectedDept != null || _selectedYear != null || _filterActive != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedDept = null;
                    _selectedYear = null;
                    _filterActive = null;
                  });
                  _loadStudents(reset: true);
                },
                child: const Text('Clear',
                    style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDeptPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('All Departments'),
              onTap: () {
                setState(() => _selectedDept = null);
                Navigator.pop(ctx);
                _loadStudents(reset: true);
              },
            ),
            for (final d in ['CSE', 'ECE', 'MECH', 'IT', 'EEE', 'CIVIL', 'AIDS', 'MBA', 'MCA'])
              ListTile(
                title: Text(d),
                onTap: () {
                  setState(() => _selectedDept = d);
                  Navigator.pop(ctx);
                  _loadStudents(reset: true);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showYearPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('All Years'),
              onTap: () {
                setState(() => _selectedYear = null);
                Navigator.pop(ctx);
                _loadStudents(reset: true);
              },
            ),
            for (final y in ['I', 'II', 'III', 'IV'])
              ListTile(
                title: Text('Year $y'),
                onTap: () {
                  setState(() => _selectedYear = y);
                  Navigator.pop(ctx);
                  _loadStudents(reset: true);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountHeader() {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '$_totalCount Students Found',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StudentExcelUploadScreen()),
            ).then((_) => _loadStudents(reset: true)),
            icon: const Icon(Icons.file_upload_rounded, size: 14),
            label: const Text('Excel Upload', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.navy,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _students.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.emerald));
    }
    if (_error != null && _students.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.amber),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _loadStudents(reset: true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
    if (_students.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people_alt_outlined, size: 52, color: AppColors.textSecondary),
              const SizedBox(height: 14),
              const Text(
                'No student records found',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 6),
              const Text(
                'Upload an Excel student list or use Add Student to register students.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StudentExcelUploadScreen()),
                ).then((_) => _loadStudents(reset: true)),
                icon: const Icon(Icons.file_upload_rounded),
                label: const Text('Upload Student Excel'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadStudents(reset: true),
      color: AppColors.emerald,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
        itemCount: _students.length,
        itemBuilder: (context, index) {
          final s = _students[index];
          return _StudentTile(
            student: s,
            onToggleStatus: () => _toggleStatus(s),
            onEdit: () => _showEditDialog(s),
          );
        },
      ),
    );
  }
}

class _StudentTile extends StatelessWidget {
  final Student student;
  final VoidCallback onToggleStatus;
  final VoidCallback onEdit;

  const _StudentTile({
    required this.student,
    required this.onToggleStatus,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = student.isTransportActive ? AppColors.emerald : Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.navy.withAlpha(20),
                  child: Text(
                    student.name.isNotEmpty ? student.name[0].toUpperCase() : 'S',
                    style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              student.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: activeColor.withAlpha(20),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: activeColor.withAlpha(60)),
                            ),
                            child: Text(
                              student.isTransportActive ? 'Active Pass' : 'Inactive',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: activeColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Reg: ${student.registerNumber} · ${student.department} Year ${student.year} ${student.section.isNotEmpty ? '(${student.section})' : ''}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 18),
            // Route Allocation info
            Row(
              children: [
                const Icon(Icons.alt_route_rounded, size: 16, color: AppColors.emerald),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${student.routeName} · Bus: ${student.busNumber}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.navy),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                const Icon(Icons.pin_drop_rounded, size: 16, color: AppColors.amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Stop: ${student.boardingStop}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                const Icon(Icons.phone_rounded, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  'Student: ${student.studentMobile}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
                if (student.parentMobile.isNotEmpty) ...[
                  const Text(' · ', style: TextStyle(color: AppColors.textSecondary)),
                  Text(
                    'Parent: ${student.parentMobile}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onToggleStatus,
                  icon: Icon(
                    student.isTransportActive ? Icons.cancel_outlined : Icons.check_circle_outline_rounded,
                    size: 14,
                  ),
                  label: Text(student.isTransportActive ? 'Deactivate' : 'Activate', style: const TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: student.isTransportActive ? Colors.red : AppColors.emeraldDark,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    minimumSize: const Size(0, 32),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 14),
                  label: const Text('Edit / Reallocate', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    minimumSize: const Size(0, 32),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.navy : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.navy : const Color(0xFFCBD5E1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 16,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
