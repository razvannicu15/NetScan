import 'package:flutter_test/flutter_test.dart';
import 'package:netscan/core/ports.dart';
import 'package:netscan/core/utils.dart';

void main() {
  test('subnet helpers', () {
    expect(hostsInSubnet('192.168.1.77', 24).length, 254);
    expect(hostsInSubnet('192.168.1.77', 24).first, '192.168.1.1');
    expect(networkAddress('10.0.5.9', 16), '10.0.0.0');
    expect(broadcastAddress('192.168.1.77', 24), '192.168.1.255');
    expect(isValidIp('256.1.1.1'), isFalse);
  });

  test('mac helpers', () {
    expect(normalizeMac('a-b-c-d-e-f'), '0A:0B:0C:0D:0E:0F');
    expect(normalizeMac('ff:ff:ff:ff:ff:ff'), isNull);
    expect(isRandomMac('DA:A1:19:00:00:01'), isTrue);
  });

  test('port spec', () {
    expect(parsePortSpec('22, 80,8000-8002'), [22, 80, 8000, 8001, 8002]);
    expect(parsePortSpec('99999'), isNull);
  });
}
