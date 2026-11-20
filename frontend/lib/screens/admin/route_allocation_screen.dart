import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/student.dart';
import '../../services/student_service.dart';

class RouteAllocationScreen extends StatefulWidget {
  final int initialTab; // 0 for Route Allocations, 1 for Bus Allocations

  const RouteAllocationScreen({super.key, this.initialTab = 0});

  @override
  State<RouteAllocationScreen> createState() => _RouteAllocationScreenState();
}

class _RouteAllocationScreenState extends State<RouteAllocationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _allocations;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _loadAllocations();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllocations() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final svc = Provider.of<StudentService>(context, listen: false);
      final data = await svc.fetchRouteAllocations();
      if (!mounted) return;
      setState(() {
        _allocations = data;
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

  void _showStudentsForAllocation({
    required String title,
    String? routeName,
    String? busNumber,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _StudentsListSheet(
        title: title,
        routeName: routeName,
        busNumber: busNumber,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text(
          'Route & Bus Allocations',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.emerald,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: 'By Route', icon: Icon(Icons.alt_route_rounded, size: 20)),
            Tab(text: 'By Regular Bus', icon: Icon(Icons.directions_bus_rounded, size: 20)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadAllocations,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.emerald))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 48, color: AppColors.amber),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textPrimary)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadAllocations,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.navy,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _allocations == null
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        _buildTopStatBanner(),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildRouteTab(),
                              _buildBusTab(),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildTopStatBanner() {
    final total = _allocations!['total_students'] ?? 0;
    final active = _allocations!['total_active_students'] ?? 0;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.people_alt_rounded,
                    color: AppColors.navy, size: 22),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$total Registered Students',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '$active Active Transport Pass Holders',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.emeraldDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteTab() {
    final routes = (_allocations!['routes'] as List<dynamic>?) ?? [];
    if (routes.isEmpty) {
      return const Center(
        child: Text('No route allocations found.',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: routes.length,
      itemBuilder: (context, index) {
        final r = routes[index];
        final routeName = r['route_name']?.toString() ?? 'Unassigned';
        final total = r['total_students'] ?? 0;
        final active = r['active_students'] ?? 0;
        final buses = (r['buses'] as List<dynamic>?) ?? [];

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
          child: InkWell(
            onTap: () => _showStudentsForAllocation(
              title: routeName,
              routeName: routeName,
            ),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.alt_route_rounded,
                        color: AppColors.emerald, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          routeName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Buses: ${buses.isNotEmpty ? buses.join(", ") : "None assigned"}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$total',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                      Text(
                        '$active active',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.emeraldDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_ios_rounded,
                      size: 14, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBusTab() {
    final buses = (_allocations!['buses'] as List<dynamic>?) ?? [];
    if (buses.isEmpty) {
      return const Center(
        child: Text('No bus allocations found.',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: buses.length,
      itemBuilder: (context, index) {
        final b = buses[index];
        final busNum = b['bus_number']?.toString() ?? 'Unassigned';
        final total = b['total_students'] ?? 0;
        final active = b['active_students'] ?? 0;
        final routes = (b['routes'] as List<dynamic>?) ?? [];

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
          child: InkWell(
            onTap: () => _showStudentsForAllocation(
              title: 'Bus $busNum',
              busNumber: busNum,
            ),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.navy.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        busNum,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Regular Bus $busNum',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          routes.isNotEmpty ? routes.join(" · ") : 'No route',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$total',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                      Text(
                        '$active active',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.emeraldDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_ios_rounded,
                      size: 14, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StudentsListSheet extends StatefulWidget {
  final String title;
  final String? routeName;
  final String? busNumber;

  const _StudentsListSheet({
    required this.title,
    this.routeName,
    this.busNumber,
  });

  @override
  State<_StudentsListSheet> createState() => _StudentsListSheetState();
}

class _StudentsListSheetState extends State<_StudentsListSheet> {
  List<Student> _students = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    try {
      final svc = Provider.of<StudentService>(context, listen: false);
      final list = await svc.fetchStudents(
        perPage: 100,
        routeName: widget.routeName,
        busNumber: widget.busNumber,
      );
      if (!mounted) return;
      setState(() {
        _students = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '${_students.length} students allocated',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.emerald))
                : _error != null
                    ? Center(child: Text(_error!))
                    : _students.isEmpty
                        ? const Center(
                            child: Text('No students found for this allocation.'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _students.length,
                            itemBuilder: (ctx, i) {
                              final s = _students[i];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor:
                                          AppColors.navy.withAlpha(20),
                                      child: Text(
                                        s.name.isNotEmpty
                                            ? s.name[0].toUpperCase()
                                            : 'S',
                                        style: const TextStyle(
                                            color: AppColors.navy,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            s.name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                                color: AppColors.textPrimary),
                                          ),
                                          Text(
                                            '${s.registerNumber} · ${s.department} ${s.year}',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textSecondary),
                                          ),
                                          Text(
                                            'Stop: ${s.boardingStop} · Bus: ${s.busNumber}',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.emeraldDark),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: s.isTransportActive
                                            ? AppColors.emerald.withAlpha(20)
                                            : Colors.red.withAlpha(20),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        s.isTransportActive
                                            ? 'Active'
                                            : 'Inactive',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: s.isTransportActive
                                              ? AppColors.emerald
                                              : Colors.red,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
