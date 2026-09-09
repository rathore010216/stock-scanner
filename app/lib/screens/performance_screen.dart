import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/portfolio_service.dart';

/// Portfolio equity curve — total value snapshotted once per day.
class PerformanceScreen extends StatelessWidget {
  const PerformanceScreen({super.key});

  String _money(double v) => '₹${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final portfolio = PortfolioService();
    return Scaffold(
      appBar: AppBar(title: const Text('Performance')),
      body: StreamBuilder<List<EquityPoint>>(
        stream: portfolio.historyStream(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final points = snap.data!;
          if (points.length < 2) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Not enough history yet.\n\nYour portfolio value is recorded '
                  'once each day you open the app. Check back tomorrow to see '
                  'the equity curve build up.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final first = points.first.value;
          final last = points.last.value;
          final change = last - first;
          final changePct = first > 0 ? change / first * 100 : 0.0;
          final up = change >= 0;

          double minV = points.first.value;
          double maxV = points.first.value;
          for (final p in points) {
            if (p.value < minV) minV = p.value;
            if (p.value > maxV) maxV = p.value;
          }
          // Pad the range so the line isn't flush against edges.
          final pad = (maxV - minV) * 0.08 + 1;
          final spots = <FlSpot>[
            for (var i = 0; i < points.length; i++)
              FlSpot(i.toDouble(), points[i].value),
          ];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Latest value',
                  style: Theme.of(context).textTheme.bodyMedium),
              Text(_money(last),
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                '${up ? '+' : ''}${_money(change)} '
                '(${changePct.toStringAsFixed(2)}%) since first snapshot',
                style: TextStyle(
                  color: up ? Colors.green.shade700 : Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 260,
                child: LineChart(LineChartData(
                  minX: 0,
                  maxX: (points.length - 1).toDouble(),
                  minY: minV - pad,
                  maxY: maxV + pad,
                  titlesData: const FlTitlesData(
                    leftTitles: AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: true, reservedSize: 52)),
                    rightTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData:
                      const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  lineTouchData: const LineTouchData(enabled: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: false,
                      color: up ? Colors.green.shade600 : Colors.red.shade600,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: (up ? Colors.green : Colors.red)
                            .withValues(alpha: 0.10),
                      ),
                    ),
                  ],
                )),
              ),
              const SizedBox(height: 16),
              Text('${points.first.date}  →  ${points.last.date}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 12),
              const Text(
                'Value is captured once per day when you open the app, using '
                'the latest available prices. Paper trading — not real money.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          );
        },
      ),
    );
  }
}
