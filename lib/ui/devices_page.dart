import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/utils.dart';
import '../models/device.dart';
import '../services/scan_controller.dart';
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
                      tooltip: 'Sortează',
                      icon: const Icon(Icons.sort_rounded),
                      initialValue: _sort,
                      onSelected: (s) => setState(() => _sort = s),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: _Sort.ip, child: Text('După IP')),
                        PopupMenuItem(
                            value: _Sort.name, child: Text('După nume')),
                        PopupMenuItem(
                            value: _Sort.vendor, child: Text('După producător')),
                        PopupMenuItem(value: _Sort.type, child: Text('După tip')),
                      ],
                    ),
                    IconButton(
                      tooltip: 'Copiază lista (CSV)',
                      icon: const Icon(Icons.ios_share_rounded),
                      onPressed: scanner.devices.isEmpty
                          ? null
                          : () {
                              Clipboard.setData(
                                  ClipboardData(text: scanner.exportCsv()));
                              toast(context, 'Lista a fost copiată ca CSV');
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
                          hintText: 'Caută IP, MAC, nume, producător…',
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
                          child: Text(_showOffline ? 'Ascunde' : 'Arată'),
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
      label: Text(scanning ? 'Oprește' : 'Scanează'),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final net = scanner.network;
    final scanning = scanner.scanning;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Card(
        elevation: 0,
        color: cs.primaryContainer,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    net == null ? Icons.wifi_off_rounded : Icons.wifi_rounded,
                    color: cs.onPrimaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      scanner.detectingNetwork && net == null
                          ? 'Detectez rețeaua…'
                          : net == null
                              ? 'Nicio rețea locală'
                              : net.interfaceName,
                      style: tt.titleMedium?.copyWith(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Redetectează rețeaua',
                    onPressed: scanning ? null : scanner.refreshNetwork,
                    icon: Icon(Icons.refresh_rounded,
                        color: cs.onPrimaryContainer),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _Stat('Dispozitive', '${scanner.devices.length}'),
                  _Stat('IP-ul tău', net?.ip ?? '—'),
                  _Stat('Gateway', net?.gateway ?? '—'),
                  _Stat('Interval', scanner.targetDescription),
                ],
              ),
              const SizedBox(height: 16),
              if (scanning) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: scanner.phase == ScanPhase.discovering
                        ? scanner.progress
                        : null,
                    minHeight: 6,
                    backgroundColor: cs.onPrimaryContainer.withValues(alpha: 0.12),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                scanning
                    ? '${scanner.status}'
                        '${scanner.phase == ScanPhase.discovering ? '  ${scanner.progressDone}/${scanner.progressTotal}' : ''}'
                    : scanner.lastScan == null
                        ? (scanner.status.isEmpty
                            ? 'Apasă „Scanează” pentru a descoperi dispozitivele.'
                            : scanner.status)
                        : '${scanner.status} · ${timeAgo(scanner.lastScan!)}',
                style: tt.bodyMedium?.copyWith(
                    color: cs.onPrimaryContainer.withValues(alpha: 0.85)),
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
                            const TagChip('TU'),
                          ],
                          if (d.isGateway) ...[
                            const SizedBox(width: 6),
                            TagChip('ROUTER',
                                color: cs.tertiaryContainer,
                                onColor: cs.onTertiaryContainer),
                          ],
                          if (d.isNew) ...[
                            const SizedBox(width: 6),
                            TagChip('NOU',
                                color: cs.errorContainer,
                                onColor: cs.onErrorContainer),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        d.online ? sub : '$sub · văzut ${timeAgo(d.lastSeen)}',
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
          Text('Descoperă ce e în rețeaua ta',
              style: tt.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'NetScan găsește dispozitivele conectate, adresele IP și MAC, '
            'producătorul și porturile deschise.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
