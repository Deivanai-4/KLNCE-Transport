import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../services/bus_service.dart';
import '../../models/bus_route.dart';
import '../../widgets/bus_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchCtrl = TextEditingController();
  String _selectedTrip = 'incoming';
  final _focusNode = FocusNode();

  final _quickStops = [
    'Teppakulam', 'Periyar', 'Thirunagar', 'Mattuthavani',
    'Madurai Junction', 'Silaiman', 'Arapalayam', 'KK Nagar',
  ];

  final _tamilStops = ['தேரடி', 'பெரியார்', 'திருநகர்', 'மட்டுத்தாவணி'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _search(String query) {
    if (query.trim().length < 2) {
      Provider.of<BusService>(context, listen: false).clearResults();
      return;
    }
    final svc = Provider.of<BusService>(context, listen: false);
    svc.searchByStop(query.trim(), trip: _selectedTrip);
  }

  void _quickSearch(String stop) {
    _searchCtrl.text = stop;
    _search(stop);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final busSvc = Provider.of<BusService>(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Find a bus'),
        actions: [
          if (_searchCtrl.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                _searchCtrl.clear();
                Provider.of<BusService>(context, listen: false).clearResults();
                setState(() {});
              },
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Where are you boarding?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'incoming',
                      label: Text('To campus'),
                    ),
                    ButtonSegment(
                      value: 'outgoing',
                      label: Text('From campus'),
                    ),
                  ],
                  selected: {_selectedTrip},
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) return;
                    setState(() => _selectedTrip = selection.first);
                    if (_searchCtrl.text.trim().length >= 2) {
                      _search(_searchCtrl.text);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _searchCtrl,
                  focusNode: _focusNode,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _search,
                  onChanged: (value) {
                    if (value.trim().length >= 2) {
                      _search(value);
                    } else {
                      Provider.of<BusService>(context, listen: false)
                          .clearResults();
                    }
                    setState(() {});
                  },
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search a stop or bus number',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchCtrl.clear();
                              Provider.of<BusService>(context, listen: false)
                                  .clearResults();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: busSvc.isLoading
                ? const Center(child: CircularProgressIndicator())
                : busSvc.errorMessage != null
                    ? _buildSearchError(busSvc.errorMessage!)
                    : busSvc.searchResults.isNotEmpty
                        ? _buildResults(
                            busSvc.searchResults,
                            busSvc.lastQuery,
                          )
                        : busSvc.lastQuery.isNotEmpty
                            ? _buildNoResults(busSvc.lastQuery)
                            : _buildQuickAccess(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_outlined,
              size: 36,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Search is unavailable',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () => _search(_searchCtrl.text),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(List<BusRoute> results, String query) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.emerald.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.emerald.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 14, color: AppColors.emerald),
                    const SizedBox(width: 5),
                    Text(
                      '${results.length} bus${results.length != 1 ? 'es' : ''} found',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.emeraldDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('for "$query"',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (_, i) => BusCard(
              route: results[i],
              highlightStop: _searchCtrl.text.trim(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoResults(String query) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.search_off_rounded,
                  size: 44, color: AppColors.amber),
            ),
            const SizedBox(height: 20),
            const Text('No Buses Found',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(
              'No bus passes through "$query".\nTry a nearby area or check spelling.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _quickStops
                  .take(4)
                  .map((s) => ActionChip(
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        onPressed: () => _quickSearch(s),
                        backgroundColor: AppColors.emerald.withOpacity(0.08),
                        labelStyle: const TextStyle(
                            color: AppColors.emeraldDark,
                            fontWeight: FontWeight.w600),
                        side: const BorderSide(
                            color: AppColors.emerald, width: 0.5),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAccess() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Text('Popular Stops',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('Tap to quickly find your bus',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickStops
                .map((s) => ActionChip(
                      avatar: const Icon(Icons.location_on_outlined,
                          size: 14, color: AppColors.emerald),
                      label: Text(s,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textPrimary)),
                      onPressed: () => _quickSearch(s),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(
                            color: Color(0xFFE2E8F0)),
                      ),
                      elevation: 0,
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),

          // Tamil stops section
          const Text('தமிழில் தேடுங்கள்',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tamilStops
                .map((s) => ActionChip(
                      label: Text(s,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.arts)),
                      onPressed: () => _quickSearch(s),
                      backgroundColor: AppColors.artsBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(
                            color: Color(0xFFDDD6FE)),
                      ),
                      elevation: 0,
                    ))
                .toList(),
          ),

          const SizedBox(height: 20),
          // Bilingual tip
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.emerald.withOpacity(0.07),
                  AppColors.emerald.withOpacity(0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.emerald.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.emerald.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.translate_rounded,
                      color: AppColors.emerald, size: 18),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tamil & English Support',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.emeraldDark)),
                      SizedBox(height: 2),
                      Text(
                        'Search in Tamil (தேரடி) or English (Madurai Junction)',
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
        ],
      ),
    );
  }
}
