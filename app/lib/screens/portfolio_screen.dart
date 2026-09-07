import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/portfolio_service.dart';
import '../services/stock_service.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  final _portfolio = PortfolioService();
  final _stock = StockService();
  final _auth = AuthService();

  // symbol -> (last, prev) close prices, fetched for held symbols.
  final Map<String, ({double last, double prev})> _prices = {};
  bool _pricesLoading = false;

  Future<void> _loadPrices(List<Holding> holdings) async {
    setState(() => _pricesLoading = true);
    for (final h in holdings) {
      if (!_prices.containsKey(h.symbol)) {
        final p = await _stock.lastTwoCloses(h.symbol);
        if (p != null) _prices[h.symbol] = p;
      }
    }
    if (mounted) setState(() => _pricesLoading = false);
  }

  String _money(double v) => '₹${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Portfolio'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'reset') {
                final ok = await _confirmReset();
                if (ok) {
                  _prices.clear();
                  await _portfolio.reset();
                }
              } else if (v == 'signout') {
                await _auth.signOut();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reset', child: Text('Reset portfolio')),
              PopupMenuItem(value: 'signout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<Portfolio>(
        stream: _portfolio.stream(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final p = snap.data!;
          // Kick off price loading for any new holdings.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _loadPrices(p.holdings);
          });

          // Compute values.
          double holdingsValue = 0;
          double dayPnl = 0;
          double unrealized = 0;
          for (final h in p.holdings) {
            final px = _prices[h.symbol];
            final last = px?.last ?? h.avgPrice;
            final prev = px?.prev ?? last;
            holdingsValue += h.qty * last;
            unrealized += (last - h.avgPrice) * h.qty;
            dayPnl += (last - prev) * h.qty;
          }
          final totalValue = p.cash + holdingsValue;
          final totalPnl = totalValue - kStartingCapital;
          final totalPnlPct = totalPnl / kStartingCapital * 100;

          return RefreshIndicator(
            onRefresh: () async {
              _prices.clear();
              await _loadPrices(p.holdings);
            },
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _summaryCard(totalValue, p.cash, totalPnl, totalPnlPct, dayPnl),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('HOLDINGS',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (_pricesLoading)
                      const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
                const SizedBox(height: 4),
                if (p.holdings.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No holdings yet.\nBuy a stock from the Screener tab.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ...p.holdings.map((h) => _holdingTile(h)),
                const SizedBox(height: 16),
                const Text(
                  'Paper trading · prices at last close · not real money · '
                  'not investment advice.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _summaryCard(double totalValue, double cash, double totalPnl,
      double totalPnlPct, double dayPnl) {
    final pnlColor = totalPnl >= 0 ? Colors.green.shade700 : Colors.red.shade700;
    final dayColor = dayPnl >= 0 ? Colors.green.shade700 : Colors.red.shade700;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Total value'),
            Text(_money(totalValue),
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _stat('Cash', _money(cash), Colors.black87)),
                Expanded(
                    child: _stat(
                        'Total P/L',
                        '${totalPnl >= 0 ? '+' : ''}${_money(totalPnl)}'
                            ' (${totalPnlPct.toStringAsFixed(2)}%)',
                        pnlColor)),
              ],
            ),
            const SizedBox(height: 8),
            _stat(
                "Day's P/L",
                '${dayPnl >= 0 ? '+' : ''}${_money(dayPnl)}',
                dayColor),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value,
            style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  Widget _holdingTile(Holding h) {
    final px = _prices[h.symbol];
    final last = px?.last ?? h.avgPrice;
    final pnl = (last - h.avgPrice) * h.qty;
    final pnlPct = h.avgPrice > 0
        ? (last - h.avgPrice) / h.avgPrice * 100
        : 0.0;
    final color = pnl >= 0 ? Colors.green.shade700 : Colors.red.shade700;
    return Card(
      child: ListTile(
        title: Text(h.symbol,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${h.qty} @ avg ₹${h.avgPrice.toStringAsFixed(2)}  ·  '
            'now ₹${last.toStringAsFixed(2)}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${pnl >= 0 ? '+' : ''}${_money(pnl)}',
                style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            Text('${pnlPct.toStringAsFixed(2)}%',
                style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
        onTap: () => _showSellDialog(h, last),
      ),
    );
  }

  Future<void> _showSellDialog(Holding h, double price) async {
    final qtyController = TextEditingController(text: '${h.qty}');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          final qty = int.tryParse(qtyController.text) ?? 0;
          final proceeds = qty * price;
          final pnl = (price - h.avgPrice) * qty;
          return AlertDialog(
            title: Text('Sell ${h.symbol}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('You hold ${h.qty} @ avg '
                    '₹${h.avgPrice.toStringAsFixed(2)}'),
                Text('Sell price (last close): ₹${price.toStringAsFixed(2)}'),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantity to sell',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setLocal(() {}),
                ),
                const SizedBox(height: 8),
                Text('Proceeds: ₹${proceeds.toStringAsFixed(2)}'),
                Text(
                    'Realized P/L: ${pnl >= 0 ? '+' : ''}'
                    '₹${pnl.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: pnl >= 0 ? Colors.green : Colors.red)),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: (qty > 0 && qty <= h.qty)
                    ? () => Navigator.pop(ctx, qty)
                    : null,
                child: const Text('Sell'),
              ),
            ],
          );
        });
      },
    );
    if (result == null) return;
    try {
      await _portfolio.sell(h.symbol, result, price);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Sold $result ${h.symbol}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is StateError ? e.message : 'Sell failed')));
      }
    }
  }

  Future<bool> _confirmReset() async {
    return (await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Reset portfolio?'),
            content: const Text(
                'This clears all holdings and resets cash to ₹100,000.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Reset')),
            ],
          ),
        )) ??
        false;
  }
}
