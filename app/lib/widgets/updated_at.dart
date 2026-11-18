import 'dart:async';

import 'package:flutter/material.dart';

import '../services/stock_service.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// ISO timestamp -> "05 Nov 2026, 14:32" in local time, or null if unparsable.
String? formatUpdated(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso);
  if (t == null) return null;
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)} ${_months[l.month - 1]} ${l.year}, '
      '${two(l.hour)}:${two(l.minute)}';
}

/// How long ago [iso] was: "just now", "4 min ago", "2 h 5 min ago",
/// "3 days ago". Null if unparsable.
String? formatAge(String? iso, {DateTime? now}) {
  final t = iso == null ? null : DateTime.tryParse(iso);
  if (t == null) return null;
  final d = (now ?? DateTime.now()).toUtc().difference(t.toUtc());
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) {
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours} h ago' : '${d.inHours} h $m min ago';
  }
  return d.inDays == 1 ? '1 day ago' : '${d.inDays} days ago';
}

/// "Updated 05 Nov 2026, 14:32 · 4 min ago" for a fixed timestamp. The age is
/// recomputed every 30 s, and turns orange when older than [staleAfter].
class AgeLabel extends StatefulWidget {
  final String? iso;
  final String prefix;
  final Duration staleAfter;
  final TextAlign textAlign;
  const AgeLabel({
    super.key,
    required this.iso,
    this.prefix = 'Updated',
    this.staleAfter = const Duration(minutes: 10),
    this.textAlign = TextAlign.start,
  });

  @override
  State<AgeLabel> createState() => _AgeLabelState();
}

class _AgeLabelState extends State<AgeLabel> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final when = formatUpdated(widget.iso);
    final age = formatAge(widget.iso);
    final t = widget.iso == null ? null : DateTime.tryParse(widget.iso!);
    final stale = t != null &&
        DateTime.now().toUtc().difference(t.toUtc()) > widget.staleAfter;
    final base = Theme.of(context).textTheme.bodySmall;
    return Text(
      when == null ? '${widget.prefix}: —' : '${widget.prefix} $when · $age',
      textAlign: widget.textAlign,
      style: base?.copyWith(
        color: stale ? Colors.orange.shade800 : Colors.grey.shade700,
        fontWeight: stale ? FontWeight.w600 : null,
      ),
    );
  }
}

/// Live "Prices updated 05 Nov 2026, 14:32 · 4 min ago", driven by
/// /stock/quotesAsOf (written by the backend after every refresh), so the time
/// changes on each refresh and the age keeps counting in between. Each
/// instance has its own listener (Firebase de-dupes them into one server
/// listen), so a screen opened later still gets the current value at once.
class UpdatedAtLabel extends StatefulWidget {
  final String prefix;
  final TextAlign textAlign;
  const UpdatedAtLabel(
      {super.key, this.prefix = 'Prices updated', this.textAlign = TextAlign.start});

  @override
  State<UpdatedAtLabel> createState() => _UpdatedAtLabelState();
}

class _UpdatedAtLabelState extends State<UpdatedAtLabel> {
  late final Stream<String?> _stream = StockService().quotesAsOfStream();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: _stream,
      builder: (context, snap) => AgeLabel(
        iso: snap.data,
        prefix: widget.prefix,
        textAlign: widget.textAlign,
      ),
    );
  }
}
