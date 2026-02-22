import 'dart:async';
import 'pages/device.dart';
import 'pages/settings.dart';
import 'package:network_port_scanner/network_port_scanner.dart';
import 'dart:developer' as debug;

const String idTemplate = "ESPDEVICE";

Future<Device> createDevice(String ip, TcpClient client) async
{
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
    List<String> ips = await NetworkScanner.scanNetwork(
      port: defaultPort,
      timeout: savedSettings.getUpdateTime() * 2
    );

    debug.log('Found ${ips.length} devices with port $defaultPort open:');
    for (String ip in ips) {
      debug.log('- $ip');
    }

    return ips;
  }

Future<List<Device>> discoverDevices(List<String> ips) async
{
  List<Device> devices = List.empty(growable: true);
  bool newList = false;

  if (ips.isEmpty) {
    // if no ids are provided, discover all devices in the range
    newList = true;
    ips = await scanNetwork();
  }

  // sorts list so that smaller ips are at the top
  ips.sort();
  ips = ips.reversed.toList();
  
  for (String ip in ips)
  {
    // ip;id
    ip = ip.split(";")[0];

    TcpClient client = TcpClient();
    bool connected = await client.connectRetry(ip, defaultPort, connectionRetries, null);

    if (!connected) {
      if (!newList) {
        // il dispositivo non è raggiungibile, lo aggiungo come offline
        // se non è una lista nuova (!newList), 
        Device device = Device();
        device.id = "";
        device.ip = ip;
        device.name = "OFFLINE";
        devices.add(device);
      }
      continue;
    }

    String response = await client.sendDataRetry("GET ?wifi=IP", connectionRetries, 100);
    
    try {
      if (response.contains("200 OK")) {
        ip = response.split("\n")[1];
      } else {
        client.disconnect();
        continue;
      }
    } catch (e) {
      client.disconnect();
      continue;
    }

    Device device = await createDevice(ip, client);
    client.disconnect();

    devices.add(device);
  }

  return devices;
}
