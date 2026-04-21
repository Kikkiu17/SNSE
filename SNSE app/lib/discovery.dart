import 'dart:async';
import 'dart:io';
import 'pages/device.dart';
import 'pages/settings.dart';
import 'package:network_port_scanner/network_port_scanner.dart';
import 'dart:developer' as debug;

// Timeout ridotto per accelerare la scansione in LAN (Fix 4)
const int _minScanTimeoutMs = 800;
const int _scanPasses = 2;

Future<Device> createDevice(String ip, TcpClient client) async {
  Device device = Device();
  device.ip = ip;

  // Rimosso Future.delayed (Fix 2)
  String response = await client.sendDataRetry("GET ?wifi=ID", connectionRetries, 100);
  if (!response.contains("200 OK")) return device;
  device.id = response.split("\n")[1];

  // Rimosso Future.delayed (Fix 2)
  response = await client.sendDataRetry("GET ?wifi=name", connectionRetries, 100);
  if (!response.contains("200 OK")) return device;
  device.name = response.split("\n")[1];

  // Rimosso Future.delayed (Fix 2)
  response = await client.sendDataRetry("GET ?features", connectionRetries, 100);
  if (!response.contains("200 OK")) return device;
  device.features = response.split("\n")[1].split(";");

  return device;
}

Future<List<String>> scanNetwork() async {
  final int configuredTimeout = savedSettings.getUpdateTime() * 2;
  final int scanTimeout = configuredTimeout < _minScanTimeoutMs
      ? _minScanTimeoutMs
      : configuredTimeout;

  final bool multiPass = Platform.isAndroid || Platform.isIOS;
  final int passes = multiPass ? _scanPasses : 1;

  Set<String> foundIps = {};

  for (int pass = 0; pass < passes; pass++) {
    // Rimosso delay tra i passaggi (Fix 2)

    List<String> ips = await NetworkScanner.scanNetwork(
      port: defaultPort,
      timeout: scanTimeout,
    );

    debug.log('[Scan pass ${pass + 1}/$passes] Found ${ips.length} devices with port $defaultPort open:');
    for (String ip in ips) {
      debug.log('  - $ip');
      foundIps.add(ip);
    }
  }

  debug.log('Total unique IPs after $passes scan pass(es): ${foundIps.length}');
  
  // Rimosso _postScanDelayMs (Fix 2)

  return foundIps.toList();
}

Future<Device?> _tryConnectDevice(String ip, bool newList) async {
  TcpClient client = TcpClient();
  bool connected = await client.connectRetry(ip, defaultPort, connectionRetries, null);

  if (!connected) {
    debug.log('[$ip] All connection attempts failed.');
    if (!newList) {
      Device device = Device();
      device.id = "";
      device.ip = ip;
      device.name = "OFFLINE";
      return device;
    }
    return null;
  }

  String response;
  try {
    response = await client.sendDataRetry("GET ?wifi=IP", connectionRetries, 100);
    if (response.contains("200 OK")) {
      ip = response.split("\n")[1];
    } else {
      debug.log('[$ip] Unexpected response to ?wifi=IP: $response');
      // Riutilizzo del client esistente per il retry immediato invece di ricreare la socket TCP (Fix 3)
      response = await client.sendDataRetry("GET ?wifi=IP", connectionRetries, 100);
      
      if (response.contains("200 OK")) {
        ip = response.split("\n")[1];
      } else {
        client.disconnect();
        return null;
      }
    }
  } catch (e) {
    debug.log('[$ip] Exception during IP handshake: $e');
    client.disconnect();
    return null;
  }

  Device device = await createDevice(ip, client);
  client.disconnect();
  return device;
}

Future<List<Device>> discoverDevices(
  List<String> ips, {
  void Function(int ipCount)? onScanComplete,
  void Function(int count)? onDeviceFound,
}) async {
  bool newList = false;

  if (ips.isEmpty) {
    newList = true;
    ips = await scanNetwork();
  }

  onScanComplete?.call(ips.length);

  ips.sort();
  ips = ips.reversed.toList();

  final List<Device> devices = [];

  final List<Future<Device?>> futures = ips.map((ipEntry) {
    final String ip = ipEntry.split(";")[0];
    return _tryConnectDevice(ip, newList).then((device) {
      if (device != null) {
        devices.add(device);
        onDeviceFound?.call(devices.length);
      }
      return device;
    });
  }).toList();

  await Future.wait(futures);

  debug.log('discoverDevices: ${devices.length} device(s) found out of ${ips.length} IP(s) tried.');
  return devices;
}