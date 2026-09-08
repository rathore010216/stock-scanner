import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/portfolio_service.dart';
import '../services/stock_service.dart';
import 'chart_screen.dart';

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
          ),        ],
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
                _summaryCard(totalValue, p.cash, holdingsValue, totalPnl,
                    totalPnlPct, dayPnl),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showManualBuyDialog,
        icon: const Icon(Icons.add),
        label: const Text('Buy stock'),
      ),
    );
  }

  Future<void> _showManualBuyDialog() async {
    final symbolController = TextEditingController();
    final priceController = TextEditingController();
    final qtyController = TextEditingController(text: '1');
    final result = await showDialog<({String symbol, int qty, double price})>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          final qty = int.tryParse(qtyController.text) ?? 0;
          final price = double.tryParse(priceController.text) ?? 0;
          final cost = qty * price;
          return AlertDialog(
            title: const Text('Buy any stock'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: symbolController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'NSE symbol (e.g. TATASTEEL)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Buy price (₹)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Quantity (whole shares)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 8),
                  Text('Estimated cost: ₹${cost.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                    'You enter the symbol and price yourself. Paper trade — '
                    'not real money, not linked to a live feed.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: (symbolController.text.trim().isNotEmpty &&
                        qty > 0 &&
                        price > 0)
                    ? () => Navigator.pop(ctx, (
                          symbol: symbolController.text.trim().toUpperCase(),
                          qty: qty,
                          price: price,
                        ))
                    : null,
                child: const Text('Buy'),
              ),
            ],
          );
        });
      },
    );
    if (result == null) return;
    try {
      await _portfolio.buy(result.symbol, result.qty, result.price);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Bought ${result.qty} ${result.symbol} @ '
                '₹${result.price.toStringAsFixed(2)}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is StateError ? e.message : 'Buy failed')));
      }
    }
  }

  Widget _summaryCard(double totalValue, double cash, double holdingsValue,
      double totalPnl, double totalPnlPct, double dayPnl) {
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
                    child: _stat('Holdings value',
                        _money(holdingsValue), Colors.black87)),
                Expanded(
                    child: _stat('Cash', _money(cash), Colors.black87)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _stat(
                        'Total P/L',
                        '${totalPnl >= 0 ? '+' : ''}${_money(totalPnl)}'
                            ' (${totalPnlPct.toStringAsFixed(2)}%)',
                        pnlColor)),
                Expanded(
                    child: _stat(
                        "Day's P/L",
                        '${dayPnl >= 0 ? '+' : ''}${_money(dayPnl)}',
                        dayColor)),
              ],
            ),
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

    // Stop-loss / target status against the current price.
    final hasPrice = px != null;
    final stopHit = hasPrice && h.stopHit(last);
    final targetHit = hasPrice && h.targetHit(last);

    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text(h.symbol,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                '${h.qty} @ avg ₹${h.avgPrice.toStringAsFixed(2)}  ·  '
                'now ₹${last.toStringAsFixed(2)}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${pnl >= 0 ? '+' : ''}${_money(pnl)}',
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.w600)),
                    Text('${pnlPct.toStringAsFixed(2)}%',
                        style: TextStyle(color: color, fontSize: 12)),
                  ],
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 34),
                    foregroundColor: Colors.red,
                  ),
                  onPressed: () => _showSellDialog(h, last),
                  child: const Text('Sell'),
                ),
              ],
            ),
            // Tap the row to view the stock's chart/data.
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ChartScreen(symbol: h.symbol),
            )),
          ),
          // SL/Target badges + set button.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                if (h.stopLoss != null)
                  _levelBadge(
                    'SL ₹${h.stopLoss!.toStringAsFixed(2)}',
                    stopHit ? Colors.red : Colors.red.shade300,
                    filled: stopHit,
                  ),
                if (h.stopLoss != null && h.target != null)
                  const SizedBox(width: 6),
                if (h.target != null)
                  _levelBadge(
                    'TGT ₹${h.target!.toStringAsFixed(2)}',
                    targetHit ? Colors.green : Colors.green.shade400,
                    filled: targetHit,
                  ),
                if (stopHit || targetHit) ...[
                  const SizedBox(width: 6),
                  Text(
                    stopHit ? 'Stop hit' : 'Target hit',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: stopHit
                            ? Colors.red.shade700
                            : Colors.green.shade700),
                  ),
                ],
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 30),
                  ),
                  icon: const Icon(Icons.tune, size: 16),
                  label: Text(
                      (h.stopLoss == null && h.target == null)
                          ? 'Set SL/Target'
                          : 'Edit SL/Target',
                      style: const TextStyle(fontSize: 12)),
                  onPressed: () => _showLevelsDialog(h),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelBadge(String text, Color color, {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: filled ? Colors.white : color,
        ),
      ),
    );
  }

  Future<void> _showLevelsDialog(Holding h) async {
    final stopController = TextEditingController(
        text: h.stopLoss != null ? h.stopLoss!.toStringAsFixed(2) : '');
    final targetController = TextEditingController(
        text: h.target != null ? h.target!.toStringAsFixed(2) : '');
    final result = await showDialog<({double? stop, double? target})>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          final stop = double.tryParse(stopController.text.trim());
          final target = double.tryParse(targetController.text.trim());
          // Validation: SL should be below avg, target above (soft warnings).
          String? warn;
          if (stop != null && target != null && stop >= target) {
            warn = 'Stop-loss should be below the target.';
          }
          return AlertDialog(
            title: Text('SL / Target · ${h.symbol}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Avg buy ₹${h.avgPrice.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: stopController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Stop-loss price (₹)',
                      hintText: 'leave blank to clear',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: targetController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Target price (₹)',
                      hintText: 'leave blank to clear',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  if (warn != null) ...[
                    const SizedBox(height: 8),
                    Text(warn,
                        style: const TextStyle(
                            color: Colors.orange, fontSize: 12)),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Paper alerts only — the app flags when the price crosses '
                    'a level during market-hours refresh. It does not auto-sell.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(
                    ctx, (stop: stop, target: target)),
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );
    if (result == null) return;
    try {
      await _portfolio.setLevels(h.symbol, result.stop, result.target);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Updated SL/Target for ${h.symbol}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is StateError ? e.message : 'Update failed')));
      }
    }
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
