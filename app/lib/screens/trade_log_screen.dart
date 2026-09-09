import 'package:flutter/material.dart';

import '../services/portfolio_service.dart';

/// History of every paper buy/sell, newest first.
class TradeLogScreen extends StatelessWidget {
  const TradeLogScreen({super.key});

  String _money(double v) => '₹${v.toStringAsFixed(2)}';

  String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = PortfolioService();
    return Scaffold(
      appBar: AppBar(title: const Text('Trade log')),
      body: StreamBuilder<List<Trade>>(
        stream: portfolio.tradesStream(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final trades = snap.data!;
          if (trades.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No trades yet.\nBuys and sells will show up here.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // Realized total (sum of sell P/L).
          double realized = 0;
          for (final t in trades) {
            if (!t.isBuy && t.realizedPnl != null) realized += t.realizedPnl!;
          }

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Text(
                  'Realized P/L (closed trades): '
                  '${realized >= 0 ? '+' : ''}${_money(realized)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: realized >= 0
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: trades.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final t = trades[i];
                    final buy = t.isBuy;
                    final pnl = t.realizedPnl;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            buy ? Colors.blue.shade100 : Colors.orange.shade100,
                        child: Icon(
                          buy ? Icons.arrow_downward : Icons.arrow_upward,
                          color: buy ? Colors.blue : Colors.orange.shade800,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        '${buy ? 'BUY' : 'SELL'}  ${t.symbol}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('${t.qty} @ ${_money(t.price)}  ·  '
                          '${_when(t.time)}'),
                      trailing: (!buy && pnl != null)
                          ? Text(
                              '${pnl >= 0 ? '+' : ''}${_money(pnl)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: pnl >= 0
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                              ),
                            )
                          : Text(_money(t.qty * t.price),
                              style: const TextStyle(color: Colors.grey)),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
