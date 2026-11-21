import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/ports.dart';
import '../models/device.dart';
import 'scan_controller.dart';

enum Severity { high, medium, low, ok }

class Finding {
  Finding(this.severity, this.title, this.detail, {this.device, this.icon});
  final Severity severity;
  final String title;
  final String detail;
  final Device? device;
  final IconData? icon;
}

/// Local, offline security review based on the last scan.
class SecurityAudit {
  static List<Finding> run(ScanController s) {
    final out = <Finding>[];
    final wifi = s.wifi;

    // ---- Wi-Fi encryption
    final sec = wifi?.security?.toUpperCase();
    if (sec != null) {
      if (sec.contains('OPEN') || sec.contains('DESCHIS') || sec.contains('NONE')) {
        out.add(Finding(
          Severity.high,
          tr('Wi-Fi fără parolă', 'Wi-Fi without password'),
          tr('Oricine din apropiere se poate conecta și îți poate vedea traficul necriptat. Activează WPA2 sau WPA3 în router.',
              'Anyone nearby can join and see unencrypted traffic. Enable WPA2 or WPA3 on the router.'),
          icon: Icons.lock_open,
        ));
      } else if (sec.contains('WEP') ||
          (sec.contains('WPA') && !sec.contains('WPA2') && !sec.contains('WPA3'))) {
        out.add(Finding(
          Severity.high,
          tr('Criptare Wi-Fi învechită ($sec)', 'Outdated Wi-Fi encryption ($sec)'),
          tr('WEP/WPA se sparg în câteva minute. Treci pe WPA2-AES sau WPA3.',
              'WEP/WPA can be cracked in minutes. Switch to WPA2-AES or WPA3.'),
          icon: Icons.lock_open,
        ));
      } else if (sec.contains('WPA3')) {
        out.add(Finding(Severity.ok, tr('Wi-Fi cu WPA3', 'Wi-Fi uses WPA3'),
            tr('Cea mai bună criptare disponibilă.', 'Best available encryption.'),
            icon: Icons.lock));
      } else {
        out.add(Finding(Severity.ok, tr('Wi-Fi cu WPA2', 'Wi-Fi uses WPA2'),
            tr('Criptare bună. WPA3 ar fi și mai sigur, dacă routerul îl suportă.',
                'Good encryption. WPA3 is even safer if your router supports it.'),
            icon: Icons.lock));
      }
    }

    // ---- Unknown devices
    final unknown = s.unknownDevices;
    if (unknown.isNotEmpty) {
      out.add(Finding(
        Severity.medium,
        tr('${unknown.length} dispozitive necunoscute', '${unknown.length} unknown devices'),
        tr('Verifică dacă le recunoști și marchează-le ca „cunoscute”. Un dispozitiv străin poate însemna că cineva îți folosește Wi-Fi-ul.',
            'Check whether you recognise them and mark them as “known”. A strange device may mean someone is using your Wi-Fi.'),
        icon: Icons.person_search,
      ));
    }

    // ---- Per-device risky services
    for (final d in s.devices) {
      final p = d.allKnownPorts;
      void add(Severity sev, String title, String detail, IconData icon) =>
          out.add(Finding(sev, title, detail, device: d, icon: icon));

      if (p.contains(23)) {
        add(Severity.high, tr('Telnet deschis', 'Telnet open'),
            tr('Telnet trimite parola necriptată și e ținta preferată a botnet-urilor (Mirai). Dezactivează-l.',
                'Telnet sends passwords in clear text and is a favourite botnet target (Mirai). Disable it.'),
            Icons.terminal);
      }
      if (p.contains(5555)) {
        add(Severity.high, tr('ADB (Android Debug) expus', 'ADB (Android Debug) exposed'),
            tr('Oricine din rețea poate controla dispozitivul. Oprește „Depanare prin rețea”.',
                'Anyone on the network can control the device. Turn off network debugging.'),
            Icons.android);
      }
      if (p.contains(2375)) {
        add(Severity.high, tr('Docker API fără TLS', 'Docker API without TLS'),
            tr('Permite control complet asupra serverului. Închide portul 2375.',
                'Allows full control of the server. Close port 2375.'),
            Icons.dns);
      }
      if (p.contains(21)) {
        add(Severity.medium, tr('FTP deschis', 'FTP open'),
            tr('FTP transmite parola necriptată. Folosește SFTP dacă e posibil.',
                'FTP sends passwords unencrypted. Use SFTP if possible.'),
            Icons.folder_open);
      }
      if (p.contains(3389)) {
        add(Severity.medium, 'Remote Desktop',
            tr('Accesul de la distanță e activ. Folosește parolă puternică și nu-l expune pe internet.',
                'Remote access is enabled. Use a strong password and never expose it to the internet.'),
            Icons.desktop_windows);
      }
      if (p.contains(5900)) {
        add(Severity.medium, tr('VNC deschis', 'VNC open'),
            tr('VNC are adesea parole slabe sau deloc. Verifică setările.',
                'VNC often has weak or no passwords. Check its settings.'),
            Icons.screen_share);
      }
      if (p.contains(1883)) {
        add(Severity.low, tr('MQTT fără criptare', 'Unencrypted MQTT'),
            tr('Mesajele smart home pot fi citite din rețea. Activează autentificarea.',
                'Smart home messages can be read on the network. Enable authentication.'),
            Icons.sensors);
      }
      if ((p.contains(445) || p.contains(139)) && !d.isSelf) {
        add(Severity.low, tr('Partajare fișiere (SMB)', 'File sharing (SMB)'),
            tr('Normal pe PC-uri și NAS-uri; asigură-te că folderele partajate au parolă.',
                'Normal on PCs and NAS; make sure shared folders are password protected.'),
            Icons.folder_shared);
      }

      if (d.isGateway) {
        final httpOnly = p.contains(80) && !p.contains(443) && !p.contains(8443);
        if (httpOnly) {
          add(Severity.medium, tr('Admin router doar pe HTTP', 'Router admin over plain HTTP'),
              tr('Parola routerului circulă necriptat în rețea. Activează HTTPS în setări dacă există.',
                  'The router password travels unencrypted on the network. Enable HTTPS if available.'),
              Icons.http);
        }
        if (p.contains(7547)) {
          add(Severity.medium, tr('TR-069 activ pe router', 'TR-069 active on router'),
              tr('Interfață de administrare a furnizorului; a avut vulnerabilități cunoscute.',
                  'ISP remote management interface; it has had known vulnerabilities.'),
              Icons.settings_remote);
        }
        if (d.upnpName != null || p.contains(1900) || p.contains(49152) || p.contains(5000)) {
          add(Severity.low, tr('UPnP activ pe router', 'UPnP enabled on router'),
              tr('Aplicațiile pot deschide singure porturi spre internet. Dezactivează-l dacă nu-ți trebuie.',
                  'Apps can open ports to the internet by themselves. Disable it if you don\'t need it.'),
              Icons.swap_horiz);
        }
      }

      if (d.isCamera) {
        final open = p
            .where((x) => kHttpPorts.contains(x) || x == 554 || x == 8554 || x == 37777)
            .map((x) => '$x')
            .join(', ');
        add(Severity.low, tr('Cameră în rețea', 'Camera on the network'),
            tr('Schimbă parola implicită și actualizează firmware-ul. Porturi: $open',
                'Change the default password and update the firmware. Ports: $open'),
            Icons.videocam);
      }
    }

    out.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return out;
  }
}
