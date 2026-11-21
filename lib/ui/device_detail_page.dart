import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../core/i18n.dart';
import '../core/ports.dart';
import '../models/device.dart';
import '../services/protocols.dart';
import 'port_scan_page.dart';
import 'tools_page.dart';
import 'traceroute_page.dart';
import 'widgets.dart';

class DeviceDetailPage extends StatefulWidget {
  const DeviceDetailPage({super.key, required this.device});
  final Device device;

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  Device get d => widget.device;
  bool _more = false;

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: d.customName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Redenumește', 'Rename')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: d.autoName),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: Text(tr('Resetează', 'Reset'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(tr('Salvează', 'Save'))),
        ],
      ),
    );
    if (name == null) return;
    await scanner.rename(d, name);
    if (mounted) setState(() {});
  }

  Future<void> _toggleKnown() async {
    await scanner.setKnown(d, !d.known);
    if (!mounted) return;
    setState(() {});
    toast(context,
        d.known ? tr('Marcat ca cunoscut', 'Marked as known') : tr('Marcat ca necunoscut', 'Marked as unknown'));
  }

  Future<void> _wake() async {
    final ok = await WakeOnLan.send(d.mac!, broadcast: scanner.network?.broadcast);
    if (mounted) {
      toast(context, ok ? tr('Wake-on-LAN trimis', 'Wake-on-LAN sent') : tr('Nu s-a putut trimite', 'Could not send'));
    }
  }

  Future<void> _openWeb(int port) async {
    final https = kHttpsPorts.contains(port);
    final uri = Uri.parse(
        '${https ? 'https' : 'http'}://${d.ip}${(port == 80 || port == 443) ? '' : ':$port'}/');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) toast(context, tr('Nu pot deschide $uri', 'Cannot open $uri'));
  }

  Future<void> _forget() async {
    await scanner.forget(d);
    if (mounted) Navigator.pop(context);
  }

  String _uptime(int sec) {
    final dd = sec ~/ 86400, h = (sec % 86400) ~/ 3600, m = (sec % 3600) ~/ 60;
    if (dd > 0) return tr('$dd zile $h h', '$dd days $h h');
    if (h > 0) return '$h h $m min';
    return '$m min';
  }

  void _push(Widget page) => Navigator.push(
      context, MaterialPageRoute<void>(builder: (_) => page)).then((_) {
        if (mounted) setState(() {});
      });

  String? get _model {
    final upnp = [d.upnpManufacturer, d.upnpModel].whereType<String>().join(' ').trim();
    if (upnp.isNotEmpty) return upnp;
    final s = d.snmpDescr;
    if (s == null) return null;
    return s.length > 48 ? '${s.substring(0, 48)}…' : s;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ports = d.allKnownPorts.toList()..sort();
    final web = ports.where((p) => kHttpPorts.contains(p) || kHttpsPorts.contains(p)).toList();
    final showUnknown = scanner.usesKnown && !d.known && !d.isSelf;

    final essentials = <InfoRow>[
      InfoRow(Icons.lan_outlined, 'IP', d.ip),
      InfoRow(Icons.fingerprint, 'MAC',
          d.mac ?? (d.isSelf ? null : tr('indisponibil pe Android', 'unavailable on Android')),
          copy: d.mac != null),
      InfoRow(Icons.factory_outlined, tr('Producător', 'Vendor'), d.vendor),
      InfoRow(Icons.memory, 'Model', _model),
    ].where((r) => r.visible).toList();

    final extras = <InfoRow>[
      InfoRow(Icons.dns_outlined, 'Hostname', d.hostname),
      InfoRow(Icons.badge_outlined, 'NetBIOS',
          [d.netbiosName, if (d.workgroup != null) '(${d.workgroup})'].whereType<String>().join(' ').trim()),
      InfoRow(Icons.cell_tower, 'mDNS', d.mdnsName),
      InfoRow(Icons.cast_outlined, 'UPnP', d.upnpName),
      InfoRow(Icons.lan, 'SNMP', d.snmpName),
      InfoRow(Icons.description_outlined, tr('Descriere SNMP', 'SNMP description'), d.snmpDescr),
      InfoRow(Icons.place_outlined, tr('Locație', 'Location'), d.snmpLocation),
      InfoRow(Icons.timelapse, 'Uptime', d.snmpUptimeSec == null ? null : _uptime(d.snmpUptimeSec!), copy: false),
      InfoRow(Icons.dns, 'Server', d.serverHeader),
      InfoRow(Icons.computer, tr('Sistem', 'OS'),
          d.osGuess == null ? null : '${d.osGuess} (TTL ${d.ttl})', copy: false),
      InfoRow(Icons.history, tr('Văzut prima dată', 'First seen'), timeAgo(d.firstSeen), copy: false),
      if (!d.online)
        InfoRow(Icons.schedule, tr('Văzut ultima dată', 'Last seen'), timeAgo(d.lastSeen), copy: false),
    ].where((r) => r.visible).toList();

    final actions = <(IconData, String, VoidCallback)>[
      (Icons.travel_explore, tr('Porturi', 'Ports'),
          () => _push(PortScanPage(host: d.ip, device: d))),
      (Icons.network_ping, 'Ping', () => _push(PingPage(initialHost: d.ip))),
      if (!d.isSelf)
        (Icons.route_outlined, 'Trace', () => _push(TraceroutePage(initialHost: d.ip))),
      if (d.mac != null && !d.isSelf) (Icons.power_settings_new, 'Wake', _wake),
      if (web.isNotEmpty) (Icons.open_in_browser, 'Web', () => _openWeb(web.first)),
    ];

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (!d.isSelf)
            IconButton(
              tooltip: d.known ? tr('Cunoscut', 'Known') : tr('Marchează ca cunoscut', 'Mark as known'),
              onPressed: _toggleKnown,
              icon: Icon(d.known ? Icons.verified_user : Icons.verified_user_outlined,
                  color: d.known ? cs.primary : null),
            ),
          IconButton(
            tooltip: tr('Redenumește', 'Rename'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: _rename,
          ),
          if (!d.online)
            IconButton(
              tooltip: tr('Uită dispozitivul', 'Forget device'),
              icon: const Icon(Icons.delete_outline),
              onPressed: _forget,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          MaxWidth(
            width: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---------------------------------------------- header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Row(
                    children: [
                      DeviceAvatar(device: d, size: 60),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              [
                                d.type.label,
                                if (d.latencyMs != null) '${d.latencyMs!.round()} ms',
                              ].join(' · '),
                              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    TagChip(d.online ? 'ONLINE' : 'OFFLINE',
                        color: d.online ? cs.secondaryContainer : cs.surfaceContainerHighest,
                        onColor: d.online ? cs.onSecondaryContainer : cs.onSurfaceVariant),
                    if (d.isSelf) TagChip(tr('ACEST DISPOZITIV', 'THIS DEVICE')),
                    if (d.isGateway)
                      TagChip('GATEWAY', color: cs.tertiaryContainer, onColor: cs.onTertiaryContainer),
                    if (d.known && !d.isSelf) TagChip(tr('CUNOSCUT', 'KNOWN')),
                    if (showUnknown)
                      TagChip(tr('NECUNOSCUT', 'UNKNOWN'),
                          color: cs.errorContainer, onColor: cs.onErrorContainer),
                    if (d.isNew)
                      TagChip(tr('NOU', 'NEW'), color: cs.errorContainer, onColor: cs.onErrorContainer),
                  ]),
                ),

                // ---------------------------------------------- actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
                  child: Row(
                    children: [
                      for (final a in actions)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: _ActionTile(icon: a.$1, label: a.$2, onTap: a.$3),
                          ),
                        ),
                    ],
                  ),
                ),

                // ---------------------------------------------- essentials
                const SizedBox(height: 12),
                TableCard(children: [
                  ...essentials,
                  if (_more) ...extras,
                  if (extras.isNotEmpty)
                    InkWell(
                      onTap: () => setState(() => _more = !_more),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _more
                                  ? tr('Mai puțin', 'Less')
                                  : tr('Mai multe detalii · ${extras.length}', 'More details · ${extras.length}'),
                              style: tt.labelLarge?.copyWith(color: cs.primary),
                            ),
                            Icon(_more ? Icons.expand_less : Icons.expand_more,
                                size: 18, color: cs.primary),
                          ],
                        ),
                      ),
                    ),
                ]),

                // ---------------------------------------------- ports
                SectionHeader(tr('Porturi deschise · ${ports.length}', 'Open ports · ${ports.length}')),
                if (ports.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      tr('Niciun port deschis găsit.', 'No open ports found.'),
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  )
                else
                  PortsTable(
                    ports: [
                      for (final p in ports)
                        d.openPorts.where((o) => o.port == p).firstOrNull ?? OpenPort(p),
                    ],
                    onOpen: _openWeb,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.secondaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: cs.onSecondaryContainer),
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: cs.onSecondaryContainer)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Open ports as a subtle table: port · service · banner · open-in-browser.
class PortsTable extends StatelessWidget {
  const PortsTable({super.key, required this.ports, this.onOpen});
  final List<OpenPort> ports;
  final void Function(int port)? onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cols = [
      const TableCol('Port', width: 64),
      TableCol(tr('Serviciu', 'Service'), flex: 2),
      const TableCol('Info', flex: 3),
      const TableCol('', width: 32, align: TextAlign.right),
    ];
    return TableCard(
      header: cols,
      children: [
        for (final o in ports)
          TableDataRow(
            cols: cols,
            onLongPress: () => copyText(context, '${o.port}'),
            cells: [
              CellText('${o.port}', bold: true, color: cs.primary),
              CellText(o.service),
              CellText(o.banner ?? '—', muted: true),
              (onOpen != null &&
                      (kHttpPorts.contains(o.port) || kHttpsPorts.contains(o.port)))
                  ? InkWell(
                      onTap: () => onOpen!(o.port),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.open_in_new, size: 18, color: cs.primary),
                      ),
                    )
                  : const SizedBox.shrink(),
            ],
          ),
      ],
    );
  }
}
