import '../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';

/// Centers content and limits its width on large (desktop) windows.
class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, required this.child, this.width = 960});
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: child,
        ),
      );
}

class DeviceAvatar extends StatelessWidget {
  const DeviceAvatar({super.key, required this.device, this.size = 44});
  final Device device;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = device.isSelf
        ? (cs.primary, cs.onPrimary)
        : device.isGateway
            ? (cs.tertiaryContainer, cs.onTertiaryContainer)
            : device.online
                ? (cs.secondaryContainer, cs.onSecondaryContainer)
                : (cs.surfaceContainerHighest, cs.onSurfaceVariant);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(device.type.icon, color: fg, size: size * 0.52),
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key, this.color, this.onColor});
  final String label;
  final Color? color;
  final Color? onColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color ?? cs.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: onColor ?? cs.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// Row with label + selectable value + copy action.
/// Key / value row rendered as a compact table line. Tap copies the value.
/// Use inside [TableCard] (rows with empty values are skipped there).
class InfoRow extends StatelessWidget {
  const InfoRow(this.icon, this.label, this.value, {super.key, this.copy = true});
  final IconData icon;
  final String label;
  final String? value;
  final bool copy;

  bool get visible => value != null && value!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: copy ? () => copyText(context, value!) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            Icon(icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 1),
                  Text(value!,
                      style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ),
            ),
            if (copy)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.copy_rounded,
                    size: 15, color: cs.onSurfaceVariant.withValues(alpha: 0.45)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Rounded, subtle container that stacks rows with hairline dividers.
class TableCard extends StatelessWidget {
  const TableCard({super.key, required this.children, this.header, this.margin});
  final List<Widget> children;
  final List<TableCol>? header;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows =
        children.where((w) => w is! InfoRow || w.visible).toList();
    if (rows.isEmpty && header == null) return const SizedBox.shrink();
    final divider = Divider(
        height: 1, thickness: 1, color: cs.outlineVariant.withValues(alpha: 0.45));
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) TableHeaderRow(cols: header!),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0 || header != null) divider,
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// Column definition for [TableHeaderRow] / [TableDataRow].
class TableCol {
  const TableCol(this.label, {this.flex = 1, this.width, this.align = TextAlign.left});
  final String label;
  final int flex;
  final double? width;
  final TextAlign align;
}

Widget _cell(TableCol c, Widget child) {
  final aligned = Align(
    alignment: c.align == TextAlign.right
        ? Alignment.centerRight
        : c.align == TextAlign.center
            ? Alignment.center
            : Alignment.centerLeft,
    child: child,
  );
  return c.width != null
      ? SizedBox(width: c.width, child: aligned)
      : Expanded(flex: c.flex, child: aligned);
}

class TableHeaderRow extends StatelessWidget {
  const TableHeaderRow({super.key, required this.cols});
  final List<TableCol> cols;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w600,
        );
    return Container(
      color: cs.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          for (final c in cols)
            _cell(c, Text(c.label.toUpperCase(), style: style)),
        ],
      ),
    );
  }
}

class TableDataRow extends StatelessWidget {
  const TableDataRow({super.key, required this.cols, required this.cells, this.onTap, this.onLongPress});
  final List<TableCol> cols;
  final List<Widget> cells;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            for (var i = 0; i < cols.length; i++) _cell(cols[i], cells[i]),
          ],
        ),
      ),
    );
  }
}

/// Text helper for table cells.
class CellText extends StatelessWidget {
  const CellText(this.text,
      {super.key, this.muted = false, this.bold = false, this.color, this.mono = false, this.maxLines = 1});
  final String text;
  final bool muted;
  final bool bold;
  final bool mono;
  final Color? color;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: color ?? (muted ? cs.onSurfaceVariant : null),
            fontWeight: bold ? FontWeight.w600 : null,
            fontFeatures: const [FontFeature.tabularFigures()],
            fontFamily: mono ? 'monospace' : null,
          ),
    );
  }
}

void copyText(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(tr('Copiat: $text', 'Copied: $text'))));
}

void toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return tr('acum', 'now');
  if (d.inMinutes < 60) return tr('acum ${d.inMinutes} min', '${d.inMinutes} min ago');
  if (d.inHours < 24) return tr('acum ${d.inHours} h', '${d.inHours} h ago');
  if (d.inDays < 30) return tr('acum ${d.inDays} zile', '${d.inDays} days ago');
  return '${t.day}.${t.month}.${t.year}';
}
