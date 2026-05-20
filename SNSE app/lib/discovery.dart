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

  String response = await client.sendDataRetry("GET ?wifi=ID", connectionRetries, 100);
  if (response.contains("200 OK")) {
    device.id = response.split("\n")[1];
  }

  response = await client.sendDataRetry("GET ?wifi=name", connectionRetries, 100);
  if (response.contains("200 OK")) {
    device.name = response.split("\n")[1];
  }

  response = await client.sendDataRetry("GET ?features", connectionRetries, 100);
  if (response.contains("200 OK")) {
    device.features = response.split("\n")[1].split(";");
  }

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

Future<Device?> _tryConnectDevice(String ipEntry, bool newList) async {
  final parts = ipEntry.split(";");
  final String ip = parts[0];
  final String savedId = parts.length > 1 ? parts[1] : "";

  TcpClient client = TcpClient();
  bool connected = await client.connectRetry(ip, defaultPort, connectionRetries, null);

  if (!connected) {
    debug.log('[$ip] All connection attempts failed.');
    if (!newList) {
      Device device = Device();
      device.id = savedId;
      device.ip = ip;
      device.name = "OFFLINE";
      return device;
    }
    return null;
  }

  // Allow socket buffer stabilization after connection
  await Future.delayed(const Duration(milliseconds: 50));

  String canonicalIp = ip;
  String response;
  try {
    response = await client.sendDataRetry("GET ?wifi=IP", connectionRetries, 100);
    if (response.contains("200 OK")) {
      canonicalIp = response.split("\n")[1];
    } else {
      debug.log('[$ip] Unexpected response to ?wifi=IP: $response');
      response = await client.sendDataRetry("GET ?wifi=IP", connectionRetries, 100);
      
      if (response.contains("200 OK")) {
        canonicalIp = response.split("\n")[1];
      } else {
        await client.disconnect();
        if (!newList) {
          Device device = Device();
          device.id = savedId;
          device.ip = ip;
          device.name = "OFFLINE";
          return device;
        }
        return null;
      }
    }
  } catch (e) {
    debug.log('[$ip] Exception during IP handshake: $e');
    await client.disconnect();
    if (!newList) {
      Device device = Device();
      device.id = savedId;
      device.ip = ip;
      device.name = "OFFLINE";
      return device;
    }
    return null;
  }

  Device device = await createDevice(canonicalIp, client);
  await client.disconnect();

  if (device.id.isEmpty || device.name.isEmpty) {
    debug.log('[$ip] Incomplete info received: id="${device.id}", name="${device.name}"');
    if (!newList) {
      device.id = device.id.isEmpty ? savedId : device.id;
      device.name = device.name.isEmpty ? "OFFLINE" : device.name;
    } else {
      return null;
    }
  }

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
    return _tryConnectDevice(ipEntry, newList).then((device) {
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