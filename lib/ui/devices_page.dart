import '../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/utils.dart';
import '../models/device.dart';
import 'device_detail_page.dart';
import 'widgets.dart';

enum _Sort { ip, name, vendor, type }

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  String _query = '';
  _Sort _sort = _Sort.ip;
  bool _showOffline = false;

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
        final online = _filter(scanner.devices);
        final offline = _filter(scanner.offlineDevices);
        return Scaffold(
          floatingActionButton: _ScanFab(),
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
                    child: _DeviceTile(device: online[i], onTap: _open),
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

class _ScanFab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scanning = scanner.scanning;
    return FloatingActionButton.extended(
      onPressed: scanning ? scanner.cancel : scanner.scan,
      icon: Icon(scanning ? Icons.stop_rounded : Icons.radar),
      label: Text(scanning ? tr('Oprește', 'Stop') : tr('Scanează', 'Scan')),
    );
  }
}

class _NetworkCard extends StatelessWidget {
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
    final stats = <(String, String)>[
      (tr('Dispozitive', 'Devices'), '${scanner.devices.length}'),
      (tr('IP-ul tău', 'Your IP'), net?.ip ?? '—'),
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
                        if (wifi != null && wifi.isWifi)
                          Text(
                            net?.interfaceName ?? 'Wi-Fi',
                            style: tt.bodySmall
                                ?.copyWith(color: onC.withValues(alpha: 0.7)),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Redetectează rețeaua', 'Re-detect network'),
                    onPressed: scanning ? null : scanner.refreshNetwork,
                    icon: Icon(Icons.refresh_rounded, color: onC),
                  ),
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
                              ? tr('Atinge pentru a permite Locația — Android o cere ca să arate numele Wi-Fi',
                                  'Tap to allow Location — Android requires it to show the Wi-Fi name')
                              : tr('Pornește Locația din telefon ca să vezi numele Wi-Fi',
                                  'Turn on Location to see the Wi-Fi name'),
                          style: tt.bodySmall?.copyWith(color: onC),
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
              if (chips.isNotEmpty) ...[
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
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [for (final st in stats) _Stat(st.$1, st.$2)],
                ),
              ),
              const SizedBox(height: 16),
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
  const _DeviceTile({required this.device, required this.onTap});
  final Device device;
  final void Function(Device) onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final d = device;
    final sub = [
      d.ip,
      if (d.vendor != null) d.vendor!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Card(
        elevation: 0,
        color: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onTap(d),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(
              children: [
                Opacity(
                  opacity: d.online ? 1 : 0.6,
                  child: DeviceAvatar(device: d),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              d.displayName,
                              style: tt.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (d.isSelf) ...[
                            const SizedBox(width: 6),
                            TagChip(tr('TU', 'YOU')),
                          ],
                          if (d.isGateway) ...[
                            const SizedBox(width: 6),
                            TagChip('ROUTER',
                                color: cs.tertiaryContainer,
                                onColor: cs.onTertiaryContainer),
                          ],
                          if (d.isNew) ...[
                            const SizedBox(width: 6),
                            TagChip(tr('NOU', 'NEW'),
                                color: cs.errorContainer,
                                onColor: cs.onErrorContainer),
                          ],
                        ],
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
                if (d.latencyMs != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text('${d.latencyMs!.round()} ms',
                        style: tt.labelMedium
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
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
