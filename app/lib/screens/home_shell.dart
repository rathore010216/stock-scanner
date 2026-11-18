import 'package:flutter/material.dart';

import '../services/portfolio_service.dart';
import '../widgets/responsive.dart';
import 'chart_screen.dart';
import 'matches_screen.dart';
import 'portfolio_screen.dart';
import 'watchlist_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  // Desktop web layout only: the stock open in the right-hand pane.
  final _selected = ValueNotifier<SelectedStock?>(null);

  static const _tabs = [
    MatchesScreen(),
    WatchlistScreen(),
    PortfolioScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Create the portfolio with starting capital on first sign-in.
    PortfolioService().ensureInit();
  }

  @override
  void dispose() {
    _selected.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The scope is always provided; openStock() only uses the side pane when
    // the window is wide (web), so the phone keeps pushing screens.
    return StockDetailScope(
      notifier: _selected,
      child: isWideWeb(context) ? _wide(context) : _narrow(),
    );
  }

  // Phone / narrow window: unchanged bottom-navigation layout.
  Widget _narrow() => Scaffold(
        body: IndexedStack(index: _index, children: _tabs),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.filter_list), label: 'Screener'),
            NavigationDestination(
                icon: Icon(Icons.star_border), label: 'Watchlist'),
            NavigationDestination(
                icon: Icon(Icons.account_balance_wallet), label: 'Portfolio'),
          ],
        ),
      );

  // Desktop web: side menu | list | selected stock.
  Widget _wide(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final listWidth = (width * 0.36).clamp(420.0, 620.0);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: width >= 1300,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: width >= 1300
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Icon(Icons.query_stats,
                  size: 32, color: Theme.of(context).colorScheme.primary),
            ),
            destinations: const [
              NavigationRailDestination(
                  icon: Icon(Icons.filter_list), label: Text('Screener')),
              NavigationRailDestination(
                  icon: Icon(Icons.star_border), label: Text('Watchlist')),
              NavigationRailDestination(
                  icon: Icon(Icons.account_balance_wallet),
                  label: Text('Portfolio')),
            ],
          ),
          const VerticalDivider(width: 1),
          SizedBox(
            width: listWidth,
            child: IndexedStack(index: _index, children: _tabs),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: ValueListenableBuilder<SelectedStock?>(
              valueListenable: _selected,
              builder: (context, sel, _) => sel == null
                  ? const _DetailPlaceholder()
                  : ChartScreen(
                      key: ValueKey(sel.symbol),
                      symbol: sel.symbol,
                      triggered: sel.triggered,
                      onClose: () => _selected.value = null,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailPlaceholder extends StatelessWidget {
  const _DetailPlaceholder();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.candlestick_chart_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('Select a stock to see its chart and financials',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
}
