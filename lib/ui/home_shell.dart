import 'package:flutter/material.dart';

import 'devices_page.dart';
import 'settings_page.dart';
import 'tools_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = [DevicesPage(), ToolsPage(), SettingsPage()];

  static const _dest = [
    (Icons.lan_outlined, Icons.lan, 'Dispozitive'),
    (Icons.handyman_outlined, Icons.handyman, 'Instrumente'),
    (Icons.settings_outlined, Icons.settings, 'Setări'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final body = IndexedStack(index: _index, children: _pages);

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.9,
              leading: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 20),
                child: Column(
                  children: [
                    Icon(Icons.radar,
                        size: 34, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 4),
                    Text('NetScan',
                        style: Theme.of(context).textTheme.labelLarge),
                  ],
                ),
              ),
              destinations: [
                for (final d in _dest)
                  NavigationRailDestination(
                    icon: Icon(d.$1),
                    selectedIcon: Icon(d.$2),
                    label: Text(d.$3),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _dest)
            NavigationDestination(
              icon: Icon(d.$1),
              selectedIcon: Icon(d.$2),
              label: d.$3,
            ),
        ],
      ),
    );
  }
}
