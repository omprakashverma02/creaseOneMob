import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../core/cricket.dart';
import '../core/theme.dart';
import '../data/crease_api.dart';
import '../services/auth_service.dart';

extension ContextX on BuildContext {
  CreaseApi get api => read<CreaseApi>();
  AuthService get auth => read<AuthService>();

  void toast(String msg, {bool error = false, bool success = false}) {
    final m = ScaffoldMessenger.maybeOf(this);
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.live : (success ? AppColors.success : AppColors.surfaceHigh),
      duration: Duration(seconds: error ? 4 : 2),
    ));
  }

  Future<T?> push<T>(Widget page) => Navigator.of(this).push<T>(MaterialPageRoute(builder: (_) => page));
}

Future<bool> confirmDialog(BuildContext context, {required String title, String? message, String ok = 'Confirm', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.live) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

Future<String?> promptText(BuildContext context, {required String title, String? initial, String? hint, TextInputType? keyboard, int maxLines = 1}) async {
  final ctrl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: keyboard,
        maxLines: maxLines,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Save')),
      ],
    ),
  );
  return r;
}

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = 64});
  final double height;
  @override
  Widget build(BuildContext context) => Image.asset('assets/images/logo.png', height: height, fit: BoxFit.contain);
}

class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.size = 40, this.fallback, this.circle = true, this.fit = BoxFit.cover});
  final String? url;
  final double size;
  final Widget? fallback;
  final bool circle;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final resolved = AppConfig.resolveImage(url);
    final fb = fallback ?? Icon(Icons.image_outlined, size: size * 0.5, color: AppColors.textLo);
    Widget child = resolved == null
        ? fb
        : CachedNetworkImage(
            imageUrl: resolved,
            width: size,
            height: size,
            fit: fit,
            errorWidget: (_, __, ___) => fb,
            placeholder: (_, __) => fb,
          );
    child = SizedBox(width: size, height: size, child: Center(child: child));
    return circle ? ClipOval(child: child) : ClipRRect(borderRadius: BorderRadius.circular(10), child: child);
  }
}

class TeamBadge extends StatelessWidget {
  const TeamBadge({super.key, required this.name, this.logoUrl, this.color, this.size = 40});
  final String name;
  final String? logoUrl;
  final String? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.fromHex(color);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [c, Color.lerp(c, Colors.black, 0.45)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      alignment: Alignment.center,
      child: Text(Fmt.shortName(name, 3), style: TextStyle(fontWeight: FontWeight.w900, fontSize: size * 0.3, color: Colors.white)),
    );
    if (AppConfig.resolveImage(logoUrl) == null) return fallback;
    return Container(
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06), border: Border.all(color: c.withValues(alpha: 0.6), width: 1.5)),
      child: NetImage(logoUrl, size: size, fallback: fallback, fit: BoxFit.contain),
    );
  }
}

class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({super.key, required this.name, this.imageUrl, this.size = 40});
  final String name;
  final String? imageUrl;
  final double size;
  @override
  Widget build(BuildContext context) {
    final fb = CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.surfaceHigh,
      child: Text(Fmt.initials(name), style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w800, color: AppColors.textHi)),
    );
    if (AppConfig.resolveImage(imageUrl) == null) return fb;
    return NetImage(imageUrl, size: size, fallback: fb);
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});
  final String? label;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          if (label != null) ...[const SizedBox(height: 12), Text(label!, style: const TextStyle(color: AppColors.textMid))],
        ]),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textLo),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMid)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ],
          ]),
        ),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, this.subtitle, this.action});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withValues(alpha: 0.12)),
              child: Icon(icon, size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMid)),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ]),
        ),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 8)});
  final String text;
  final Widget? trailing;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Container(width: 4, height: 16, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Expanded(child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, letterSpacing: 1.1, color: AppColors.textMid))),
          if (trailing != null) trailing!,
        ]),
      );
}

class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.label = 'LIVE'});
  final String label;
  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppColors.live.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          FadeTransition(opacity: _c, child: const CircleAvatar(radius: 3.5, backgroundColor: AppColors.live)),
          const SizedBox(width: 5),
          Text(widget.label, style: const TextStyle(color: AppColors.live, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
        ]),
      );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = AppColors.primary, this.icon});
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.35))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        ]),
      );
}

/// Ball pip used in "this over" rows and commentary.
class BallPip extends StatelessWidget {
  const BallPip(this.label, {super.key, this.size = 30});
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l = label.toUpperCase();
    Color bg;
    if (l.startsWith('W') && !l.startsWith('WD')) {
      bg = AppColors.wicket;
    } else if (l == '6') {
      bg = AppColors.six;
    } else if (l == '4') {
      bg = AppColors.four;
    } else if (l.startsWith('WD') || l.startsWith('NB') || l.startsWith('B') || l.startsWith('LB')) {
      bg = AppColors.extra;
    } else if (l == '0' || l == '•') {
      bg = AppColors.dot;
    } else {
      bg = AppColors.surfaceHigh;
    }
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.only(right: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg, border: Border.all(color: Colors.white.withValues(alpha: 0.12))),
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Text(l == '0' ? '•' : label, style: TextStyle(fontWeight: FontWeight.w900, fontSize: size * 0.38, color: Colors.white)),
        ),
      ),
    );
  }
}

class GradientCard extends StatelessWidget {
  const GradientCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.gradient});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Gradient? gradient;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: gradient ?? AppColors.cardGradient,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            padding: padding,
            child: child,
          ),
        ),
      );
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.k, this.v, {super.key});
  final String k;
  final String v;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: const TextStyle(color: AppColors.textMid))),
          Expanded(child: Text(v.isEmpty ? '-' : v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color ?? AppColors.textHi)),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.textMid, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Generic future loader with pull-to-refresh friendly retry.
class AsyncBuilder<T> extends StatelessWidget {
  const AsyncBuilder({super.key, required this.future, required this.builder, this.onRetry});
  final Future<T> future;
  final Widget Function(BuildContext, T) builder;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: future,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) return const LoadingView();
          if (s.hasError) return ErrorView(message: s.error.toString(), onRetry: onRetry);
          return builder(c, s.data as T);
        },
      );
}

/// Searchable single-pick bottom sheet.
Future<Map<String, dynamic>?> pickFromList(
  BuildContext context, {
  required String title,
  required List<Map<String, dynamic>> items,
  required String Function(Map<String, dynamic>) label,
  String Function(Map<String, dynamic>)? subtitle,
  Widget Function(Map<String, dynamic>)? leading,
  bool Function(Map<String, dynamic>)? disabled,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (c) => _PickSheet(title: title, items: items, label: label, subtitle: subtitle, leading: leading, disabled: disabled),
  );
}

class _PickSheet extends StatefulWidget {
  const _PickSheet({required this.title, required this.items, required this.label, this.subtitle, this.leading, this.disabled});
  final String title;
  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) label;
  final String Function(Map<String, dynamic>)? subtitle;
  final Widget Function(Map<String, dynamic>)? leading;
  final bool Function(Map<String, dynamic>)? disabled;
  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final filtered = widget.items.where((e) => widget.label(e).toLowerCase().contains(q.toLowerCase())).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (c, sc) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        if (widget.items.length > 8)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search'),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Nothing to pick', style: TextStyle(color: AppColors.textMid)))
              : ListView.builder(
                  controller: sc,
                  itemCount: filtered.length,
                  itemBuilder: (c, i) {
                    final it = filtered[i];
                    final dis = widget.disabled?.call(it) ?? false;
                    return ListTile(
                      enabled: !dis,
                      leading: widget.leading?.call(it),
                      title: Text(widget.label(it), style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: widget.subtitle == null ? null : Text(widget.subtitle!(it)),
                      onTap: dis ? null : () => Navigator.pop(context, it),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
