import 'dart:io';

import '../core/utils.dart';

class LocalNetwork {
  LocalNetwork({
    required this.interfaceName,
    required this.ip,
    required this.prefix,
    this.gateway,
    this.selfMac,
  });

  final String interfaceName;
  final String ip;
  final int prefix;
  final String? gateway;
  final String? selfMac;

  /// Prefix actually scanned (very large networks are limited to a /24).
  int get scanPrefix => (prefix < 22 || prefix > 30) ? 24 : prefix;

  String get cidr => '${networkAddress(ip, scanPrefix)}/$scanPrefix';
  String get id => '${networkAddress(ip, prefix)}/$prefix';
  List<String> get hosts => hostsInSubnet(ip, scanPrefix);
  String get broadcast => broadcastAddress(ip, prefix);
}

class LocalNetworkService {
  static const _bad = [
    'rmnet', 'ccmni', 'tun', 'ppp', 'vpn', 'virtual', 'vethernet', 'vmware',
    'virtualbox', 'docker', 'hyper-v', 'wsl', 'tailscale', 'zerotier',
    'loopback', 'bluetooth', 'p2p', 'dummy', 'veth', 'br-'
  ];
  static const _good = [
    'wlan', 'wi-fi', 'wifi', 'wireless', 'en0', 'eth', 'ethernet', 'wlp',
    'enp', 'ap0', 'swlan'
  ];

  static Future<LocalNetwork?> detect() async {
    List<NetworkInterface> ifaces;
    try {
      ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
    } catch (_) {
      return null;
    }

    String? bestIp;
    String? bestName;
    var bestScore = -1000;
    for (final iface in ifaces) {
      final name = iface.name.toLowerCase();
      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (!isValidIp(ip) || ip.startsWith('169.254.')) continue;
        var score = 0;
        if (isPrivateIp(ip)) score += 10;
        if (ip.startsWith('192.168.')) score += 3;
        if (ip.startsWith('100.')) score -= 6; // CGNAT / Tailscale
        if (_good.any(name.contains)) score += 8;
        if (_bad.any(name.contains)) score -= 20;
        if (score > bestScore) {
          bestScore = score;
          bestIp = ip;
          bestName = iface.name;
        }
      }
    }
    if (bestIp == null) return null;

    var prefix = 24;
    String? gateway;
    String? selfMac;

    if (Platform.isWindows) {
      final out = await runCommand('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "\$a = Get-NetIPAddress -AddressFamily IPv4 -IPAddress '$bestIp'; "
            "\$m = (Get-NetAdapter -InterfaceIndex \$a.InterfaceIndex).MacAddress; "
            "Write-Output \"\$(\$a.PrefixLength)|\$m\""
      ], timeout: const Duration(seconds: 6));
      if (out != null) {
        final line = out.trim().split('\n').last.trim();
        final parts = line.split('|');
        final p = int.tryParse(parts.first.trim());
        if (p != null && p > 0 && p <= 32) prefix = p;
        if (parts.length > 1) selfMac = normalizeMac(parts[1]);
      }
      final route = await runCommand('route', ['print', '-4', '0.0.0.0']);
      if (route != null) {
        final re = RegExp(
            r'^\s*0\.0\.0\.0\s+0\.0\.0\.0\s+(\d+\.\d+\.\d+\.\d+)\s+(\d+\.\d+\.\d+\.\d+)',
            multiLine: true);
        for (final m in re.allMatches(route)) {
          if (m.group(2) == bestIp) gateway = m.group(1);
          gateway ??= m.group(1);
        }
      }
    } else {
      final addr = await runCommand('ip', ['-o', '-f', 'inet', 'addr', 'show']);
      if (addr != null) {
        final m = RegExp('inet ${RegExp.escape(bestIp)}/(\\d+)').firstMatch(addr);
        if (m != null) prefix = int.parse(m.group(1)!);
      }
      final route = await runCommand('ip', ['route']);
      if (route != null) {
        final m = RegExp(r'default via (\d+\.\d+\.\d+\.\d+)').firstMatch(route);
        if (m != null) gateway = m.group(1);
      }
      if (gateway == null && (Platform.isMacOS)) {
        final r = await runCommand('route', ['-n', 'get', 'default']);
        final m = RegExp(r'gateway:\s*(\d+\.\d+\.\d+\.\d+)').firstMatch(r ?? '');
        gateway = m?.group(1);
      }
      if (Platform.isLinux && bestName != null) {
        try {
          selfMac = normalizeMac(
              await File('/sys/class/net/$bestName/address').readAsString());
        } catch (_) {}
      }
    }

    if (gateway != null && !isValidIp(gateway)) gateway = null;
    // Fallback: the classic .1 router address in the same subnet.
    gateway ??= intToIp((ipToInt(bestIp) & prefixMask(prefix)) + 1);

    return LocalNetwork(
      interfaceName: bestName ?? '?',
      ip: bestIp,
      prefix: prefix,
      gateway: gateway,
      selfMac: selfMac,
    );
  }
}
