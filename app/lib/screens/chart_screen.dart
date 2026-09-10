import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/stock_data.dart';
import '../services/stock_service.dart';

class ChartScreen extends StatefulWidget {
  final String symbol;
  const ChartScreen({super.key, required this.symbol});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  final _service = StockService();
  ChartData? _data;
  bool _loading = true;
  String? _error;
  int _rangeDays = 63; // default ~3 months

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await _service.fetchChart(widget.symbol);
      setState(() {
        _data = c;
        _loading = false;
        if (c == null) _error = 'No chart data for ${widget.symbol}.';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not load chart.\n$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.symbol)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : _buildChart(),
    );
  }

  // Build spots from a series, skipping nulls (x = index).
  List<FlSpot> _spots(List<double?> series) {
    final spots = <FlSpot>[];
    for (var i = 0; i < series.length; i++) {
      final v = series[i];
      if (v != null) spots.add(FlSpot(i.toDouble(), v));
    }
    return spots;
  }

  double _min(List<List<double?>> series) {
    double m = double.infinity;
    for (final s in series) {
      for (final v in s) {
        if (v != null && v < m) m = v;
      }
    }
    return m == double.infinity ? 0 : m;
  }

  double _max(List<List<double?>> series) {
    double m = -double.infinity;
    for (final s in series) {
      for (final v in s) {
        if (v != null && v > m) m = v;
      }
    }
    return m == -double.infinity ? 1 : m;
  }

  // Slice the last N bars from a series.
  List<double?> _tail(List<double?> s, int n) =>
      s.length <= n ? s : s.sublist(s.length - n);

  Widget _rangeSelector() {
    final options = <String, int>{
      '1M': 21,
      '3M': 63,
      '6M': 126,
      'Max': 100000,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        children: [
          for (final e in options.entries)
            ChoiceChip(
              label: Text(e.key),
              selected: _rangeDays == e.value,
              onSelected: (_) => setState(() => _rangeDays = e.value),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final full = _data!;
    final r = _rangeDays;
    // Sliced view for the selected range.
    final d = ChartData(
      dates: full.dates.length <= r
          ? full.dates
          : full.dates.sublist(full.dates.length - r),
      close: _tail(full.close, r),
      ema50: _tail(full.ema50, r),
      ema200: _tail(full.ema200, r),
      bbUpper: _tail(full.bbUpper, r),
      bbLower: _tail(full.bbLower, r),
      macd: _tail(full.macd, r),
      macdSignal: _tail(full.macdSignal, r),
      macdHist: _tail(full.macdHist, r),
      rsi: _tail(full.rsi, r),
      volAvg20: _tail(full.volAvg20, r),
      volume: _tail(full.volume, r),
    );
    final n = d.close.length;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _rangeSelector(),
        _panelTitle('Price · EMA50 · EMA200 · Bollinger'),
        _lineChart(
          height: 260,
          lines: [
            _line(_spots(d.bbUpper), Colors.grey.shade400, width: 1),
            _line(_spots(d.bbLower), Colors.grey.shade400, width: 1),
            _line(_spots(d.close), Colors.black, width: 1.6),
            _line(_spots(d.ema50), Colors.blue, width: 1.2),
            _line(_spots(d.ema200), Colors.red, width: 1.2),
          ],
          minY: _min([d.bbLower, d.close, d.ema200]) * 0.99,
          maxY: _max([d.bbUpper, d.close]) * 1.01,
          n: n,
          dates: d.dates,
          valuePrefix: '₹',
          primaryBarIndex: 2, // the Close line
        ),
        _legend(const {
          'Close': Colors.black,
          'EMA50': Colors.blue,
          'EMA200': Colors.red,
          'Bollinger': Colors.grey,
        }),
        const SizedBox(height: 16),
        _panelTitle('Volume · 20d avg'),
        _volumeChart(d, n),
        const SizedBox(height: 16),
        _panelTitle('MACD (12,26,9)'),
        _lineChart(
          height: 160,
          lines: [
            _line(_spots(d.macd), Colors.blue, width: 1.2),
            _line(_spots(d.macdSignal), Colors.red, width: 1.2),
          ],
          minY: _min([d.macd, d.macdSignal, d.macdHist]) * 1.1,
          maxY: _max([d.macd, d.macdSignal, d.macdHist]) * 1.1,
          n: n,
          zeroLine: true,
          dates: d.dates,
        ),
        _legend(const {'MACD': Colors.blue, 'Signal': Colors.red}),
        const SizedBox(height: 16),
        _panelTitle('RSI (14)'),
        _lineChart(
          height: 140,
          lines: [_line(_spots(d.rsi), Colors.purple, width: 1.2)],
          minY: 0,
          maxY: 100,
          n: n,
          extraLines: [30, 50, 70],
          dates: d.dates,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _panelTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  LineChartBarData _line(List<FlSpot> spots, Color color,
          {double width = 1}) =>
      LineChartBarData(
        spots: spots,
        isCurved: false,
        color: color,
        barWidth: width,
        dotData: const FlDotData(show: false),
      );

  Widget _lineChart({
    required double height,
    required List<LineChartBarData> lines,
    required double minY,
    required double maxY,
    required int n,
    bool zeroLine = false,
    List<double> extraLines = const [],
    List<String>? dates, // when provided, tap shows date + value
    String valuePrefix = '',
    int primaryBarIndex = 0, // which line's value to show in the tooltip
  }) {
    final hLines = <HorizontalLine>[];
    if (zeroLine) {
      hLines.add(HorizontalLine(y: 0, color: Colors.black26, strokeWidth: 0.8));
    }
    for (final y in extraLines) {
      hLines.add(HorizontalLine(
          y: y,
          color: y == 50 ? Colors.grey.shade300 : Colors.redAccent.shade100,
          strokeWidth: 0.6,
          dashArray: [4, 4]));
    }
    // Which bar index carries the "main" value we want in the tooltip — the
    // last line added is the primary series for MACD/RSI; for the price panel
    // we mark the Close line explicitly via [primaryBarIndex].
    return SizedBox(
      height: height,
      child: LineChart(LineChartData(
        minX: 0,
        maxX: (n - 1).toDouble(),
        minY: minY,
        maxY: maxY,
        lineBarsData: lines,
        extraLinesData: ExtraLinesData(horizontalLines: hLines),
        titlesData: const FlTitlesData(
          leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(
            show: true, border: Border.all(color: Colors.grey.shade300)),
        // Google-Finance-style crosshair + tooltip: tap/drag shows the date
        // and value at that point. A vertical indicator line is drawn.
        lineTouchData: LineTouchData(
          enabled: true,
          getTouchedSpotIndicator: (barData, indexes) {
            return indexes.map((i) {
              return TouchedSpotIndicatorData(
                const FlLine(color: Colors.black38, strokeWidth: 1),
                FlDotData(
                  // Only draw the dot on the primary series for a clean look.
                  show: true,
                  getDotPainter: (spot, percent, bar, index) {
                    final isPrimary = lines.isNotEmpty &&
                        bar == lines[primaryBarIndex.clamp(0, lines.length - 1)];
                    return FlDotCirclePainter(
                      radius: isPrimary ? 4 : 0,
                      color: bar.color ?? Colors.black,
                      strokeWidth: 0,
                    );
                  },
                ),
              );
            }).toList();
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.black87,
            maxContentWidth: 160,
            getTooltipItems: (spots) {
              // Show the date + the primary series' value once; suppress the
              // other overlapping lines so the tooltip stays clean.
              return spots.map((s) {
                if (s.barIndex != primaryBarIndex) return null;
                final xi = s.x.round();
                final dateStr = (dates != null && xi >= 0 && xi < dates.length)
                    ? dates[xi]
                    : '';
                final valStr = '$valuePrefix${s.y.toStringAsFixed(2)}';
                return LineTooltipItem(
                  dateStr.isEmpty ? valStr : '$dateStr\n$valStr',
                  const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                );
              }).toList();
            },
          ),
          handleBuiltInTouches: true,
        ),
      )),
    );
  }

  Widget _volumeChart(ChartData d, int n) {
    final bars = <BarChartGroupData>[];
    double maxV = 1;
    for (var i = 0; i < d.volume.length; i++) {
      final v = d.volume[i] ?? 0;
      if (v > maxV) maxV = v;
      bars.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(
            toY: v, color: Colors.blueGrey.shade300, width: 2),
      ]));
    }
    return SizedBox(
      height: 130,
      child: BarChart(BarChartData(
        maxY: maxV * 1.1,
        barGroups: bars,
        titlesData: const FlTitlesData(
          leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(
            show: true, border: Border.all(color: Colors.grey.shade300)),
      )),
    );
  }

  Widget _legend(Map<String, Color> items) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 12,
          children: [
            for (final e in items.entries)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 12, height: 3, color: e.value),
                const SizedBox(width: 4),
                Text(e.key, style: const TextStyle(fontSize: 11)),
              ]),
          ],
        ),
      );
}
