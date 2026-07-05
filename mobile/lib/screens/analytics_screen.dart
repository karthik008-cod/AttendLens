import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/theme/theme.dart';

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
    final dates = List<Map<String, dynamic>>.from(_data!['date_summaries'] ?? []);
    final totalLectures = (_data!['total_lectures'] as int?) ?? 0;
    final totalStudents = (_data!['total_students'] as int?) ?? 0;
    final avgPct = (_data!['overall_avg_percentage'] as num?)?.toDouble() ?? 0.0;

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
          const SizedBox(height: 28),

          if (dates.isEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: AttendLensTheme.glassDecoration,
              child: Column(children: [
                const Text('📋', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text('No attendance sessions yet', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                Text('Take attendance to see charts here', style: GoogleFonts.outfit(color: AttendLensTheme.textSecondary, fontSize: 13)),
              ]),
            ),
          ] else ...[
            Text('Attendance Per Session', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
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
                            // Show abbreviated: "MM-DD\nHH:mm"
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

            // Date breakdown list
            ...dates.reversed.map((d) {
              final pct = (d['percentage'] as num).toDouble();
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(color: AttendLensTheme.surfaceDark, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.07))),
                child: Row(children: [
                  Container(width: 4, height: 40, decoration: BoxDecoration(color: _pctColor(pct), borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d['date'], style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                    Text('${d['present']}P  ${d['absent']}A', style: GoogleFonts.outfit(fontSize: 12, color: AttendLensTheme.textSecondary)),
                  ])),
                  Text('${pct.toStringAsFixed(1)}%', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _pctColor(pct))),
                ]),
              );
            }),
          ],
        ],
      ),
    );
  }

  // ── Students Tab ───────────────────────────────────────────────────────────

  Widget _buildStudentsTab() {
    final allStudents = List<Map<String, dynamic>>.from(_data!['student_summaries'] ?? []);
    final filtered = _searchQuery.isEmpty
        ? allStudents
        : allStudents.where((s) =>
            s['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            s['roll_number'].toString().toLowerCase().contains(_searchQuery.toLowerCase())).toList();

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

        // At-risk banner
        if (allStudents.any((s) => (s['percentage'] as num) < 75) && _searchQuery.isEmpty)
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
          border: Border.all(color: pct < 75 ? color.withOpacity(0.4) : Colors.white.withOpacity(0.07)),
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

            // Expanded: attendance history dots
            if (_expanded && history.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(color: Colors.white12),
              const SizedBox(height: 8),
              Text('Attendance History', style: GoogleFonts.outfit(fontSize: 12, color: AttendLensTheme.textSecondary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: history.map<Widget>((h) {
                  final status = h['status'] as String;
                  final isPresent = status == 'P';
                  final isAbsent = status == 'A';
                  final color = isPresent ? AttendLensTheme.statusPresent : isAbsent ? AttendLensTheme.statusAbsent : Colors.grey;
                  return Tooltip(
                    message: '${h['date']}: ${isPresent ? 'Present' : isAbsent ? 'Absent' : 'No record'}',
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(color: color.withOpacity(0.18), shape: BoxShape.circle, border: Border.all(color: color.withOpacity(0.5))),
                      child: Center(child: Text(status, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold))),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
