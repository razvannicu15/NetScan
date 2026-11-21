# NetScan

Scanner de rețea pentru **Android** și **Windows**, în stil Material 3 – similar cu Fing / Advanced IP Scanner.

## Funcții

- **Descoperire dispozitive** în subrețeaua curentă (sau un interval IP personalizat): sondare TCP pe porturi uzuale + ping ICMP, apoi tabela ARP
- **IP, MAC și producător** (bază de date IEEE OUI inclusă, ~40.000 de producători, funcționează offline)
- **Nume dispozitive** din DNS invers, NetBIOS (PC-uri Windows/Samba), mDNS/Bonjour (Apple, imprimante, Linux) și UPnP/SSDP (TV-uri, routere, media)
- **Tipul dispozitivului** ghicit automat (router, PC, telefon, imprimantă, TV, cameră, NAS, IoT…) + sistemul de operare estimat din TTL
- **Scanare porturi**: uzuale / 1–1024 / toate 65535 / listă personalizată, cu **bannere** (SSH, FTP, server HTTP, certificat HTTPS) și deschidere în browser
- **Istoric**: dispozitive noi marcate „NOU”, dispozitive offline, nume personalizate
- **Instrumente**: Ping (ICMP/TCP, statistici + grafic), Wake-on-LAN, DNS lookup, informații rețea + IP public
- Export listă ca CSV (în clipboard), temă luminoasă/întunecată, layout adaptiv (bară jos pe telefon, rail lateral pe desktop)

## Limitări cunoscute

- **Android 10+** nu mai permite aplicațiilor să citească tabela ARP, deci MAC-ul (și producătorul) apar doar pentru dispozitivele care răspund la NetBIOS. Pe **Windows** MAC-ul apare pentru toate dispozitivele din LAN.
- Rețelele mai mari de /22 sunt scanate pe /24-ul curent (se poate seta un interval personalizat în Setări).

## Build

Build-ul se face automat în **GitHub Actions** la fiecare push pe `main`:

- `NetScan-android` → APK
- `NetScan-windows` → ZIP cu `NetScan.exe`

Le găsești în tab-ul **Actions → ultimul run → Artifacts**. La un tag `v*` (ex. `v1.0.0`) se creează automat și un **Release** cu ambele fișiere.

Local (cu Flutter instalat):

```bash
flutter create --platforms=android,windows --org ro.netscan --project-name netscan .
flutter pub get
dart run tool/patch_platforms.dart
dart run flutter_launcher_icons
flutter build apk --release      # sau: flutter build windows --release
```

> Folosește NetScan doar în rețele pe care le administrezi sau ai permisiunea să le scanezi.
