import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../screens/chart_screen.dart';

/// Width at which the WEB build switches to the desktop layout.
const double kWideBreakpoint = 1000;

/// True only for the web build on a wide window. The Android app is never
/// "wide", so its layout is untouched.
bool isWideWeb(BuildContext context) =>
    kIsWeb && MediaQuery.sizeOf(context).width >= kWideBreakpoint;

/// The stock shown in the desktop layout's right-hand pane.
typedef SelectedStock = ({String symbol, List<String>? triggered});

/// Provided by HomeShell in the desktop layout only.
class StockDetailScope extends InheritedNotifier<ValueNotifier<SelectedStock?>> {
  const StockDetailScope({
    super.key,
    required ValueNotifier<SelectedStock?> super.notifier,
    required super.child,
  });

  static ValueNotifier<SelectedStock?>? _of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<StockDetailScope>()
      ?.notifier;

  /// Currently selected symbol (desktop layout), for highlighting list rows.
  static String? selectedSymbol(BuildContext context) =>
      _of(context)?.value?.symbol;
}

/// Open a stock's chart: in the right-hand pane on the desktop web layout,
/// otherwise as a new screen (phone app, narrow browser window).
void openStock(BuildContext context, String symbol, {List<String>? triggered}) {
  final scope = context.getInheritedWidgetOfExactType<StockDetailScope>();
  if (scope != null && isWideWeb(context)) {
    scope.notifier!.value = (symbol: symbol, triggered: triggered);
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ChartScreen(symbol: symbol, triggered: triggered),
  ));
}
