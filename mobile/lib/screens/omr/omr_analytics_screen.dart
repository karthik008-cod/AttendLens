import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/theme/theme.dart';

class OmrAnalyticsScreen extends StatefulWidget {
  final Map<String, dynamic> exam;

  const OmrAnalyticsScreen({super.key, required this.exam});

  @override
  State<OmrAnalyticsScreen> createState() => _OmrAnalyticsScreenState();
}

class _OmrAnalyticsScreenState extends State<OmrAnalyticsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  Map<String, dynamic>? _analyticsData;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAnalytics();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAnalytics() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final res = await ApiService.getOmrAnalytics(widget.exam['id']);
      if (mounted) {
        setState(() {
          _analyticsData = res['analytics'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _exportReport(bool isExcel) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: AttendLensTheme.accentCyan)),
      );

      final examId = widget.exam['id'];
      final url = isExcel ? ApiService.getOmrExcelUrl(examId) : ApiService.getOmrPdfUrl(examId);
      final res = await http.get(Uri.parse(url));

      if (mounted) Navigator.pop(context); // close loader

      if (res.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final ext = isExcel ? 'xlsx' : 'pdf';
        final title = widget.exam['title']?.toString().replaceAll(' ', '_') ?? 'Exam';
        final file = File('${dir.path}/OMR_Report_${title}_$examId.$ext');
        await file.writeAsBytes(res.bodyBytes);

        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'AttendLens OMR Assessment Report ($title)',
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: Status ${res.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AttendLensTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AttendLensTheme.surfaceDark,
        elevation: 0,
        title: Text(
          widget.exam['title'] ?? 'Exam Analytics',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Export Excel Button
          IconButton(
            icon: const Icon(Icons.table_chart_outlined, color: AttendLensTheme.statusPresent),
            tooltip: 'Export Excel Report',
            onPressed: () => _exportReport(true),
          ),
          // Export PDF Button
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined, color: AttendLensTheme.accentCyan),
            tooltip: 'Export PDF Report',
            onPressed: () => _exportReport(false),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadAnalytics,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AttendLensTheme.accentCyan,
          labelColor: AttendLensTheme.accentCyan,
          unselectedLabelColor: Colors.white60,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'Batch Overview'),
            Tab(text: 'Student Ranks'),
            Tab(text: 'Item Analysis (CTT)'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AttendLensTheme.primaryIndigo))
          : _error != null
              ? Center(child: Text('Error: $_error', style: GoogleFonts.outfit(color: Colors.white70)))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildBatchOverviewTab(),
                    _buildStudentRanksTab(),
                    _buildItemAnalysisTab(),
                  ],
                ),
    );
  }

  // ── Tab 1: Batch Overview ──────────────────────────────────────────────────

  Widget _buildBatchOverviewTab() {
    final batch = _analyticsData?['batch_summary'] ?? {};
    final bins = (_analyticsData?['score_distribution'] as List<dynamic>?) ?? [];
    final subjects = (_analyticsData?['subject_batch_performance'] as List<dynamic>?) ?? [];
    final students = (_analyticsData?['students'] as List<dynamic>?) ?? [];
    final atRisk = students.where((s) => (s['risk_flags'] as List<dynamic>?)?.isNotEmpty ?? false).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Executive Summary Stats Grid
          Row(
            children: [
              _statBox('Class Mean', '${batch['mean_score']} / ${batch['max_possible_marks']}', Icons.school, AttendLensTheme.accentCyan),
              const SizedBox(width: 10),
              _statBox('Pass Rate', '${batch['pass_rate']}%', Icons.verified, AttendLensTheme.statusPresent),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _statBox('Median Score', '${batch['median_score']}', Icons.timeline, Colors.white),
              const SizedBox(width: 10),
              _statBox('Std Dev', '${batch['std_dev']}', Icons.stacked_line_chart, Colors.white70),
              const SizedBox(width: 10),
              _statBox('KR-20 Reliability', '${batch['kr20_reliability']}', Icons.shield_outlined, AttendLensTheme.primaryPurple),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _statBox('Avg Difficulty (p)', '${batch['average_difficulty']}', Icons.speed, Colors.amber),
              const SizedBox(width: 10),
              _statBox('Avg Discrimination', '${batch['average_discrimination']}', Icons.compare_arrows, AttendLensTheme.accentCyan),
            ],
          ),
          const SizedBox(height: 24),

          // Score Distribution Histogram
          Text('Score Distribution (Bell Curve)', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),
          Container(
            height: 220,
            decoration: AttendLensTheme.glassDecoration,
            padding: const EdgeInsets.fromLTRB(12, 20, 16, 12),
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (bins.fold(0, (max, b) => (b['count'] as int) > max ? (b['count'] as int) : max) + 2).toDouble(),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AttendLensTheme.surfaceDark,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final b = bins[groupIndex];
                      return BarTooltipItem(
                        '${b['range']}: ${b['count']} students',
                        GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) {
                        final idx = val.toInt();
                        if (idx >= 0 && idx < bins.length && idx % 2 == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(bins[idx]['range'], style: GoogleFonts.outfit(fontSize: 9, color: AttendLensTheme.textSecondary)),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (val, meta) => Text(
                        val.toInt().toString(),
                        style: GoogleFonts.outfit(fontSize: 10, color: AttendLensTheme.textSecondary),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(bins.length, (i) {
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: (bins[i]['count'] as int).toDouble(),
                        color: AttendLensTheme.primaryIndigo,
                        width: 14,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Subject-wise Batch Performance
          Text('Subject-wise Performance', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),
          ...subjects.map((sb) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: AttendLensTheme.glassDecoration,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sb['subject'] ?? 'Subject', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text('Max Marks: ${sb['max_marks']}', style: GoogleFonts.outfit(fontSize: 11, color: AttendLensTheme.textSecondary)),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AttendLensTheme.accentCyan.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('Avg: ${sb['average_score']}', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: AttendLensTheme.accentCyan)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AttendLensTheme.statusPresent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('Acc: ${sb['average_accuracy']}%', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: AttendLensTheme.statusPresent)),
                    ),
                  ],
                ),
              ],
            ),
          )),
          const SizedBox(height: 24),

          // At-Risk Students Warning
          if (atRisk.isNotEmpty) ...[
            Text('At-Risk Candidates (${atRisk.length})', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AttendLensTheme.statusAbsent)),
            const SizedBox(height: 12),
            ...atRisk.map((s) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AttendLensTheme.statusAbsent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AttendLensTheme.statusAbsent.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${s['student_name']} (${s['student_hall_ticket']})', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 6,
                        children: ((s['risk_flags'] as List<dynamic>?) ?? []).map((f) => Text('• $f', style: GoogleFonts.outfit(fontSize: 11, color: AttendLensTheme.statusAbsent))).toList(),
                      ),
                    ],
                  ),
                  Text('${s['total_score']} M (${s['percentage']}%)', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _statBox(String label, String val, IconData icon, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: AttendLensTheme.glassDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(val, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.outfit(fontSize: 10, color: AttendLensTheme.textSecondary)),
        ],
      ),
    ),
  );

  // ── Tab 2: Student Ranks ───────────────────────────────────────────────────

  Widget _buildStudentRanksTab() {
    final students = (_analyticsData?['students'] as List<dynamic>?) ?? [];

    if (students.isEmpty) {
      return Center(child: Text('No student submissions yet', style: GoogleFonts.outfit(color: Colors.white70)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: students.length,
      itemBuilder: (ctx, idx) {
        final s = students[idx];
        final rank = s['rank'] ?? (idx + 1);
        final name = s['student_name'] ?? 'Candidate';
        final ht = s['student_hall_ticket'] ?? '';
        final score = s['total_score'] ?? 0;
        final maxM = s['total_max_marks'] ?? 0;
        final pct = s['percentage'] ?? 0;
        final pr = s['percentile'] ?? 0;
        final acc = s['accuracy'] ?? 0;
        final att = s['attempt_rate'] ?? 0;
        final pen = s['penalty_ratio'] ?? 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: AttendLensTheme.glassDecoration,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: rank <= 3 ? AttendLensTheme.accentCyan.withOpacity(0.2) : Colors.white10,
                          shape: BoxShape.circle,
                          border: Border.all(color: rank <= 3 ? AttendLensTheme.accentCyan : Colors.white24),
                        ),
                        child: Center(
                          child: Text(
                            '#$rank',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: rank <= 3 ? AttendLensTheme.accentCyan : Colors.white, fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          Text('Hall Ticket: $ht', style: GoogleFonts.outfit(fontSize: 11, color: AttendLensTheme.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$score / $maxM', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text('$pct% ($pr %ile)', style: GoogleFonts.outfit(fontSize: 11, color: AttendLensTheme.statusPresent, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Metrics Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _miniStat('Accuracy', '$acc%'),
                  _miniStat('Attempt', '$att%'),
                  _miniStat('Penalty Loss', '$pen%'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _miniStat(String label, String val) => Column(
    children: [
      Text(val, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70)),
      Text(label, style: GoogleFonts.outfit(fontSize: 10, color: AttendLensTheme.textSecondary)),
    ],
  );

  // ── Tab 3: Item Analysis (Classical Test Theory) ───────────────────────────

  Widget _buildItemAnalysisTab() {
    final items = (_analyticsData?['item_analysis'] as List<dynamic>?) ?? [];

    if (items.isEmpty) {
      return Center(child: Text('No item analysis available', style: GoogleFonts.outfit(color: Colors.white70)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (ctx, idx) {
        final it = items[idx];
        final qNum = it['question_number'];
        final subj = it['subject'];
        final key = it['key'];
        final p = it['p_value'];
        final diffLabel = it['difficulty_label'];
        final di = it['discrimination_index'];
        final discLabel = it['discrimination_label'];
        final rpbis = it['point_biserial'];
        final dec = it['decision'] ?? 'KEEP';
        final distractors = (it['distractors'] as Map<String, dynamic>?) ?? {};

        Color decColor = AttendLensTheme.statusPresent;
        if (dec.contains('DISCARD') || dec.contains('CHECK KEY')) {
          decColor = AttendLensTheme.statusAbsent;
        } else if (dec.contains('REVISE')) {
          decColor = Colors.amber;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: AttendLensTheme.glassDecoration,
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AttendLensTheme.primaryIndigo.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Q$qNum', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('$subj (Key: $key)', style: GoogleFonts.outfit(fontSize: 13, color: Colors.white70)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: decColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: decColor.withOpacity(0.4)),
                  ),
                  child: Text(dec, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: decColor)),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Text('p: $p ($diffLabel)', style: GoogleFonts.outfit(fontSize: 11, color: Colors.amber)),
                  const SizedBox(width: 12),
                  Text('DI: $di ($discLabel)', style: GoogleFonts.outfit(fontSize: 11, color: AttendLensTheme.accentCyan)),
                ],
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(color: Colors.white10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Point-Biserial (r_pbis): $rpbis', style: GoogleFonts.outfit(fontSize: 11, color: Colors.white70)),
                        Text('NFD (<5%): ${it['nfd_count']}', style: GoogleFonts.outfit(fontSize: 11, color: Colors.white70)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('Distractor Selection Frequencies:', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [1, 2, 3, 4].map((opt) {
                        final od = distractors[opt.toString()] ?? {};
                        final pct = od['pct'] ?? 0;
                        final isKey = od['is_key'] ?? false;
                        final flag = od['flag'] ?? '';

                        return Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isKey ? AttendLensTheme.statusPresent.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isKey ? AttendLensTheme.statusPresent : Colors.white10),
                          ),
                          child: Column(
                            children: [
                              Text('Opt $opt', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: isKey ? AttendLensTheme.statusPresent : Colors.white)),
                              Text('$pct%', style: GoogleFonts.outfit(fontSize: 11, color: Colors.white70)),
                              if (!isKey && flag != 'Functional')
                                Text(flag.contains('<5%') ? 'NFD' : 'Mislead', style: GoogleFonts.outfit(fontSize: 9, color: Colors.amber)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
