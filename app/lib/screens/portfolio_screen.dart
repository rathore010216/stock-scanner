import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/portfolio_service.dart';
import '../services/stock_service.dart';
import '../services/notification_service.dart';
import 'chart_screen.dart';
import 'trade_log_screen.dart';
import 'performance_screen.dart';

/// Sort options for the holdings list.
enum _HoldingSort {
  symbol,
  pnlAmountAsc, // biggest losses (amount) first
  pnlAmountDesc, // biggest gains (amount) first
  pnlPctAsc, // biggest losses (%) first
  pnlPctDesc, // biggest gains (%) first
  valueDesc, // largest position value first
}

extension _HoldingSortLabel on _HoldingSort {
  String get label {
    switch (this) {
      case _HoldingSort.symbol:
        return 'Symbol (A-Z)';
      case _HoldingSort.pnlAmountAsc:
        return 'Loss ₹ (worst first)';
      case _HoldingSort.pnlAmountDesc:
        return 'Gain ₹ (best first)';
      case _HoldingSort.pnlPctAsc:
        return 'Loss % (worst first)';
      case _HoldingSort.pnlPctDesc:
        return 'Gain % (best first)';
      case _HoldingSort.valueDesc:
        return 'Position value';
    }
  }
}

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
  bool _snapshotDone = false;

  // Current holdings sort order.
  _HoldingSort _sortMode = _HoldingSort.symbol;

  // De-dup for SL/target notifications: tracks symbols currently "in" a hit
  // zone so we notify on the crossing, not on every refresh. Cleared when the
  // price moves back out of the zone.
  final Set<String> _notifiedStop = {};
  final Set<String> _notifiedTarget = {};

  Future<void> _loadPrices(List<Holding> holdings) async {
    setState(() => _pricesLoading = true);
    for (final h in holdings) {
      if (!_prices.containsKey(h.symbol)) {
        final p = await _stock.lastTwoCloses(h.symbol);
        if (p != null) _prices[h.symbol] = p;
      }
    }
    if (mounted) setState(() => _pricesLoading = false);
    _checkAlerts(holdings);
  }

  /// Fire a local notification when a holding first crosses its SL/target.
  Future<void> _checkAlerts(List<Holding> holdings) async {
    for (final h in holdings) {
      final px = _prices[h.symbol];
      if (px == null) continue;
      final price = px.last;

      // Stop-loss.
      if (h.stopLoss != null && price <= h.stopLoss!) {
        if (!_notifiedStop.contains(h.symbol)) {
          _notifiedStop.add(h.symbol);
          await NotificationService.instance.showLevelHit(
            id: h.symbol.hashCode & 0x7fffffff,
            symbol: h.symbol,
            isStop: true,
            price: price,
            level: h.stopLoss!,
          );
        }
      } else {
        _notifiedStop.remove(h.symbol); // out of zone → allow re-notify later
      }

      // Target.
      if (h.target != null && price >= h.target!) {
        if (!_notifiedTarget.contains(h.symbol)) {
          _notifiedTarget.add(h.symbol);
          await NotificationService.instance.showLevelHit(
            id: (h.symbol.hashCode & 0x7fffffff) ^ 0x55555555,
            symbol: h.symbol,
            isStop: false,
            price: price,
            level: h.target!,
          );
        }
      } else {
        _notifiedTarget.remove(h.symbol);
      }
    }
  }

  String _money(double v) => '₹${v.toStringAsFixed(2)}';

  /// Sort holdings per the current [_sortMode], using loaded prices for P/L.
  List<Holding> _sortedHoldings(List<Holding> holdings) {
    double pnlAmt(Holding h) {
      final last = _prices[h.symbol]?.last ?? h.avgPrice;
      return (last - h.avgPrice) * h.qty;
    }

    double pnlPct(Holding h) {
      final last = _prices[h.symbol]?.last ?? h.avgPrice;
      return h.avgPrice > 0 ? (last - h.avgPrice) / h.avgPrice * 100 : 0;
    }

    double value(Holding h) {
      final last = _prices[h.symbol]?.last ?? h.avgPrice;
      return h.qty * last;
    }

    final list = [...holdings];
    switch (_sortMode) {
      case _HoldingSort.symbol:
        list.sort((a, b) => a.symbol.compareTo(b.symbol));
        break;
      case _HoldingSort.pnlAmountAsc:
        list.sort((a, b) => pnlAmt(a).compareTo(pnlAmt(b)));
        break;
      case _HoldingSort.pnlAmountDesc:
        list.sort((a, b) => pnlAmt(b).compareTo(pnlAmt(a)));
        break;
      case _HoldingSort.pnlPctAsc:
        list.sort((a, b) => pnlPct(a).compareTo(pnlPct(b)));
        break;
      case _HoldingSort.pnlPctDesc:
        list.sort((a, b) => pnlPct(b).compareTo(pnlPct(a)));
        break;
      case _HoldingSort.valueDesc:
        list.sort((a, b) => value(b).compareTo(value(a)));
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Portfolio'),
        actions: [
          IconButton(
            tooltip: 'Performance',
            icon: const Icon(Icons.show_chart),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const PerformanceScreen(),
            )),
          ),
          IconButton(
            tooltip: 'Trade log',
            icon: const Icon(Icons.receipt_long),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const TradeLogScreen(),
            )),
          ),
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

          // Snapshot today's total value once per session, after prices are
          // loaded (so the equity curve uses live values, not avg-cost).
          if (!_snapshotDone && !_pricesLoading) {
            _snapshotDone = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _portfolio.snapshotValue(totalValue);
            });
          }

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
                    if (p.holdings.length > 1)
                      PopupMenuButton<_HoldingSort>(
                        tooltip: 'Sort holdings',
                        initialValue: _sortMode,
                        onSelected: (m) => setState(() => _sortMode = m),
                        itemBuilder: (_) => [
                          for (final m in _HoldingSort.values)
                            PopupMenuItem(value: m, child: Text(m.label)),
                        ],
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.sort, size: 18),
                            const SizedBox(width: 4),
                            Text(_sortMode.label,
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
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
                ..._sortedHoldings(p.holdings).map((h) => _holdingTile(h)),
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
          // Note row: show existing note or an "Add note" affordance.
          InkWell(
            onTap: () => _showNoteDialog(h),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    h.note == null
                        ? Icons.note_add_outlined
                        : Icons.sticky_note_2_outlined,
                    size: 15,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      h.note ?? 'Add a note',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle:
                            h.note == null ? FontStyle.italic : FontStyle.normal,
                        color: h.note == null
                            ? Colors.grey
                            : Colors.black.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showNoteDialog(Holding h) async {
    final controller = TextEditingController(text: h.note ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Note · ${h.symbol}'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'e.g. waiting for Q3 results / breakout above 450',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == null) return;
    try {
      await _portfolio.setNote(h.symbol, saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save note')));
      }
    }
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
    // Input mode: absolute price (₹) or percentage off avg buy (%).
    // Storage is always price-based; % is converted on save.
    bool percentMode = false;
    final avg = h.avgPrice;

    // Seed controllers from any existing price levels (as ₹ initially).
    final stopController = TextEditingController(
        text: h.stopLoss != null ? h.stopLoss!.toStringAsFixed(2) : '');
    final targetController = TextEditingController(
        text: h.target != null ? h.target!.toStringAsFixed(2) : '');

    // Convert a stop-loss between ₹ and % (SL is below avg → positive % down).
    double? stopToPercent(double price) =>
        avg > 0 ? (avg - price) / avg * 100 : null;
    double stopFromPercent(double pct) => avg * (1 - pct / 100);
    // Target is above avg → positive % up.
    double? targetToPercent(double price) =>
        avg > 0 ? (price - avg) / avg * 100 : null;
    double targetFromPercent(double pct) => avg * (1 + pct / 100);

    final result = await showDialog<({double? stop, double? target})>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          final rawStop = double.tryParse(stopController.text.trim());
          final rawTarget = double.tryParse(targetController.text.trim());

          // Resolve to actual prices based on the current input mode.
          final double? stopPrice = rawStop == null
              ? null
              : (percentMode ? stopFromPercent(rawStop) : rawStop);
          final double? targetPrice = rawTarget == null
              ? null
              : (percentMode ? targetFromPercent(rawTarget) : rawTarget);

          String? warn;
          if (stopPrice != null && targetPrice != null &&
              stopPrice >= targetPrice) {
            warn = 'Stop-loss should be below the target.';
          } else if (percentMode && ((rawStop != null && rawStop < 0) ||
              (rawTarget != null && rawTarget < 0))) {
            warn = 'Enter a positive % (SL is below avg, target above).';
          }

          void switchMode(bool toPercent) {
            if (toPercent == percentMode) return;
            // Convert current field values between ₹ and %.
            if (toPercent) {
              if (rawStop != null) {
                final p = stopToPercent(rawStop);
                stopController.text = p != null ? p.toStringAsFixed(2) : '';
              }
              if (rawTarget != null) {
                final p = targetToPercent(rawTarget);
                targetController.text = p != null ? p.toStringAsFixed(2) : '';
              }
            } else {
              if (rawStop != null) {
                stopController.text =
                    stopFromPercent(rawStop).toStringAsFixed(2);
              }
              if (rawTarget != null) {
                targetController.text =
                    targetFromPercent(rawTarget).toStringAsFixed(2);
              }
            }
            setLocal(() => percentMode = toPercent);
          }

          final unit = percentMode ? '%' : '₹';
          return AlertDialog(
            title: Text('SL / Target · ${h.symbol}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Avg buy ₹${avg.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  // ₹ / % mode toggle.
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Price ₹')),
                      ButtonSegment(value: true, label: Text('Percent %')),
                    ],
                    selected: {percentMode},
                    onSelectionChanged: (s) => switchMode(s.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: stopController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Stop-loss ($unit)',
                      hintText: 'leave blank to clear',
                      helperText: (percentMode && stopPrice != null)
                          ? '= ₹${stopPrice.toStringAsFixed(2)}'
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: targetController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Target ($unit)',
                      hintText: 'leave blank to clear',
                      helperText: (percentMode && targetPrice != null)
                          ? '= ₹${targetPrice.toStringAsFixed(2)}'
                          : null,
                      border: const OutlineInputBorder(),
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
                  Text(
                    percentMode
                        ? 'Percent is measured off your avg buy price — '
                            'SL below, target above. You get a notification '
                            'when a level is crossed while the app is open. '
                            'No auto-sell.'
                        : 'You get a notification when the price crosses a '
                            'level while the app is open (on the Portfolio '
                            'tab). Paper alerts only — no auto-sell.',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
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
                    ctx, (stop: stopPrice, target: targetPrice)),
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
