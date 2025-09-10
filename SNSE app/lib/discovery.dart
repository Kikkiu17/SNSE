import 'dart:async';
import 'pages/device.dart';
import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import 'pages/settings.dart';

const String idTemplate = "ESPDEVICE";

Future<Device> createDevice(String ip, TcpClient client) async
{
  Device device = Device();
  device.ip = ip;

  // --- GET DEVICE ID ---
  String response = await client.sendData("GET ?wifi=ID");
  if (!response.contains("200 OK")) {
    return device;
  }
  device.id = response.split("\n")[1];

  // --- GET DEVICE NAME ---
  response = await client.sendData("GET ?wifi=name");
  if (!response.contains("200 OK")) {
    return device;
  }
  device.name = response.split("\n")[1];
  
  // --- GET DEVICE FEATURES ---
  response = await client.sendData("GET ?features");
  if (!response.contains("200 OK")) {
    return device;
  }
  device.features = response.split("\n")[1].split(";");

  return device;
}

Future<List<String>> scanNetwork() async {
    List<String> ips = List.empty(growable: true);
    await (NetworkInfo().getWifiIP()).then(
      (ip) async {
        final String subnet = ip!.substring(0, ip.lastIndexOf('.'));
        for (var i = 0; i < savedSettings.getMaxIp(); i++) {
          String ip = '$subnet.$i';
          await Socket.connect(ip, defaultPort, timeout: Duration(milliseconds: savedSettings.getScanTimeout()))
            .then((socket) async {
              ips.add(socket.address.address);
              socket.destroy();
            }).catchError((error) => null);
        }
      },
    );
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
  
  for (String ip in ips)
  {
    // ip;id
    ip = ip.split(";")[0];

    TcpClient client = TcpClient();
    bool connected = await client.connect(ip, defaultPort, null);

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

    String response = await client.sendData("GET ?wifi=IP");
    if (!response.contains("200 OK")) {
      // retry
      sleep(const Duration(milliseconds: 25));
      response = await client.sendData("GET ?wifi=IP");
    }
    
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
