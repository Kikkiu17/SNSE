import 'dart:async';
import 'dart:io';
import 'pages/device.dart';
import 'pages/settings.dart';
import 'package:network_port_scanner/network_port_scanner.dart';
import 'dart:developer' as debug;

const int _retryDelayMs = 200;
const int _postScanDelayMs = 300;

// Minimum scan timeout in ms — Android's WiFi stack is slow to respond to
// ARP/ping probes, so a very short timeout reliably misses reachable devices.
const int _minScanTimeoutMs = 1500;

// Number of times to repeat a full network scan before giving up.
// A second pass catches devices that didn't respond in the first sweep.
const int _scanPasses = 2;

Future<Device> createDevice(String ip, TcpClient client) async {
  Device device = Device();
  device.ip = ip;

  // --- GET DEVICE ID ---
  await Future.delayed(const Duration(milliseconds: 15));
  String response = await client.sendDataRetry("GET ?wifi=ID", connectionRetries, 100);
  if (!response.contains("200 OK")) {
    return device;
  }
  device.id = response.split("\n")[1];

  // --- GET DEVICE NAME ---
  await Future.delayed(const Duration(milliseconds: 15));
  response = await client.sendDataRetry("GET ?wifi=name", connectionRetries, 100);
  if (!response.contains("200 OK")) {
    return device;
  }
  device.name = response.split("\n")[1];

  // --- GET DEVICE FEATURES ---
  await Future.delayed(const Duration(milliseconds: 15));
  response = await client.sendDataRetry("GET ?features", connectionRetries, 100);
  if (!response.contains("200 OK")) {
    return device;
  }
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
    if (pass > 0) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

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

  await Future.delayed(const Duration(milliseconds: _postScanDelayMs));

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
      client.disconnect();
      // One more attempt after a short delay (device may have been busy).
      await Future.delayed(const Duration(milliseconds: _retryDelayMs));
      TcpClient retryClient = TcpClient();
      bool retryConnected = await retryClient.connectRetry(ip, defaultPort, connectionRetries, null);
      if (!retryConnected) {
        if (!newList) {
          Device device = Device();
          device.id = "";
          device.ip = ip;
          device.name = "OFFLINE";
          return device;
        }
        return null;
      }
      response = await retryClient.sendDataRetry("GET ?wifi=IP", connectionRetries, 100);
      if (response.contains("200 OK")) {
        ip = response.split("\n")[1];
      } else {
        retryClient.disconnect();
        return null;
      }
      Device device = await createDevice(ip, retryClient);
      retryClient.disconnect();
      return device;
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

  // Report how many IPs were found/known before connections start, so the
  // badge can show the scan result immediately rather than waiting for TCP.
  onScanComplete?.call(ips.length);

  ips.sort();
  ips = ips.reversed.toList();

  // Devices are appended here as each parallel future completes.
  final List<Device> devices = [];

  // Build futures and attach an individual .then() to each one so that
  // onDeviceFound fires as soon as that specific IP resolves — not after
  // the slowest IP in the whole batch finishes.
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