import 'dart:async';
import 'package:flutter/material.dart';

import '../models/stock_data.dart';
import '../services/stock_service.dart';
import '../services/portfolio_service.dart';
import 'chart_screen.dart';

/// Human-friendly labels for screener keys.
const screenerLabels = {
  'trend': 'Uptrend',
  'breakout_52w': '52w breakout',
  'volume_surge': 'Volume surge',
  'momentum': 'Momentum',
  'rsi2': 'RSI-2 dip',
  'bollinger_squeeze': 'Squeeze',
  'macd_cross': 'MACD cross',
  'cup_handle': 'Cup & handle',
};

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  final _service = StockService();

  bool _loading = false;
  String? _error;
  String? _asOf;
  String _disclaimer = '';
  List<String> _allScreeners = [];
  List<StockMatch> _matches = [];
  Map<String, double> _quotes = {};
  String? _quotesAsOf;

  // Toggle state: which screeners are active filters.
  final Set<String> _active = {};
  int _minHits = 1;
  bool _loaded = false; // whether the user has loaded today's picks yet

  @override
  void initState() {
    super.initState();
    // Do NOT auto-fetch on open (keeps reads lean). User taps "Load".
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _service.fetchLatest().timeout(
          const Duration(seconds: 20));
      // Quotes are best-effort; don't let them block or fail the load.
      Map<String, double> quotes = {};
      String? quotesAsOf;
      try {
        quotes = await _service
            .fetchQuotes()
            .timeout(const Duration(seconds: 15));
        quotesAsOf = await _service
            .quotesAsOf()
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        // ignore quote failures; show matches without live prices
      }
      setState(() {
        _asOf = r.asOf;
        _disclaimer = r.disclaimer;
        _allScreeners = r.screeners;
        _matches = r.matches;
        _quotes = quotes;
        _quotesAsOf = quotesAsOf;
        _active
          ..clear()
          ..addAll(r.screeners); // all active by default
        _loading = false;
        _loaded = true;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load data. Tap Retry.\n$e';
        _loading = false;
      });
    }
  }

  /// Matches filtered by active screeners + min-hits.
  List<StockMatch> get _filtered {
    final out = _matches.where((m) {
      final hitsActive = m.triggered.where(_active.contains).toList();
      return hitsActive.length >= _minHits;
    }).toList();
    // Sort by # of ACTIVE screeners hit, then symbol.
    out.sort((a, b) {
      final ah = a.triggered.where(_active.contains).length;
      final bh = b.triggered.where(_active.contains).length;
      if (ah != bh) return bh - ah;
      return a.symbol.compareTo(b.symbol);
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NSE Swing Screener'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('About'),
                content: const Text(
                  'NSE Swing Screener\n\n'
                  'Created and owned by Pawan.\n'
                  'Contact: pawan88@gmail.com\n\n'
                  'This app is a research/screening tool only and is NOT '
                  'investment advice. Do your own analysis before trading.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : !_loaded
                  ? _loadPrompt()
                  : _buildBody(),
    );
  }

  Widget _loadPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.query_stats, size: 56, color: Color(0xFF1565C0)),
            const SizedBox(height: 16),
            const Text(
              "Today's screener picks are ready.\nTap to load them.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.download),
              label: const Text('Load picks'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final filtered = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Text(_asOf != null ? 'As of $_asOf close' : 'No data',
                  style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              Text('${filtered.length} matches',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        // Screener toggle chips.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final key in _allScreeners)
                FilterChip(
                  label: Text(screenerLabels[key] ?? key,
                      style: const TextStyle(fontSize: 12)),
                  selected: _active.contains(key),
                  onSelected: (sel) => setState(() {
                    if (sel) {
                      _active.add(key);
                    } else {
                      _active.remove(key);
                    }
                  }),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        // Min-hits selector.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Text('Min screeners: '),
              DropdownButton<int>(
                value: _minHits,
                items: [1, 2, 3, 4]
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                    .toList(),
                onChanged: (v) => setState(() => _minHits = v ?? 1),
              ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    setState(() => _active..clear()..addAll(_allScreeners)),
                child: const Text('All'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: filtered.isEmpty
                ? ListView(children: const [
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No matches for the selected screeners.\n'
                        'Enable more chips or lower the minimum.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  ])
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) => _MatchTile(
                        match: filtered[i],
                        active: _active,
                        livePrice: _quotes[filtered[i].symbol]),
                  ),
          ),
        ),
        if (_disclaimer.isNotEmpty)
          Container(
            width: double.infinity,
            color: Colors.amber.shade50,
            padding: const EdgeInsets.all(8),
            child: Text(_disclaimer,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.brown)),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: const Text(
            'Created & owned by Pawan · pawan88@gmail.com',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ),
      ],
    );
  }
}

class _MatchTile extends StatelessWidget {
  final StockMatch match;
  final Set<String> active;
  final double? livePrice;
  const _MatchTile(
      {required this.match, required this.active, this.livePrice});

  double get _price => livePrice ?? match.price;

  @override
  Widget build(BuildContext context) {
    final activeHits =
        match.triggered.where(active.contains).toList();
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF1565C0),
        child: Text('${activeHits.length}',
            style: const TextStyle(color: Colors.white)),
      ),
      title: Text(match.symbol,
          style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Wrap(
        spacing: 4,
        runSpacing: -6,
        children: [
          for (final t in activeHits)
            Chip(
              label: Text(screenerLabels[t] ?? t,
                  style: const TextStyle(fontSize: 10)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹${_price.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (match.rsi != null)
                Text('RSI ${match.rsi}',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Add to watchlist',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.star_border, size: 22),
            onPressed: () async {
              try {
                await PortfolioService().addToWatchlist(match.symbol);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('${match.symbol} added to watchlist')));
                }
              } catch (_) {}
            },
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 34),
            ),
            onPressed: () => _showBuyDialog(context),
            child: const Text('Buy'),
          ),
        ],
      ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChartScreen(symbol: match.symbol),
      )),
    );
  }

  Future<void> _showBuyDialog(BuildContext context) async {
    final qtyController = TextEditingController(text: '1');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          final qty = int.tryParse(qtyController.text) ?? 0;
          final cost = qty * _price;
          return AlertDialog(
            title: Text('Buy ${match.symbol}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Price: ₹${_price.toStringAsFixed(2)}'),
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
                const Text('Paper trade at last close. Not real money.',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: qty > 0 ? () => Navigator.pop(ctx, qty) : null,
                child: const Text('Buy'),
              ),
            ],
          );
        });
      },
    );
    if (result == null) return;
    try {
      await PortfolioService().buy(match.symbol, result, _price);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Bought $result ${match.symbol} @ '
                '₹${_price.toStringAsFixed(2)}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is StateError ? e.message : 'Buy failed')));
      }
    }
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
