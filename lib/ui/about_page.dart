import 'package:flutter/material.dart';

import '../core/i18n.dart';
import 'widgets.dart';

const kAppVersion = '1.5.1';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: tt.bodyLarge)),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Despre', 'About'))),
      body: MaxWidth(
        width: 560,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Image.asset('assets/icon.png', width: 104, height: 104),
              ),
            ),
            const SizedBox(height: 16),
            Text('NetScan',
                textAlign: TextAlign.center,
                style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text('v$kAppVersion · by norAz',
                textAlign: TextAlign.center,
                style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                tr('Am făcut-o pentru că m-am săturat de aplicații pline de reclame.',
                    "Made because I'm sick of apps full of ads."),
                textAlign: TextAlign.center,
                style: tt.titleMedium?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 20),
            point(Icons.block, tr('Fără reclame', 'No ads')),
            point(Icons.visibility_off_outlined,
                tr('Fără tracking, fără cont', 'No tracking, no account')),
            point(Icons.lock_outline,
                tr('Datele rămân pe dispozitivul tău', 'Your data stays on your device')),
            const SizedBox(height: 24),
            Text(
              tr('Folosește NetScan doar în rețele pe care le administrezi sau ai permisiunea să le scanezi.',
                  'Only use NetScan on networks you manage or have permission to scan.'),
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
