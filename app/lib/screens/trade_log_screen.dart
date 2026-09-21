import 'package:flutter/material.dart';

import '../services/portfolio_service.dart';

enum _TradeFilter { all, buys, sells }

/// History of every paper buy/sell, newest first, with a buy/sell filter.
class TradeLogScreen extends StatefulWidget {
  const TradeLogScreen({super.key});

  @override
  State<TradeLogScreen> createState() => _TradeLogScreenState();
}

class _TradeLogScreenState extends State<TradeLogScreen> {
  final _portfolio = PortfolioService();
  _TradeFilter _filter = _TradeFilter.all;

  String _money(double v) => '₹${v.toStringAsFixed(2)}';

  String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trade log')),
      body: StreamBuilder<List<Trade>>(
        stream: _portfolio.tradesStream(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data!;
          if (all.isEmpty) {
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

          // Apply the buy/sell filter.
          final trades = all.where((t) {
            switch (_filter) {
              case _TradeFilter.all:
                return true;
              case _TradeFilter.buys:
                return t.isBuy;
              case _TradeFilter.sells:
                return !t.isBuy;
            }
          }).toList();

          // Totals across the CURRENTLY shown trades.
          double realized = 0;
          double fees = 0;
          for (final t in trades) {
            if (!t.isBuy && t.realizedPnl != null) realized += t.realizedPnl!;
            fees += t.fee;
          }

          return Column(
            children: [
              // Filter chips.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    for (final f in _TradeFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(_filterLabel(f)),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ),
              // Summary header for the filtered set.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_filter != _TradeFilter.buys)
                      Text(
                        'Realized P/L (shown): '
                        '${realized >= 0 ? '+' : ''}${_money(realized)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: realized >= 0
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    Text('Fees (shown): ${_money(fees)}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              Expanded(
                child: trades.isEmpty
                    ? const Center(child: Text('No trades match this filter.'))
                    : ListView.separated(
                        itemCount: trades.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final t = trades[i];
                          final buy = t.isBuy;
                          final pnl = t.realizedPnl;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: buy
                                  ? Colors.blue.shade100
                                  : Colors.orange.shade100,
                              child: Icon(
                                buy
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                                color:
                                    buy ? Colors.blue : Colors.orange.shade800,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              '${buy ? 'BUY' : 'SELL'}  ${t.symbol}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text('${t.qty} @ ${_money(t.price)}  ·  '
                                '${_when(t.time)}'
                                '${t.fee > 0 ? '  ·  fee ${_money(t.fee)}' : ''}'),
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

  String _filterLabel(_TradeFilter f) {
    switch (f) {
      case _TradeFilter.all:
        return 'All';
      case _TradeFilter.buys:
        return 'Buys';
      case _TradeFilter.sells:
        return 'Sells';
    }
  }
}
