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
      toast(context, 'Listă de porturi invalidă. Exemplu: 22,80,8000-8100');
      return;
    }
    final cancel = _cancel = CancelToken();
    setState(() {
      _open.clear();
      _done = 0;
      _total = ports.length;
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
        if (mounted) setState(() => _done = d);
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
      appBar: AppBar(title: Text('Porturi · ${widget.host}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _running ? () => _cancel?.cancel() : _start,
        icon: Icon(_running ? Icons.stop_rounded : Icons.play_arrow_rounded),
        label: Text(_running ? 'Oprește' : 'Pornește'),
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
                  Text('Ce porturi verific?', style: tt.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (p, label) in [
                        (_Preset.top, 'Uzuale (${kTopPorts.length})'),
                        (_Preset.wellKnown, '1–1024'),
                        (_Preset.full, 'Toate (65535)'),
                        (_Preset.custom, 'Personalizat'),
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
                      decoration: const InputDecoration(
                        labelText: 'Porturi',
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
                                        ? 'Scanez… $_done / $_total'
                                        : 'Gata: $_done porturi în ${(_sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s',
                                    style: tt.titleSmall,
                                  ),
                                ),
                                Text('${_open.length} deschise',
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
                if (_open.isNotEmpty) const SectionHeader('Porturi deschise'),
                for (final o in _open)
                  PortTile(
                    port: o.port,
                    banner: o.banner,
                    onOpen: (kHttpPorts.contains(o.port) ||
                            kHttpsPorts.contains(o.port))
                        ? () => _openWeb(o.port)
                        : null,
                  ),
                if (_finished && _open.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Niciun port deschis găsit (sau gazda filtrează conexiunile).',
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
