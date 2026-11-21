/// Well-known TCP ports with human friendly service names.
const Map<int, String> kServiceNames = {
  7: 'Echo',
  20: 'FTP-data',
  21: 'FTP',
  22: 'SSH',
  23: 'Telnet',
  25: 'SMTP',
  37: 'Time',
  53: 'DNS',
  67: 'DHCP',
  69: 'TFTP',
  80: 'HTTP',
  81: 'HTTP-alt',
  88: 'Kerberos',
  110: 'POP3',
  111: 'RPCbind',
  119: 'NNTP',
  123: 'NTP',
  135: 'MS-RPC',
  137: 'NetBIOS-NS',
  139: 'NetBIOS/SMB',
  143: 'IMAP',
  161: 'SNMP',
  179: 'BGP',
  389: 'LDAP',
  427: 'SLP',
  443: 'HTTPS',
  444: 'SNPP',
  445: 'SMB',
  465: 'SMTPS',
  500: 'IKE/VPN',
  515: 'LPD (imprimantă)',
  548: 'AFP',
  554: 'RTSP (cameră)',
  587: 'SMTP Submission',
  631: 'IPP (imprimantă)',
  636: 'LDAPS',
  873: 'rsync',
  902: 'VMware',
  990: 'FTPS',
  993: 'IMAPS',
  995: 'POP3S',
  1080: 'SOCKS',
  1194: 'OpenVPN',
  1433: 'MS SQL',
  1521: 'Oracle DB',
  1723: 'PPTP',
  1883: 'MQTT',
  1900: 'UPnP',
  2049: 'NFS',
  2082: 'cPanel',
  2375: 'Docker',
  2376: 'Docker TLS',
  3000: 'Dev server',
  3128: 'Proxy',
  3306: 'MySQL',
  3389: 'Remote Desktop',
  3689: 'iTunes/DAAP',
  4000: 'HTTP-alt',
  4443: 'HTTPS-alt',
  4567: 'HTTP-alt',
  5000: 'UPnP / Synology',
  5001: 'Synology HTTPS',
  5060: 'SIP',
  5353: 'mDNS',
  5357: 'WSD',
  5432: 'PostgreSQL',
  5555: 'ADB (Android)',
  5900: 'VNC',
  5985: 'WinRM',
  6000: 'X11',
  6379: 'Redis',
  6443: 'Kubernetes',
  6668: 'Tuya',
  7000: 'AirPlay',
  7100: 'AirPlay',
  7547: 'TR-069',
  8000: 'HTTP-alt',
  8008: 'Chromecast',
  8009: 'Chromecast',
  8080: 'HTTP-proxy',
  8081: 'HTTP-alt',
  8086: 'InfluxDB',
  8088: 'HTTP-alt',
  8123: 'Home Assistant',
  8200: 'DLNA',
  8291: 'MikroTik Winbox',
  8443: 'HTTPS-alt',
  8554: 'RTSP-alt',
  8888: 'HTTP-alt',
  8899: 'HTTP-alt',
  9000: 'Portainer / HTTP',
  9090: 'HTTP-alt',
  9100: 'Imprimantă (RAW)',
  9200: 'Elasticsearch',
  9443: 'HTTPS-alt',
  10000: 'Webmin',
  11211: 'Memcached',
  27017: 'MongoDB',
  32400: 'Plex',
  37777: 'Dahua DVR',
  49152: 'UPnP',
  49153: 'UPnP',
  51820: 'WireGuard',
  55443: 'HTTPS-alt',
  62078: 'iOS Lockdown',
};

String serviceName(int port) => kServiceNames[port] ?? 'necunoscut';

/// Ports probed during host discovery (fast liveness + type hints).
const List<int> kDiscoveryPorts = [
  80, 443, 22, 445, 139, 135, 53, 8080, 62078, 5000, 554, 8008, 9100, 3389,
  7000, 49152, 23, 631,
];

/// "Top" ports preset used by quick port scans.
List<int> get kTopPorts {
  final list = kServiceNames.keys.toList()..sort();
  return list;
}

const Set<int> kHttpPorts = {
  80, 81, 3000, 4000, 4567, 5000, 8000, 8008, 8080, 8081, 8088, 8123, 8888,
  8899, 9000, 9090, 10000, 32400,
};

const Set<int> kHttpsPorts = {443, 4443, 5001, 8443, 9443, 55443};

/// Parses "22,80,8000-8100" into a sorted port list. Returns null if invalid.
List<int>? parsePortSpec(String spec) {
  final out = <int>{};
  for (final raw in spec.split(RegExp(r'[,\s;]+'))) {
    final part = raw.trim();
    if (part.isEmpty) continue;
    if (part.contains('-')) {
      final ab = part.split('-');
      if (ab.length != 2) return null;
      final a = int.tryParse(ab[0]), b = int.tryParse(ab[1]);
      if (a == null || b == null || a < 1 || b > 65535 || a > b) return null;
      for (var p = a; p <= b; p++) {
        out.add(p);
      }
    } else {
      final p = int.tryParse(part);
      if (p == null || p < 1 || p > 65535) return null;
      out.add(p);
    }
  }
  if (out.isEmpty) return null;
  return out.toList()..sort();
}
