import '../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../core/ports.dart';
import '../core/utils.dart';
import '../models/device.dart';
import '../services/port_scanner.dart';
import 'device_detail_page.dart';
import 'widgets.dart';

enum _Preset { top, wellKnown, full, custom }

class PortScanPage extends StatefulWidget {
  const PortScanPage({super.key, required this.host, this.device});
  final String host;
  final Device? device;

  @override
  State<PortScanPage> createState() => _PortScanPageState();
}

class _PortScanPageState extends State<PortScanPage> {
  _Preset _preset = _Preset.top;
  final _custom = TextEditingController(text: '1-1024,3389,5900,8080');
  final List<OpenPort> _open = [];
  int _done = 0;
  int _total = 0;
  int _portCount = 0;
  bool _running = false;
  bool _finished = false;
  CancelToken? _cancel;
  final _sw = Stopwatch();

  List<int>? _ports() {
    switch (_preset) {
      case _Preset.top:
        return kTopPorts;
      case _Preset.wellKnown:
        return [for (var p = 1; p <= 1024; p++) p, ...kTopPorts.where((p) => p > 1024)];
      case _Preset.full:
        return [for (var p = 1; p <= 65535; p++) p];
      case _Preset.custom:
        return parsePortSpec(_custom.text);
    }
  }

  Future<void> _start() async {
    final ports = _ports();
    if (ports == null) {
      toast(context, tr('Listă de porturi invalidă. Exemplu: 22,80,8000-8100', 'Invalid port list. Example: 22,80,8000-8100'));
      return;
    }
    final cancel = _cancel = CancelToken();
    setState(() {
      _open.clear();
      _done = 0;
      _total = ports.length;
      _portCount = ports.length;
      _running = true;
      _finished = false;
    });
    _sw
      ..reset()
      ..start();
    await PortScanner.scan(
      widget.host,
      ports.toSet().toList()..sort(),
      cancel: cancel,
      concurrency: appSettings.portConcurrency,
      timeout: Duration(milliseconds: appSettings.probeTimeoutMs),
      onOpen: (p) {
        final op = OpenPort(p);
        _open.add(op);
        _open.sort((a, b) => a.port.compareTo(b.port));
        if (mounted) setState(() {});
        PortScanner.grabBanner(widget.host, p).then((b) {
          op.banner = b;
          if (mounted) setState(() {});
        });
      },
      onProgress: (d, t) {
        if (mounted) {
          setState(() {
            _done = d;
            _total = t;
          });
        }
      },
    );
    _sw.stop();
    final dev = widget.device ?? scanner.byIp(widget.host);
    if (dev != null) {
      dev.openPorts = List.of(_open);
      if (!cancel.isCancelled) {
        dev.discoveryPorts
          ..clear()
          ..addAll(_open.map((o) => o.port));
      } else {
        dev.discoveryPorts.addAll(_open.map((o) => o.port));
      }
    }
    if (mounted) {
      setState(() {
        _running = false;
        _finished = true;
      });
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _custom.dispose();
    super.dispose();
  }

  Future<void> _openWeb(int port) async {
    final https = kHttpsPorts.contains(port);
    final uri = Uri.parse('${https ? 'https' : 'http'}://${widget.host}:$port/');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final progress = _total == 0 ? 0.0 : _done / _total;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Porturi · ${widget.host}', 'Ports · ${widget.host}'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _running ? () => _cancel?.cancel() : _start,
        icon: Icon(_running ? Icons.stop_rounded : Icons.play_arrow_rounded),
        label: Text(_running ? tr('Oprește', 'Stop') : tr('Pornește', 'Start')),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          MaxWidth(
            width: 760,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Ce porturi verific?', 'Which ports to check?'), style: tt.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (p, label) in [
                        (_Preset.top, tr('Uzuale (${kTopPorts.length})', 'Common (${kTopPorts.length})')),
                        (_Preset.wellKnown, '1–1024'),
                        (_Preset.full, tr('Toate (65535)', 'All (65535)')),
                        (_Preset.custom, tr('Personalizat', 'Custom')),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: _preset == p,
                          onSelected: _running
                              ? null
                              : (_) => setState(() => _preset = p),
                        ),
                    ],
                  ),
                  if (_preset == _Preset.custom) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _custom,
                      enabled: !_running,
                      decoration: InputDecoration(
                        labelText: tr('Porturi', 'Ports'),
                        hintText: '22,80,443,8000-8100',
                        prefixIcon: Icon(Icons.tag),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_running || _finished)
                    Card(
                      elevation: 0,
                      color: cs.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _running
                                        ? (_done >= _portCount
                                            ? tr('Verific din nou porturile lente… $_done / $_total', 'Re-checking slow ports… $_done / $_total')
                                            : tr('Scanez… $_done / $_total', 'Scanning… $_done / $_total'))
                                        : tr('Gata: $_portCount porturi în ${(_sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s', 'Done: $_portCount ports in ${(_sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s'),
                                    style: tt.titleSmall,
                                  ),
                                ),
                                Text(tr('${_open.length} deschise', '${_open.length} open'),
                                    style: tt.titleSmall
                                        ?.copyWith(color: cs.primary)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                  value: progress, minHeight: 6),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          MaxWidth(
            width: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_open.isNotEmpty) SectionHeader(tr('Porturi deschise', 'Open ports')),
                if (_open.isNotEmpty)
                  PortsTable(ports: _open, onOpen: _openWeb),
                if (_finished && _open.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr('Niciun port deschis găsit (sau gazda filtrează conexiunile).', 'No open ports found (or the host filters connections).'),
                      textAlign: TextAlign.center,
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
