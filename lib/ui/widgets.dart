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
class InfoRow extends StatelessWidget {
  const InfoRow(this.icon, this.label, this.value, {super.key, this.copy = true});
  final IconData icon;
  final String label;
  final String? value;
  final bool copy;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return ListTile(
      leading: Icon(icon),
      title: Text(label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
      subtitle: SelectableText(value!,
          style: Theme.of(context).textTheme.bodyLarge),
      trailing: copy
          ? IconButton(
              tooltip: 'Copiază',
              icon: const Icon(Icons.copy_rounded, size: 20),
              onPressed: () => copyText(context, value!),
            )
          : null,
    );
  }
}

void copyText(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('Copiat: $text')));
}

void toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'acum';
  if (d.inMinutes < 60) return 'acum ${d.inMinutes} min';
  if (d.inHours < 24) return 'acum ${d.inHours} h';
  if (d.inDays < 30) return 'acum ${d.inDays} zile';
  return '${t.day}.${t.month}.${t.year}';
}
