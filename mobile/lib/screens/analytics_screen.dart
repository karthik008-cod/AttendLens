import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/theme/theme.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AnalyticsScreen extends StatefulWidget {
  final int classId;
  final String className;

  const AnalyticsScreen({super.key, required this.classId, required this.className});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  String _sortBy = 'Default';
  String _filterBy = 'All';
  String? _selectedDateFilter;

  Future<void> _pickFilterDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
      builder: (ctx, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AttendLensTheme.statusPresent,
              onPrimary: Colors.white,
              surface: AttendLensTheme.surfaceDark,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      final m = picked.month.toString().padLeft(2, '0');
      final d = picked.day.toString().padLeft(2, '0');
      setState(() {
        _selectedDateFilter = '${picked.year}-$m-$d';
      });
    }
  }

  void _showSessionAttendanceModal(Map<String, dynamic> dateSummary) {
    final presentList = List<Map<String, dynamic>>.from(dateSummary['present_list'] ?? []);
    final absentList = List<Map<String, dynamic>>.from(dateSummary['absent_list'] ?? []);
    final dateStr = dateSummary['date'] as String;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AttendLensTheme.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DefaultTabController(
        length: 2,
        child: Container(
          height: MediaQuery.of(ctx).size.height * 0.75,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, color: AttendLensTheme.accentCyan, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text("Attendance: $dateStr", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TabBar(
                indicatorColor: AttendLensTheme.statusPresent,
                labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                unselectedLabelStyle: GoogleFonts.outfit(),
                tabs: [
                  Tab(text: "🟢 Present (${presentList.length})"),
                  Tab(text: "🔴 Absent (${absentList.length})"),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildStudentListTab(presentList, isPresent: true),
                    _buildStudentListTab(absentList, isPresent: false),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentListTab(List<Map<String, dynamic>> list, {required bool isPresent}) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          isPresent ? "No students marked present." : "No students absent on this date!",
          style: GoogleFonts.outfit(color: AttendLensTheme.textSecondary, fontSize: 15),
        ),
      );
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        final s = list[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isPresent ? AttendLensTheme.statusPresent.withOpacity(0.2) : AttendLensTheme.statusAbsent.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: isPresent ? AttendLensTheme.statusPresent.withOpacity(0.2) : AttendLensTheme.statusAbsent.withOpacity(0.2),
                child: Icon(isPresent ? Icons.check_circle : Icons.cancel, color: isPresent ? AttendLensTheme.statusPresent : AttendLensTheme.statusAbsent, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s['name'] ?? '', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                    Text("Roll No: ${s['roll_number'] ?? 'N/A'}", style: GoogleFonts.outfit(color: AttendLensTheme.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final data = await ApiService.getClassAnalytics(widget.classId);
      if (mounted) setState(() { _data = data; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Color _pctColor(double pct) {
    if (pct >= 75) return AttendLensTheme.statusPresent;
    if (pct >= 60) return AttendLensTheme.statusLate;
    return AttendLensTheme.statusAbsent;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.className),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData)],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AttendLensTheme.primaryIndigo,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
          unselectedLabelStyle: GoogleFonts.outfit(),
          tabs: const [Tab(text: '📊 Class Overview'), Tab(text: '👥 Students')],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AttendLensTheme.primaryIndigo))
          : _error != null
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.wifi_off, color: Colors.grey, size: 48),
                  const SizedBox(height: 12),
                  Text('Could not load analytics', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 8),
                  ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
                ]))
              : TabBarView(
                  controller: _tabController,
                  children: [_buildClassTab(), _buildStudentsTab()],
                ),
    );
  }

  // ── Class Overview Tab ─────────────────────────────────────────────────────

  Widget _buildClassTab() {
    var dates = List<Map<String, dynamic>>.from(_data!['date_summaries'] ?? []);
    final totalLectures = (_data!['total_lectures'] as int?) ?? 0;
    final totalStudents = (_data!['total_students'] as int?) ?? 0;
    final avgPct = (_data!['overall_avg_percentage'] as num?)?.toDouble() ?? 0.0;

    if (_selectedDateFilter != null && _selectedDateFilter!.isNotEmpty) {
      dates = dates.where((d) => (d['date'] as String).startsWith(_selectedDateFilter!)).toList();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary cards
          Row(children: [
            _summaryCard('${totalLectures}', 'Sessions', Icons.calendar_today_outlined, AttendLensTheme.primaryIndigo),
            const SizedBox(width: 12),
            _summaryCard('$totalStudents', 'Students', Icons.people_outline, AttendLensTheme.accentCyan),
            const SizedBox(width: 12),
            _summaryCard('${avgPct.toStringAsFixed(0)}%', 'Avg. %', Icons.show_chart, _pctColor(avgPct)),
          ]),
          const SizedBox(height: 20),

          // Search / Calendar Date Filter Bar
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _selectedDateFilter != null ? AttendLensTheme.accentCyan : Colors.white,
                    side: BorderSide(color: _selectedDateFilter != null ? AttendLensTheme.accentCyan : Colors.white24, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: Text(
                    _selectedDateFilter != null ? "Date: $_selectedDateFilter" : "Search Date via Calendar",
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: _pickFilterDate,
                ),
              ),
              if (_selectedDateFilter != null) ...[
                const SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(14)),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    tooltip: "Clear Filter",
                    onPressed: () => setState(() => _selectedDateFilter = null),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),

          if (dates.isEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: AttendLensTheme.glassDecoration,
              child: Column(children: [
                const Icon(Icons.event_busy, color: Colors.white24, size: 48),
                const SizedBox(height: 12),
                Text(_selectedDateFilter != null ? 'No sessions on $_selectedDateFilter' : 'No attendance sessions yet', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 6),
                Text(_selectedDateFilter != null ? 'Try choosing another date or clearing filter' : 'Take attendance to see charts here', style: GoogleFonts.outfit(color: AttendLensTheme.textSecondary, fontSize: 13)),
                if (_selectedDateFilter != null) ...[
                  const SizedBox(height: 16),
                  TextButton.icon(
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: Text("Clear Date Filter", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                    onPressed: () => setState(() => _selectedDateFilter = null),
                  ),
                ],
              ]),
            ),
          ] else ...[
            Text('Attendance Per Session (Tap to view Absentees/Presentees)', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: AttendLensTheme.accentCyan)),
            const SizedBox(height: 16),

            // Bar Chart — scrollable like a stock chart
            Container(
              padding: const EdgeInsets.fromLTRB(8, 20, 8, 12),
              decoration: AttendLensTheme.glassDecoration,
              height: 240,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: dates.length < 6 ? MediaQuery.of(context).size.width - 60 : dates.length * 70.0,
                  child: BarChart(
                    BarChartData(
                      maxY: 100,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 25,
                        getDrawingHorizontalLine: (_) => FlLine(color: Colors.white12, strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(sideTitles: SideTitles(
                          showTitles: true, interval: 25, reservedSize: 36,
                          getTitlesWidget: (val, _) => Text('${val.toInt()}%', style: GoogleFonts.outfit(fontSize: 10, color: AttendLensTheme.textSecondary)),
                        )),
                        bottomTitles: AxisTitles(sideTitles: SideTitles(
                          showTitles: true, reservedSize: 44,
                          getTitlesWidget: (val, _) {
                            final i = val.toInt();
                            if (i < 0 || i >= dates.length) return const SizedBox.shrink();
                            final raw = dates[i]['date'] as String;
                            final datePart = raw.length >= 10 ? raw.substring(5, 10) : raw;
                            final timePart = raw.length > 11 ? raw.substring(11, 16) : '';
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(datePart, style: GoogleFonts.outfit(fontSize: 9, color: AttendLensTheme.textSecondary)),
                                  if (timePart.isNotEmpty)
                                    Text(timePart, style: GoogleFonts.outfit(fontSize: 8, color: AttendLensTheme.textSecondary.withOpacity(0.7))),
                                ],
                              ),
                            );
                          },
                        )),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      barGroups: List.generate(dates.length, (i) {
                        final pct = (dates[i]['percentage'] as num).toDouble();
                        return BarChartGroupData(x: i, barRods: [
                          BarChartRodData(
                            toY: pct,
                            width: dates.length > 10 ? 14 : 22,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            color: _pctColor(pct),
                            backDrawRodData: BackgroundBarChartRodData(show: true, toY: 100, color: Colors.white.withOpacity(0.04)),
                          ),
                        ]);
                      }),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Date breakdown list (Clickable cards)
            ...dates.reversed.map((d) {
              final pct = (d['percentage'] as num).toDouble();
              return GestureDetector(
                onTap: () => _showSessionAttendanceModal(d),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: AttendLensTheme.surfaceDark, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.07))),
                  child: Row(children: [
                    Container(width: 4, height: 40, decoration: BoxDecoration(color: _pctColor(pct), borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d['date'], style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text('${d['present']}P  ${d['absent']}A', style: GoogleFonts.outfit(fontSize: 12, color: AttendLensTheme.textSecondary)),
                          const SizedBox(width: 8),
                          const Icon(Icons.touch_app_outlined, size: 13, color: AttendLensTheme.accentCyan),
                          Text(" Tap to view list", style: GoogleFonts.outfit(fontSize: 11, color: AttendLensTheme.accentCyan)),
                        ],
                      ),
                    ])),
                    Text('${pct.toStringAsFixed(1)}%', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _pctColor(pct))),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white30),
                  ]),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // ── Students Tab ───────────────────────────────────────────────────────────

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AttendLensTheme.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sort Students By', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            ...['Default', 'Name (A-Z)', 'Attendance: High to Low', 'Attendance: Low to High'].map((opt) {
              final sel = _sortBy == opt;
              return ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: sel ? AttendLensTheme.primaryIndigo.withOpacity(0.2) : null,
                leading: Icon(sel ? Icons.check_circle : Icons.circle_outlined, color: sel ? AttendLensTheme.accentCyan : Colors.white38),
                title: Text(opt, style: GoogleFonts.outfit(color: sel ? Colors.white : Colors.white70, fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                onTap: () {
                  setState(() => _sortBy = opt);
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AttendLensTheme.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter Students', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            ...['All', 'Below 75% (Shortage)', 'Above 75% (Safe)', '100% Perfect'].map((opt) {
              final sel = _filterBy == opt;
              return ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: sel ? AttendLensTheme.primaryIndigo.withOpacity(0.2) : null,
                leading: Icon(sel ? Icons.check_circle : Icons.circle_outlined, color: sel ? AttendLensTheme.accentCyan : Colors.white38),
                title: Text(opt, style: GoogleFonts.outfit(color: sel ? Colors.white : Colors.white70, fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                onTap: () {
                  setState(() => _filterBy = opt);
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentsTab() {
    final allStudents = List<Map<String, dynamic>>.from(_data!['student_summaries'] ?? []);
    List<Map<String, dynamic>> filtered = allStudents.where((s) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchName = s['name'].toString().toLowerCase().contains(q);
        final matchRoll = s['roll_number'].toString().toLowerCase().contains(q);
        if (!matchName && !matchRoll) return false;
      }
      final pct = (s['percentage'] as num).toDouble();
      if (_filterBy == 'Below 75% (Shortage)' && pct >= 75) return false;
      if (_filterBy == 'Above 75% (Safe)' && pct < 75) return false;
      if (_filterBy == '100% Perfect' && pct < 100) return false;
      return true;
    }).toList();

    if (_sortBy == 'Name (A-Z)') {
      filtered.sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
    } else if (_sortBy == 'Attendance: High to Low') {
      filtered.sort((a, b) => (b['percentage'] as num).compareTo(a['percentage'] as num));
    } else if (_sortBy == 'Attendance: Low to High') {
      filtered.sort((a, b) => (a['percentage'] as num).compareTo(b['percentage'] as num));
    }

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            style: GoogleFonts.outfit(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search student name or roll no…',
              hintStyle: GoogleFonts.outfit(color: AttendLensTheme.textSecondary.withOpacity(0.6), fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: AttendLensTheme.textSecondary),
              filled: true, fillColor: AttendLensTheme.surfaceDark,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),

        // Sort & Filter Row
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _sortBy != 'Default' ? AttendLensTheme.accentCyan : Colors.white70,
                    side: BorderSide(color: _sortBy != 'Default' ? AttendLensTheme.accentCyan : Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.sort_rounded, size: 18),
                  label: Text(
                    _sortBy == 'Default' ? 'Sort' : _sortBy.split(':')[0],
                    style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: _showSortOptions,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _filterBy != 'All' ? AttendLensTheme.primaryIndigo : Colors.white70,
                    side: BorderSide(color: _filterBy != 'All' ? AttendLensTheme.primaryIndigo : Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.filter_list_rounded, size: 18),
                  label: Text(
                    _filterBy == 'All' ? 'Filter' : _filterBy.split(' ')[0],
                    style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: _showFilterOptions,
                ),
              ),
              if (_sortBy != 'Default' || _filterBy != 'All') ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 20),
                  tooltip: 'Reset Filters',
                  onPressed: () => setState(() { _sortBy = 'Default'; _filterBy = 'All'; }),
                ),
              ],
            ],
          ),
        ),

        // At-risk banner
        if (allStudents.any((s) => (s['percentage'] as num) < 75) && _searchQuery.isEmpty && _filterBy == 'All')
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AttendLensTheme.statusAbsent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AttendLensTheme.statusAbsent.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: AttendLensTheme.statusAbsent, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  '${allStudents.where((s) => (s['percentage'] as num) < 75).length} student(s) below 75% — listed first',
                  style: GoogleFonts.outfit(fontSize: 12, color: AttendLensTheme.statusAbsent),
                )),
              ]),
            ),
          ),

        // Student list
        Expanded(
          child: filtered.isEmpty
              ? Center(child: Text('No students found', style: GoogleFonts.outfit(color: Colors.grey, fontSize: 15)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _StudentCard(student: filtered[i], pctColor: _pctColor),
                ),
        ),
      ],
    );
  }

  Widget _summaryCard(String value, String label, IconData icon, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(value, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: GoogleFonts.outfit(fontSize: 11, color: AttendLensTheme.textSecondary)),
      ]),
    ),
  );
}

// ── Student Card ───────────────────────────────────────────────────────────────

class _StudentCard extends StatefulWidget {
  final Map<String, dynamic> student;
  final Color Function(double) pctColor;
  const _StudentCard({required this.student, required this.pctColor});

  @override
  State<_StudentCard> createState() => _StudentCardState();
}

class _StudentCardState extends State<_StudentCard> {
  bool _expanded = false;

  void _sendAtRiskAlert(double pct) {
    final name = widget.student['name'];
    final roll = widget.student['roll_number'];
    final present = widget.student['present'];
    final total = widget.student['total'];
    final phoneRaw = (widget.student['phone'] ?? '').toString().trim();
    final phoneClean = phoneRaw.replaceAll(RegExp(r'[^0-9+]'), '');

    final message = '🚨 AttendLens Academic Warning:\n\nHello $name (Roll No: $roll),\n\nYour attendance is currently at ${pct.toStringAsFixed(1)}% ($present Present / $total Total sessions), which falls below the mandatory 75% threshold.\n\nPlease attend upcoming classes regularly or contact the faculty advisor immediately to avoid attendance shortage penalties.';

    showModalBottomSheet(
      context: context,
      backgroundColor: AttendLensTheme.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.send_to_mobile, color: Colors.orangeAccent, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Nudge $name (<75%)", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text(phoneRaw.isNotEmpty ? "Enrolled Mobile: $phoneRaw" : "No mobile number enrolled yet", style: GoogleFonts.outfit(color: AttendLensTheme.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (phoneClean.isNotEmpty) ...[
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF25D366).withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.chat_bubble, color: Color(0xFF25D366)),
                ),
                title: Text("Send via WhatsApp", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: Text("Opens WhatsApp with pre-filled warning", style: GoogleFonts.outfit(color: AttendLensTheme.textSecondary, fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final uri = Uri.parse('https://wa.me/$phoneClean?text=${Uri.encodeComponent(message)}');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    Share.share(message, subject: 'AttendLens Shortage Warning: $name');
                  }
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.sms_rounded, color: Colors.blueAccent),
                ),
                title: Text("Send via SMS / Messages", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: Text("Opens phone messages app with alert text", style: GoogleFonts.outfit(color: AttendLensTheme.textSecondary, fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final uri = Uri.parse('sms:$phoneClean?body=${Uri.encodeComponent(message)}');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  } else {
                    Share.share(message, subject: 'AttendLens Shortage Warning: $name');
                  }
                },
              ),
              const SizedBox(height: 10),
            ],
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.share_rounded, color: Colors.white),
              ),
              title: Text("Share via Other App / Email", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
              subtitle: Text("Use system share menu", style: GoogleFonts.outfit(color: AttendLensTheme.textSecondary, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                Share.share(message, subject: 'AttendLens Shortage Warning: $name');
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showHistoryEditorModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AttendLensTheme.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final history = List<Map<String, dynamic>>.from(widget.student['history'] ?? []);
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 24, right: 24, top: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 18),
                Row(children: [
                  const Icon(Icons.edit_calendar_rounded, color: AttendLensTheme.accentCyan, size: 24),
                  const SizedBox(width: 10),
                  Expanded(child: Text("Past Attendance Editor", style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white))),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AttendLensTheme.statusPresent, backgroundColor: AttendLensTheme.statusPresent.withOpacity(0.15), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                    label: Text("Add Date", style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: now,
                        firstDate: DateTime(2024),
                        lastDate: now,
                        builder: (c, child) => Theme(data: ThemeData.dark(), child: child!),
                      );
                      if (picked != null) {
                        final dateStr = "${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')} 09:00";
                        try {
                          await ApiService.updatePastAttendance(widget.student['id'], dateStr, 'P');
                        } catch (_) {}
                        setState(() {
                          final existing = history.indexWhere((h) => h['date']?.toString().startsWith(dateStr.substring(0, 10)) ?? false);
                          if (existing >= 0) {
                            history[existing]['status'] = 'P';
                            if (widget.student['history'] != null) (widget.student['history'] as List)[existing]['status'] = 'P';
                          } else {
                            final newRec = {'date': dateStr, 'status': 'P'};
                            history.insert(0, newRec);
                            if (widget.student['history'] == null) widget.student['history'] = [];
                            (widget.student['history'] as List).insert(0, newRec);
                          }
                          _recomputeStats();
                        });
                        setModal(() {});
                      }
                    },
                  ),
                ]),
                const SizedBox(height: 4),
                Text("${widget.student['name']} (${widget.student['roll_number']}) — Tap status to modify or add dates", style: GoogleFonts.outfit(color: AttendLensTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 300,
                  child: history.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_today_outlined, size: 40, color: Colors.white24),
                              const SizedBox(height: 12),
                              Text("No past lecture records found.", style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14)),
                              const SizedBox(height: 6),
                              Text("Tap 'Add Date' above to create a record.", style: GoogleFonts.outfit(color: AttendLensTheme.accentCyan, fontSize: 12)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: history.length,
                          separatorBuilder: (_, __) => const Divider(color: Colors.white12),
                          itemBuilder: (_, i) {
                            final h = history[i];
                            final dateStr = h['date']?.toString() ?? 'Unknown Date';
                            final status = h['status']?.toString() ?? '-';
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(dateStr, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () async {
                                      if (status == 'P') return;
                                      setModal(() => h['status'] = 'P');
                                      setState(() {
                                        h['status'] = 'P';
                                        _recomputeStats();
                                      });
                                      try {
                                        await ApiService.updatePastAttendance(widget.student['id'], dateStr, 'P');
                                      } catch (_) {}
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: status == 'P' ? AttendLensTheme.statusPresent : Colors.white12,
                                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                                      ),
                                      child: Text("Present", style: GoogleFonts.outfit(color: status == 'P' ? Colors.white : Colors.white60, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () async {
                                      if (status == 'A') return;
                                      setModal(() => h['status'] = 'A');
                                      setState(() {
                                        h['status'] = 'A';
                                        _recomputeStats();
                                      });
                                      try {
                                        await ApiService.updatePastAttendance(widget.student['id'], dateStr, 'A');
                                      } catch (_) {}
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: status == 'A' ? AttendLensTheme.statusAbsent : Colors.white12,
                                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                                      ),
                                      child: Text("Absent", style: GoogleFonts.outfit(color: status == 'A' ? Colors.white : Colors.white60, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AttendLensTheme.primaryIndigo, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text("Done", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _recomputeStats() {
    final history = widget.student['history'] as List? ?? [];
    int p = 0;
    int t = 0;
    for (var h in history) {
      final s = h['status'];
      if (s == 'P' || s == 'A') {
        t++;
        if (s == 'P') p++;
      }
    }
    widget.student['present'] = p;
    widget.student['total'] = t;
    if (t > 0) {
      widget.student['percentage'] = (p / t) * 100.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = (widget.student['percentage'] as num).toDouble();
    final color = widget.pctColor(pct);
    final history = widget.student['history'] as List? ?? [];

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AttendLensTheme.surfaceDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pct < 75 ? color.withOpacity(0.5) : Colors.white.withOpacity(0.07), width: pct < 75 ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withOpacity(0.18),
                child: Text(widget.student['name'][0], style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: color)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.student['name'], style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                Text('${widget.student['roll_number']}  •  ${widget.student['present']}P / ${widget.student['total']} sessions',
                    style: GoogleFonts.outfit(fontSize: 12, color: AttendLensTheme.textSecondary)),
              ])),
              Text('${pct.toStringAsFixed(1)}%', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              const SizedBox(width: 8),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey, size: 20),
            ]),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct / 100,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 5,
              ),
            ),

            // Smart At-Risk Alert Nudge (if below 75%)
            if (pct < 75) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.withOpacity(0.4))),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text("Shortage Alert Trigger (<75%)", style: GoogleFonts.outfit(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.w600))),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.orange.shade800, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      icon: const Icon(Icons.send_rounded, size: 14),
                      label: Text("Nudge", style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => _sendAtRiskAlert(pct),
                    ),
                  ],
                ),
              ),
            ],

            // Expanded: attendance history dots + editor trigger
            if (_expanded) ...[
              const SizedBox(height: 14),
              const Divider(color: Colors.white12),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Attendance History (${history.length} lectures)', style: GoogleFonts.outfit(fontSize: 12, color: AttendLensTheme.textSecondary, fontWeight: FontWeight.w600)),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AttendLensTheme.accentCyan, padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: Text("Edit History", style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () => _showHistoryEditorModal(context),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (history.isNotEmpty)
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: history.map<Widget>((h) {
                    final status = h['status'] as String;
                    final isPresent = status == 'P';
                    final isAbsent = status == 'A';
                    final dotColor = isPresent ? AttendLensTheme.statusPresent : isAbsent ? AttendLensTheme.statusAbsent : Colors.grey;
                    return GestureDetector(
                      onTap: () => _showHistoryEditorModal(context),
                      child: Tooltip(
                        message: '${h['date']}: ${isPresent ? 'Present' : isAbsent ? 'Absent' : 'No record'} (Tap to edit)',
                        child: Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(color: dotColor.withOpacity(0.18), shape: BoxShape.circle, border: Border.all(color: dotColor.withOpacity(0.5))),
                          child: Center(child: Text(status, style: TextStyle(fontSize: 10, color: dotColor, fontWeight: FontWeight.bold))),
                        ),
                      ),
                    );
                  }).toList(),
                )
              else
                Text('No lecture attendance records yet.', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}
