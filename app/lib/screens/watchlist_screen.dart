import 'package:flutter/material.dart';

import '../services/portfolio_service.dart';
import '../services/stock_service.dart';
import 'chart_screen.dart';

/// A simple watchlist — track symbols without paper-buying them.
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final _portfolio = PortfolioService();
  final _stock = StockService();

  final Map<String, ({double last, double prev})> _prices = {};
  bool _pricesLoading = false;

  Future<void> _loadPrices(List<String> symbols) async {
    final missing = symbols.where((s) => !_prices.containsKey(s)).toList();
    if (missing.isEmpty) return;
    setState(() => _pricesLoading = true);
    for (final s in missing) {
      final p = await _stock.lastTwoCloses(s);
      if (p != null) _prices[s] = p;
    }
    if (mounted) setState(() => _pricesLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Watchlist'),
        actions: [
          if (_pricesLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
        ],
      ),
      body: StreamBuilder<List<String>>(
        stream: _portfolio.watchlistStream(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final symbols = snap.data!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _loadPrices(symbols);
          });

          if (symbols.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Your watchlist is empty.\n\nTap + to add a symbol, or use '
                  '"Watch" on a stock in the Screener tab.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              _prices.clear();
              await _loadPrices(symbols);
            },
            child: ListView.separated(
              itemCount: symbols.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = symbols[i];
                final px = _prices[s];
                final last = px?.last;
                final prev = px?.prev;
                final dayChg = (last != null && prev != null && prev > 0)
                    ? (last - prev) / prev * 100
                    : null;
                final chgColor = (dayChg ?? 0) >= 0
                    ? Colors.green.shade700
                    : Colors.red.shade700;
                return ListTile(
                  title: Text(s,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: last != null
                      ? Text('₹${last.toStringAsFixed(2)}')
                      : const Text('tap to load price',
                          style: TextStyle(color: Colors.grey)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (dayChg != null)
                        Text(
                          '${dayChg >= 0 ? '+' : ''}${dayChg.toStringAsFixed(2)}%',
                          style: TextStyle(
                              color: chgColor, fontWeight: FontWeight.w600),
                        ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => _portfolio.removeFromWatchlist(s),
                      ),
                    ],
                  ),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChartScreen(symbol: s),
                  )),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add symbol'),
      ),
    );
  }

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
    final symbol = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add to watchlist'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'NSE symbol (e.g. TATASTEEL)',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (symbol == null || symbol.trim().isEmpty) return;
    try {
      await _portfolio.addToWatchlist(symbol);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is StateError ? e.message : 'Could not add')));
      }
    }
  }
}
