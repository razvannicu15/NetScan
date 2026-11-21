import '../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/utils.dart';
import '../models/device.dart';
import 'device_detail_page.dart';
import 'security_page.dart';
import 'widgets.dart';

enum _Sort { ip, name, vendor, type }

enum _View { all, fresh, unknown, cameras }

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  String _query = '';
  _Sort _sort = _Sort.ip;
  bool _showOffline = false;
  _View _view = _View.all;
  int _seenSerial = 0;

  List<Device> _filter(List<Device> list) {
    final q = _query.trim().toLowerCase();
    var out = q.isEmpty
        ? list
        : list.where((d) {
            return [
              d.ip,
              d.mac,
              d.vendor,
              d.displayName,
              d.hostname,
              d.type.label,
            ].whereType<String>().any((s) => s.toLowerCase().contains(q));
          }).toList();
    out = [...out];
    switch (_sort) {
      case _Sort.ip:
        out.sort((a, b) => compareIp(a.ip, b.ip));
      case _Sort.name:
        out.sort((a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      case _Sort.vendor:
        out.sort((a, b) => (a.vendor ?? '~').compareTo(b.vendor ?? '~'));
      case _Sort.type:
        out.sort((a, b) => a.type.index.compareTo(b.type.index));
    }
    return out;
  }

  void _open(Device d) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DeviceDetailPage(device: d),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scanner,
      builder: (context, _) {
        final unknown = scanner.unknownDevices;
        final cameras = scanner.cameras;
        final fresh = scanner.newDevices;
        if (scanner.scanSerial != _seenSerial) {
          _seenSerial = scanner.scanSerial;
          final n = scanner.newCount;
          if (n > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  duration: const Duration(seconds: 8),
                  content: Text(n == 1
                      ? tr('Un dispozitiv nou în rețea', 'One new device on the network')
                      : tr('$n dispozitive noi în rețea', '$n new devices on the network')),
                  action: SnackBarAction(
                    label: tr('Vezi', 'Show'),
                    onPressed: () => setState(() => _view = _View.fresh),
                  ),
                ));
            });
          }
        }
        if (_view == _View.fresh && fresh.isEmpty) _view = _View.all;
        if (_view == _View.unknown && unknown.isEmpty) _view = _View.all;
        if (_view == _View.cameras && cameras.isEmpty) _view = _View.all;
        final online = _filter(switch (_view) {
          _View.all => scanner.devices,
          _View.fresh => fresh,
          _View.unknown => unknown,
          _View.cameras => cameras,
        });
        final done = !scanner.scanning && scanner.lastScan != null;
        final offline = _filter(scanner.offlineDevices);
        return Scaffold(
          floatingActionButton: _ScanFab(
              scanning: scanner.scanning, progress: scanner.progress),
          body: RefreshIndicator(
            onRefresh: () => scanner.scan(),
            child: CustomScrollView(
              slivers: [
                SliverAppBar.medium(
                  title: const Text('NetScan'),
                  actions: [
                    PopupMenuButton<_Sort>(
                      tooltip: tr('Sortează', 'Sort'),
                      icon: const Icon(Icons.sort_rounded),
                      initialValue: _sort,
                      onSelected: (s) => setState(() => _sort = s),
                      itemBuilder: (_) => [
                        PopupMenuItem(value: _Sort.ip, child: Text(tr('După IP', 'By IP'))),
                        PopupMenuItem(
                            value: _Sort.name, child: Text(tr('După nume', 'By name'))),
                        PopupMenuItem(
                            value: _Sort.vendor, child: Text(tr('După producător', 'By vendor'))),
                        PopupMenuItem(value: _Sort.type, child: Text(tr('După tip', 'By type'))),
                      ],
                    ),
                    IconButton(
                      tooltip: tr('Copiază lista (CSV)', 'Copy list (CSV)'),
                      icon: const Icon(Icons.ios_share_rounded),
                      onPressed: scanner.devices.isEmpty
                          ? null
                          : () {
                              Clipboard.setData(
                                  ClipboardData(text: scanner.exportCsv()));
                              toast(context, tr('Lista a fost copiată ca CSV', 'List copied as CSV'));
                            },
                    ),
                    PopupMenuButton<int>(
                      tooltip: tr('Mai multe', 'More'),
                      onSelected: (v) async {
                        if (v == 1) {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(tr('Marchezi toate ca cunoscute?', 'Mark all as known?')),
                              content: Text(tr(
                                  'Toate dispozitivele de acum devin „ale tale”. De acum încolo, orice dispozitiv nou va apărea ca necunoscut.',
                                  'All current devices become “yours”. From now on, any new device will show as unknown.')),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: Text(tr('Anulează', 'Cancel'))),
                                FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(tr('Marchează', 'Mark'))),
                              ],
                            ),
                          );
                          if (ok == true) await scanner.markAllKnown();
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 1,
                          enabled: scanner.devices.isNotEmpty && !scanner.scanning,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.verified_user_outlined),
                            title: Text(tr('Marchează toate ca cunoscute', 'Mark all as known')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
                SliverToBoxAdapter(
                  child: MaxWidth(child: _NetworkCard()),
                ),
                if (scanner.devices.isNotEmpty || _query.isNotEmpty)
                  SliverToBoxAdapter(
                    child: MaxWidth(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: SearchBar(
                          hintText: tr('Caută IP, MAC, nume, producător…', 'Search IP, MAC, name, vendor…'),
                          leading: const Icon(Icons.search),
                          elevation: const WidgetStatePropertyAll(0),
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                    ),
                  ),
                if (done && scanner.devices.isNotEmpty)
                  SliverToBoxAdapter(
                    child: MaxWidth(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: Text('${tr('Toate', 'All')} · ${scanner.devices.length}'),
                              selected: _view == _View.all,
                              onSelected: (_) => setState(() => _view = _View.all),
                            ),
                            if (fresh.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              ChoiceChip(
                                avatar: Icon(Icons.fiber_new_outlined,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.primary),
                                label: Text('${tr('Noi', 'New')} · ${fresh.length}'),
                                selected: _view == _View.fresh,
                                onSelected: (_) =>
                                    setState(() => _view = _View.fresh),
                              ),
                            ],
                            if (unknown.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              ChoiceChip(
                                avatar: Icon(Icons.person_search,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.error),
                                label: Text('${tr('Necunoscute', 'Unknown')} · ${unknown.length}'),
                                selected: _view == _View.unknown,
                                onSelected: (_) =>
                                    setState(() => _view = _View.unknown),
                              ),
                            ],
                            if (cameras.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              ChoiceChip(
                                avatar: const Icon(Icons.videocam_outlined, size: 18),
                                label: Text('${tr('Camere', 'Cameras')} · ${cameras.length}'),
                                selected: _view == _View.cameras,
                                onSelected: (_) =>
                                    setState(() => _view = _View.cameras),
                              ),
                            ],
                            const SizedBox(width: 8),
                            ActionChip(
                              avatar: const Icon(Icons.shield_outlined, size: 18),
                              label: Text(tr('Securitate', 'Security')),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                    builder: (_) => const SecurityPage()),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (scanner.devices.isEmpty && !scanner.scanning)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(),
                  ),
                if (online.isNotEmpty)
                  SliverToBoxAdapter(
                    child: MaxWidth(
                      child: SectionHeader('Online · ${online.length}'),
                    ),
                  ),
                SliverList.builder(
                  itemCount: online.length,
                  itemBuilder: (_, i) => MaxWidth(
                    child: _DeviceTile(
                        device: online[i],
                        onTap: _open,
                        enabled: !scanner.scanning),
                  ),
                ),
                if (offline.isNotEmpty && !scanner.scanning)
                  SliverToBoxAdapter(
                    child: MaxWidth(
                      child: SectionHeader(
                        'Offline · ${offline.length}',
                        trailing: TextButton(
                          onPressed: () =>
                              setState(() => _showOffline = !_showOffline),
                          child: Text(_showOffline ? tr('Ascunde', 'Hide') : tr('Arată', 'Show')),
                        ),
                      ),
                    ),
                  ),
                if (_showOffline && !scanner.scanning)
                  SliverList.builder(
                    itemCount: offline.length,
                    itemBuilder: (_, i) => MaxWidth(
                      child: _DeviceTile(device: offline[i], onTap: _open),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ScanFab extends StatefulWidget {
  const _ScanFab({required this.scanning, required this.progress});
  final bool scanning;
  final double? progress;

  @override
  State<_ScanFab> createState() => _ScanFabState();
}

class _ScanFabState extends State<_ScanFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.scanning) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _ScanFab old) {
    super.didUpdateWidget(old);
    if (widget.scanning && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.scanning && _c.isAnimating) {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scanning = widget.scanning;
    final bg = scanning ? cs.tertiary : cs.primary;
    final fg = scanning ? cs.onTertiary : cs.onPrimary;
    final p = widget.progress;
    final label = scanning
        ? '${tr('Oprește', 'Stop')}${p == null ? '' : ' · ${(p * 100).round()}%'}'
        : tr('Scanează', 'Scan');
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(22));

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // 0 → 1 → 0 pulse while scanning
        final pulse = scanning ? 1 - (2 * _c.value - 1).abs() : 0.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: bg.withValues(alpha: scanning ? 0.25 + 0.30 * pulse : 0.35),
                blurRadius: scanning ? 14 + 16 * pulse : 16,
                spreadRadius: scanning ? 1 + 6 * pulse : 1,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        );
      },
      child: FloatingActionButton.extended(
        onPressed: scanning ? scanner.cancel : scanner.scan,
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 2,
        highlightElevation: 0,
        shape: shape,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 28),
        icon: RotationTransition(
          turns: _c,
          child: const Icon(Icons.radar, size: 28),
        ),
        label: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            label,
            key: ValueKey(scanning),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

class _NetworkCard extends StatefulWidget {
  @override
  State<_NetworkCard> createState() => _NetworkCardState();
}

class _NetworkCardState extends State<_NetworkCard> {
  bool _expanded = false;

  IconData _wifiIcon(int? p) {
    if (p == null) return Icons.wifi_rounded;
    if (p >= 75) return Icons.signal_wifi_4_bar;
    if (p >= 50) return Icons.network_wifi_3_bar;
    if (p >= 30) return Icons.network_wifi_2_bar;
    return Icons.network_wifi_1_bar;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final net = scanner.network;
    final wifi = scanner.wifi;
    final scanning = scanner.scanning;
    final onC = cs.onPrimaryContainer;

    final String title;
    final IconData icon;
    if (net == null) {
      title = scanner.detectingNetwork
          ? tr('Detectez rețeaua…', 'Detecting network…')
          : tr('Nicio rețea locală', 'No local network');
      icon = Icons.wifi_off_rounded;
    } else if (wifi != null && wifi.isWifi) {
      title = wifi.ssid ?? 'Wi-Fi';
      icon = _wifiIcon(wifi.signalPercent);
    } else {
      title = net.interfaceName;
      icon = Icons.settings_ethernet;
    }

    final chips = <(IconData, String)>[
      if (wifi != null && wifi.signalPercent != null)
        (
          Icons.signal_cellular_alt,
          '${wifi.signalPercent}%${wifi.rssi != null ? ' · ${wifi.rssi} dBm' : ''} · ${wifi.signalLabel}'
        ),
      if (wifi?.band != null)
        (
          Icons.waves,
          '${wifi!.band}${wifi.channel != null ? ' · ${tr('canal', 'ch')} ${wifi.channel}' : ''}'
        ),
      if (wifi?.standard != null) (Icons.wifi_tethering, wifi!.standard!),
      if (wifi?.linkMbps != null || wifi?.rxMbps != null)
        (
          Icons.speed,
          wifi!.rxMbps != null && wifi.txMbps != null
              ? '↓${wifi.rxMbps} ↑${wifi.txMbps} Mbps'
              : '${wifi.linkMbps ?? wifi.rxMbps} Mbps'
        ),
      if (wifi?.security != null) (Icons.lock_outline, wifi!.security!),
    ];

    final gw = scanner.gateway;
    final mainStats = <(String, String)>[
      (tr('Dispozitive', 'Devices'), '${scanner.devices.length}'),
      (tr('IP-ul tău', 'Your IP'), net?.ip ?? '—'),
      if (scanner.unknownDevices.isNotEmpty)
        (tr('Necunoscute', 'Unknown'), '${scanner.unknownDevices.length}'),
    ];
    final subtitle = (wifi != null && wifi.signalPercent != null)
        ? '${tr('Semnal', 'Signal')} ${wifi.signalPercent}% · ${wifi.signalLabel}${wifi.band != null ? ' · ${wifi.band}' : ''}'
        : (wifi != null && wifi.isWifi)
            ? (net?.interfaceName ?? 'Wi-Fi')
            : null;
    final stats = <(String, String)>[
      ('Gateway', net?.gateway ?? '—'),
      (tr('Interval', 'Range'), scanner.targetDescription),
      if (gw?.vendor != null) ('Router', gw!.vendor!),
      if (wifi?.bssid != null) ('BSSID', wifi!.bssid!),
      if (scanner.publicIp != null) (tr('IP public', 'Public IP'), scanner.publicIp!),
      if (scanner.isp != null && scanner.isp!.isNotEmpty) ('ISP', scanner.isp!),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Card(
        elevation: 0,
        color: cs.primaryContainer,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: onC, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: tt.titleLarge?.copyWith(
                                color: onC, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall
                                ?.copyWith(color: onC.withValues(alpha: 0.75)),
                          ),
                      ],
                    ),
                  ),
                  if (_expanded)
                    IconButton(
                      tooltip: tr('Redetectează rețeaua', 'Re-detect network'),
                      onPressed: scanning ? null : scanner.refreshNetwork,
                      icon: Icon(Icons.refresh_rounded, color: onC),
                    ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more, color: onC),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              if (wifi != null && (wifi.needsLocation || wifi.locationOff)) ...[
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: wifi.needsLocation ? scanner.requestWifiPermission : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Icon(Icons.location_on_outlined, size: 16, color: onC),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          wifi.needsLocation
                              ? tr('Permite Locația ca să vezi numele Wi-Fi', 'Allow Location to see the Wi-Fi name')
                              : tr('Pornește Locația ca să vezi numele Wi-Fi', 'Turn on Location to see the Wi-Fi name'),
                          style: tt.bodySmall?.copyWith(color: onC),
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [for (final st in mainStats) _Stat(st.$1, st.$2)],
                ),
              ),
              if (_expanded && chips.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in chips)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: onC.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(c.$1, size: 14, color: onC),
                          const SizedBox(width: 5),
                          Text(c.$2,
                              style: tt.labelMedium?.copyWith(color: onC)),
                        ]),
                      ),
                  ],
                ),
              ],
              if (_expanded) ...[
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [for (final st in stats) _Stat(st.$1, st.$2)],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (scanning) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: scanner.progress,
                      minHeight: 6,
                      backgroundColor: onC.withValues(alpha: 0.12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                scanning
                    ? '${scanner.status}'
                        '${scanner.progressTotal > 0 ? '  ${scanner.progressDone}/${scanner.progressTotal}' : ''}'
                    : scanner.lastScan == null
                        ? (scanner.status.isEmpty
                            ? tr('Apasă „Scanează” pentru a descoperi dispozitivele.', 'Tap “Scan” to discover devices.')
                            : scanner.status)
                        : '${scanner.status} · ${timeAgo(scanner.lastScan!)}',
                style: tt.bodyMedium?.copyWith(color: onC.withValues(alpha: 0.85)),
              ),
            ],
          ),
          ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: tt.labelMedium?.copyWith(
                color: cs.onPrimaryContainer.withValues(alpha: 0.7))),
        const SizedBox(height: 2),
        Text(value,
            style: tt.titleMedium?.copyWith(
                color: cs.onPrimaryContainer,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile(
      {required this.device, required this.onTap, this.enabled = true});
  final Device device;
  final void Function(Device) onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final d = device;
    final sub = [
      if (d.isSelf) tr('Tu', 'You'),
      d.ip,
      if (d.vendor != null && d.vendor != d.displayName) d.vendor!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: enabled ? 1 : 0.45,
        child: Card(
        elevation: 0,
        color: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => onTap(d) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(
              children: [
                Opacity(
                  opacity: d.online ? 1 : 0.6,
                  child: _BadgedAvatar(
                    device: d,
                    unknown: scanner.usesKnown && !d.known && !d.isSelf && d.online,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.displayName,
                        style: tt.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        d.online ? sub : tr('$sub · văzut ${timeAgo(d.lastSeen)}', '$sub · seen ${timeAgo(d.lastSeen)}'),
                        style: tt.bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (d.mac != null)
                        Text(
                          d.mac!,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                    ],
                  ),
                ),
                if (enabled && d.latencyMs != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text('${d.latencyMs!.round()} ms',
                        style: tt.labelMedium
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                if (enabled)
                  Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant)
                else
                  const Padding(
                    padding: EdgeInsets.all(4),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.radar, size: 56, color: cs.onSecondaryContainer),
          ),
          const SizedBox(height: 20),
          Text(tr('Descoperă ce e în rețeaua ta', 'Discover what\'s on your network'),
              style: tt.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            tr('NetScan găsește dispozitivele conectate, adresele IP și MAC, producătorul și porturile deschise.',
                'NetScan finds connected devices, their IP and MAC addresses, vendor and open ports.'),
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Device icon with a tiny status badge: red "?" = unknown, blue dot = new.
class _BadgedAvatar extends StatelessWidget {
  const _BadgedAvatar({required this.device, required this.unknown});
  final Device device;
  final bool unknown;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 0, top: 0, child: DeviceAvatar(device: device)),
          if (unknown)
            Positioned(
              right: 0,
              bottom: 0,
              child: Tooltip(
                message: tr('Necunoscut', 'Unknown'),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: cs.error,
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.surfaceContainerLow, width: 2),
                  ),
                  child: Icon(Icons.question_mark, size: 10, color: cs.onError),
                ),
              ),
            ),
          if (device.isNew)
            Positioned(
              right: 0,
              top: 0,
              child: Tooltip(
                message: tr('Nou', 'New'),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.surfaceContainerLow, width: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
