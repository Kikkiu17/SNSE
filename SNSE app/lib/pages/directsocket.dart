import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:snse/pages/settings.dart';

import 'device.dart';

String command = "";
String recv = "";
String device_ip = "";
String device_port = "";
bool isConnected = false;

Device device = Device();

class DirectSocketPage extends StatefulWidget {
  const DirectSocketPage({super.key});

  @override
  State<DirectSocketPage> createState() => _DirectSocketPageState();
}

class _DirectSocketPageState extends State<DirectSocketPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    super.dispose();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached ||
    state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      // app in background
      isConnected = false;
      device.client.disconnect();
      if (context.mounted) {
        setState(() {});
      }
    } else if (state == AppLifecycleState.resumed) {
      // app in foreground
      device.client.connect(device.ip, int.tryParse(device_port) ?? defaultPort, device).then((connected) {
        isConnected = connected;
        if (context.mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      body: ListView(
        children: [
          ListTile(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(20))
            ),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            title: Text((isConnected) ? "direct_socket.connected".tr() : "direct_socket.disconnected".tr(),
              style: TextStyle(
                color: (isConnected) ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold
              ),
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 10)),
          // IP
          ListTile(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(20))
            ),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            title: Text("direct_socket.device_ip".tr()),
            trailing: SizedBox(
              width: 140,
              height: 25,
              child: TextField(
                controller: TextEditingController(text: device_ip),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.only(bottom: 1),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  device_ip = value;
                },
              ),
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 10)),
          // PORT
          ListTile(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(20))
            ),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            title: Text("direct_socket.device_port".tr()),
            trailing: SizedBox(
              width: 140,
              height: 25,
              child: TextField(
                controller: TextEditingController(text: (device_port == "") ? defaultPort.toString() : device_port),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.only(bottom: 1),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  device_port = value;
                },
              ),
            ),
          ),
          // CONNECT/DISCONNECT
          ListTile(
            title: ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
              ),
              child: Text("direct_socket.connect".tr()),
              onPressed: () async {
                device.client.disconnect();
                device.ip = device_ip;
                isConnected = await device.client.connect(device.ip, int.tryParse(device_port) ?? defaultPort, device);
                if (context.mounted) {
                  setState(() {});
                }
              }
            ),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
              ),
              child: Text("direct_socket.disconnect".tr()),
              onPressed: () {
                device.client.disconnect();
                isConnected = false;
                if (context.mounted) {
                  setState(() {});
                }
              }
            ),
          ),
          // COMMAND
          ListTile(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(20))
            ),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            title: Text("direct_socket.command".tr()),
            subtitle: Column(
              children: [
                const Padding(padding: EdgeInsets.only(top: 7)),
                SizedBox(
                  height: 75,
                  child: TextField(
                    controller: TextEditingController(text: command),
                    maxLines: null,
                    expands: true,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.only(bottom: 1),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      command = value;
                    },
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 7)),
              ]
            )
          ),
          // SEND
          ListTile(
            title: ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
              ),
              child: Text("direct_socket.send".tr()),
              onPressed: () async {
                recv = "";
                recv = await device.client.sendData(command);
                if (context.mounted) {
                  setState(() {});
                }
              }
            )
          ),
          // RECV
          ListTile(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(20))
            ),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            title: Text("direct_socket.received_data".tr()),
            subtitle: Column(
              children: [
                const Padding(padding: EdgeInsets.only(top: 7)),
                SizedBox(
                  height: 200,
                  child: TextField(
                    controller: TextEditingController(text: recv),
                    maxLines: null,
                    expands: true,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.only(bottom: 1),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      recv = value;
                    },
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 7)),
              ]
            )
          ),
          //const Padding(padding: EdgeInsets.only(top: 10)),
        ],
      )
    );
  }
}