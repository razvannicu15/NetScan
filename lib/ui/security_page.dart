import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/i18n.dart';
import '../services/security_audit.dart';
import 'device_detail_page.dart';
import 'widgets.dart';

class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scanner,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;
        final scanned = scanner.lastScan != null && !scanner.scanning;
        final findings = scanned ? SecurityAudit.run(scanner) : <Finding>[];
        final high = findings.where((f) => f.severity == Severity.high).length;
        final medium = findings.where((f) => f.severity == Severity.medium).length;
        final low = findings.where((f) => f.severity == Severity.low).length;

        final (Color bg, Color fg, IconData icon, String headline) = !scanned
            ? (cs.surfaceContainerHigh, cs.onSurface, Icons.shield_outlined,
                tr('Rulează o scanare a rețelei', 'Run a network scan first'))
            : high > 0
                ? (cs.errorContainer, cs.onErrorContainer, Icons.gpp_bad_outlined,
                    tr('$high probleme importante', '$high important issues'))
                : medium > 0
                    ? (cs.tertiaryContainer, cs.onTertiaryContainer,
                        Icons.gpp_maybe_outlined,
                        tr('$medium lucruri de verificat', '$medium things to check'))
                    : (cs.primaryContainer, cs.onPrimaryContainer,
                        Icons.verified_user_outlined,
                        tr('Rețeaua arată bine', 'Your network looks good'));

        return Scaffold(
          appBar: AppBar(title: Text(tr('Securitate rețea', 'Network security'))),
          body: MaxWidth(
            width: 760,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 44, color: fg),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(headline,
                                style: tt.titleLarge?.copyWith(
                                    color: fg, fontWeight: FontWeight.w700)),
                            if (scanned) ...[
                              const SizedBox(height: 4),
                              Text(
                                tr('$high mari · $medium medii · $low informative',
                                    '$high high · $medium medium · $low info'),
                                style: tt.bodyMedium
                                    ?.copyWith(color: fg.withValues(alpha: 0.8)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!scanned) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: scanner.scanning
                        ? null
                        : () {
                            scanner.scan();
                          },
                    icon: const Icon(Icons.radar),
                    label: Text(tr('Scanează acum', 'Scan now')),
                  ),
                ],
                if (scanned && !appSettings.scanPorts) ...[
                  const SizedBox(height: 12),
                  Text(
                    tr('Scanarea porturilor e dezactivată în Setări, deci verificarea e parțială.',
                        'Port scanning is disabled in Settings, so this check is partial.'),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 16),
                if (findings.isNotEmpty)
                  TableCard(
                    margin: EdgeInsets.zero,
                    children: [for (final f in findings) _FindingRow(f)],
                  ),
                const SizedBox(height: 12),
                Text(
                  tr('Verificarea se face local, pe baza ultimei scanări. Nimic nu e trimis pe internet.',
                      'The check runs locally from the last scan. Nothing is sent to the internet.'),
                  textAlign: TextAlign.center,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow(this.f);
  final Finding f;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final (Color c, String label) = switch (f.severity) {
      Severity.high => (cs.error, tr('MARE', 'HIGH')),
      Severity.medium => (Colors.orange.shade700, tr('MEDIE', 'MEDIUM')),
      Severity.low => (cs.onSurfaceVariant, 'INFO'),
      Severity.ok => (Colors.green.shade600, 'OK'),
    };
    final d = f.device;
    return InkWell(
      onTap: d == null
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => DeviceDetailPage(device: d)),
              ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(f.icon ?? Icons.info_outline, size: 20, color: c),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(f.title,
                            style: tt.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(label,
                            style: tt.labelSmall?.copyWith(
                                color: c, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  if (d != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('${d.displayName} · ${d.ip}',
                          style: tt.labelMedium?.copyWith(color: cs.primary)),
                    ),
                  const SizedBox(height: 4),
                  Text(f.detail,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cameras found in the last scan (RTSP ports, camera vendors / names).
class CamerasPage extends StatelessWidget {
  const CamerasPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scanner,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;
        final cams = scanner.cameras;
        final scanned = scanner.lastScan != null && !scanner.scanning;
        return Scaffold(
          appBar: AppBar(title: Text(tr('Camere în rețea', 'Cameras on network'))),
          body: MaxWidth(
            width: 760,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  tr('Caut dispozitive cu porturi video (RTSP 554/8554, DVR 37777) sau producători de camere (Hikvision, Dahua, Reolink, Ezviz…).',
                      'Looks for devices with video ports (RTSP 554/8554, DVR 37777) or camera vendors (Hikvision, Dahua, Reolink, Ezviz…).'),
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                if (!scanned)
                  FilledButton.icon(
                    onPressed: scanner.scanning ? null : () => scanner.scan(),
                    icon: const Icon(Icons.radar),
                    label: Text(scanner.scanning
                        ? tr('Se scanează…', 'Scanning…')
                        : tr('Scanează acum', 'Scan now')),
                  )
                else if (cams.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(children: [
                      Icon(Icons.videocam_off_outlined, color: cs.onPrimaryContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                            tr('Nicio cameră găsită în rețea.', 'No cameras found on the network.'),
                            style: tt.titleMedium
                                ?.copyWith(color: cs.onPrimaryContainer)),
                      ),
                    ]),
                  )
                else
                  TableCard(
                    margin: EdgeInsets.zero,
                    children: [
                      for (final d in cams)
                        ListTile(
                          leading: DeviceAvatar(device: d, size: 40),
                          title: Text(d.displayName),
                          subtitle: Text([
                            d.ip,
                            if (d.vendor != null) d.vendor!,
                            (d.allKnownPorts.toList()..sort()).join(', '),
                          ].join(' · ')),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) => DeviceDetailPage(device: d)),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
                Text(
                  tr('O cameră ascunsă pe Wi-Fi apare aici doar dacă e conectată la aceeași rețea cu tine.',
                      'A hidden Wi-Fi camera only shows up here if it is on the same network as you.'),
                  textAlign: TextAlign.center,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
