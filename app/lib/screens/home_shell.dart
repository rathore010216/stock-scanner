import 'package:flutter/material.dart';

import '../services/portfolio_service.dart';
import 'matches_screen.dart';
import 'portfolio_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Create the portfolio with starting capital on first sign-in.
    PortfolioService().ensureInit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [MatchesScreen(), PortfolioScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.filter_list), label: 'Screener'),
          NavigationDestination(
              icon: Icon(Icons.account_balance_wallet), label: 'Portfolio'),
        ],
      ),
    );
  }
}
