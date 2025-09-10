// warning not needed, context is always mounted here
// ignore_for_file: use_build_context_synchronously

import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:developer' as debug;
import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import '../externalfeatures.dart';
import 'dart:convert';

import '../tiles/tiles.dart';
import 'settings.dart';

bool update = true;
bool forceShowNotification = false;

class Lock {
  bool _locked = false;

  Future<T> synchronized<T>(Future<T> Function() func) async {
    while (_locked) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    _locked = true;
    try {
      return await func();
    } finally {
      _locked = false;
    }
  }
}

class TcpClient {
  Socket? _socket;
  final _responseQueue = Queue<Completer<String>>();
  final _sendLock = Lock();
  bool _sendingLoopActive = false;

  int _lastNotificationID = 0;
  Device? linkedDevice;
  bool _stopRequested = false;
  Completer<void>? _loopCompleter;

  Future<void> connectAndStartLoop(String host, int port, Device? dev, BuildContext context) async {
    bool connected = await connect(host, port, dev);
    if (connected) {
      await dev!.client.startSendingLoop(context);
    } else {
      showPopupOK(context, "device.error_text".tr(), "device.cant_connect".tr());
    }
  }

  /// Connect to the server and return true if successful
  Future<bool> connect(String host, int port, Device? dev) async {
    linkedDevice = dev;
    try {
      _socket = await Socket.connect(host, port);
      _socket!.listen(_onData, onError: _onError, onDone: _onDone);
      debug.log("Connected to $host");
      return true;
    } catch (e) {
      debug.log('Connection failed: $e');
      _socket = null;
      return false;
    }
  }

  /// Handle incoming data and match it to the correct completer
  String _buffer = "";

  void _onData(Uint8List data) {
    _buffer += utf8.decode(data);

    while (_buffer.contains("\r\n")) {
      final index = _buffer.indexOf("\r\n");
      final completeResponse = _buffer.substring(0, index);
      _buffer = _buffer.substring(index + 2);

      if (_responseQueue.isNotEmpty) {
        final completer = _responseQueue.removeFirst();
        completer.complete(completeResponse);
      } else {
        debug.log('Unexpected response: $completeResponse');
      }
    }
  }


  void _onError(error) {
    debug.log('Socket error: $error');
    _socket?.destroy();
    _socket = null;
  }

  void _onDone() {
    debug.log('Socket closed');
    _socket = null;
  }

  /// Send a single request and wait for its response
  Future<String> sendData(String data) async {
    final result = await _sendLock.synchronized(() async {
      if (_socket == null) {
        throw Exception('Socket is not connected.');
      }

      final completer = Completer<String>();
      _responseQueue.add(completer);
      _socket!.write(data);

      return await completer.future.timeout(Duration(milliseconds: savedSettings.getUpdateTime()), onTimeout: () {
        _responseQueue.remove(completer);
        debug.log('No response within ${savedSettings.getUpdateTime()} ms. Request: $data');
        return ""; // Return empty string on timeout
      });
    });

    return result;
  }

  /// Start the periodic loop that sends two requests every 250ms
  Future<void> startSendingLoop(BuildContext context) async {
    if (linkedDevice == null) return;
      if (_sendingLoopActive) return;

    _sendingLoopActive = true;
    _stopRequested = false;

    _loopCompleter = Completer<void>();

    _loop(context);
  }

  Future<void> _loop(BuildContext context) async {
    while (!_stopRequested) {
      final start = DateTime.now();

      try {
        final notification = await sendData("GET ?notification\n");
        handleNotification(notification, context);

        String features = linkedDevice!.features.join(";");
        String newFeatures = await sendData("GET ?features\n");
        // newFeatures.toLowerCase().contains("vuoto") means notification data
        if (newFeatures.contains("200 OK") && !newFeatures.toLowerCase().contains("vuoto")) {
          features = newFeatures;
        }
        linkedDevice!.features = features.replaceAll("200 OK\n", "").split(";");
        generateIOs.value = !generateIOs.value;
      } catch (e) {
        debug.log('Error during periodic send: $e');
      }

      final elapsed = DateTime.now().difference(start).inMilliseconds;
      if (elapsed < savedSettings.getUpdateTime()) {
        await Future.delayed(Duration(milliseconds: savedSettings.getUpdateTime() - elapsed));
      }
    }

    _sendingLoopActive = false;
    _loopCompleter?.complete();
    _loopCompleter = null;
  }

  Future<void> stopSendingLoop() async {
    if (!_sendingLoopActive) return;

    _stopRequested = true;

    // Wait for the loop to finish
    await _loopCompleter?.future;
  }

  String getNotification(String notificationText) {
    try {
      notificationText = notificationText.split("200 OK")[1].trim();
      int notificationID = int.parse(notificationText.split(dataSeparator)[0]);

      if (notificationID != _lastNotificationID || forceShowNotification) {
        _lastNotificationID = notificationID;
        return notificationText.split(dataSeparator)[1];
      }
    } catch (e) {
      return "";
    }

    return "";
  }
  
  void showNotification(BuildContext context, String notificationText) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text("device.notification".tr()),
        content: Text(notificationText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'OK'),
            child: const Text('OK'),
          ),
        ],
      )
    );
  }

  void showNoNewNotifications(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text("device.no_notif_dialog_title".tr()),
        content: Text("device.no_notif_dialog_content".tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'OK'),
            child: const Text('OK'),
          ),
        ],
      )
    );
  }

  void handleNotification(String notificationText, BuildContext context) {
    notificationText = getNotification(notificationText);
    if (notificationText != "" || forceShowNotification) {
      if (context.mounted) {
        if (notificationText == "" && forceShowNotification) {
          showNoNewNotifications(context);
        } else {
          showNotification(context, notificationText);
        }
        forceShowNotification = false;
      }
    }
  }

  void disconnect() {
    stopSendingLoop();
    _socket?.destroy();
    _socket = null;
  }
}

void showPopupOK(BuildContext context, String title, String content) {
  showDialog(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'OK'),
          child: const Text('OK'),
        ),
      ],
    )
  );
}

class Device {
  String id = "";
  String name = "";
  String ip = "";
  List<String> features = List.empty(growable: true);
  final TcpClient client = TcpClient();
  bool updatingValues = false;

  Future<String> sendName(String name) async {
    while (!await client.connect(ip, defaultPort, this)) {}
    String resp = await client.sendData("POST ?wifi=changename&name=$name");
    client.disconnect();
    return resp.split("\n")[0];
  }

  Future<bool?> changeName(BuildContext context) async {
    String userInputName = "";

    bool? ret = await showDialog (
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.tr("device.change_name_dialog_title")),
        content: TextField(
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: context.tr("device.change_name_dialog_hint"),
          ),
          onChanged: (text) {
            userInputName = text;
          },
        ),
        actions: [
          TextButton(
            onPressed: () {

              sendName(userInputName).then((statusCode) {
                if (statusCode == "200 OK") {
                  showPopupOK(context, "device.success_text".tr(), "device.change_name_success".tr());
                }
                else {
                  showPopupOK(context, "device.error_text".tr(), "device.change_name_error".tr());
                }
              });

              Navigator.pop(context, true);
            },
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          )
        ],
      )
    );

    return ret;
  }

  DevicePage setThisDevicePage() {
    return DevicePage(device: this);
  }

  // FUNZIONI PERSONALIZZATE PER L'APPLICAZIONE SPECIFICA
  // FUNZIONI PULSANTE
  Future<String> openCloseValve(String id) async {
    //await espsocket.flush();
    String resp = await client.sendData("GET ?valve=$id");
    if (resp.contains("200 OK")) {
      String isOpen = resp.split("\n")[1];
      if (isOpen == "aperta") {
        client.sendData("POST ?valve=$id&cmd=close");
      } else if (isOpen == "chiusa") {
        client.sendData("POST ?valve=$id&cmd=open");
      }
    }

    return resp.split("\n")[0];
  }
}

class DevicePage extends StatefulWidget {
  const DevicePage({
    super.key,
    required this.device
  });

  final Device device;

  @override
  State<DevicePage> createState() => _DevicePageState();
}

late Timer timer;

late ValueNotifier<bool> generateIOs;
ValueNotifier<bool> updateIOs = ValueNotifier(false);
ValueNotifier<bool> updateExternalFeaturesListener = ValueNotifier(false);

List<Widget> userIOs = List.empty(growable: true);
bool firstRun = true;

class ExternalFeature
{
  ExternalFeature(this.index, this.id, this.widget);
  final int index;
  final int id;
  final Widget widget;
}
List<Widget> externalFeaturesWidgets = List.empty(growable: true);
String rawExternalFeatures = "";
ValueNotifier<bool> addExternalFeaturesListener = ValueNotifier(false);

class _DevicePageState extends State<DevicePage> with WidgetsBindingObserver {
  bool rawExternalFeaturesAdded = false;

  void _generateIOsListener() {
    if (!update) return;
    updateIOs.value = false;
    userIOs = _generateDirectUserIOs(widget.device);
    updateIOs.value = true;
  }

  @override
  void initState() {
    super.initState();
    rawExternalFeatures = "";
    externalFeaturesWidgets.clear();
    firstRun = true;
    userIOs = List.empty(growable: true);
    userIOs.add(loadingTileNoText);
    generateIOs = ValueNotifier(false);
    generateIOs.addListener(_generateIOsListener);

    addExternalFeaturesListener.addListener(_addExternalFeature);

    widget.device.client.connect(widget.device.ip, defaultPort, widget.device).then((connected) {
      if (connected) {
        widget.device.client.startSendingLoop(context);
      } else {
        showPopupOK(context, "device.error_text".tr(), "device.cant_connect".tr());
      }
    });

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    firstRun = false;
    Future.microtask(() async {
      widget.device.client.disconnect();
      generateIOs.removeListener(_generateIOsListener);
      generateIOs.dispose();
    });

    addExternalFeaturesListener.removeListener(_addExternalFeature);

    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached ||
    state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      // app in background
      widget.device.client.disconnect();
    } else if (state == AppLifecycleState.resumed) {
      // app in foreground
      widget.device.client.connect(widget.device.ip, defaultPort, widget.device).then((connected) {
        if (connected) {
          widget.device.client.startSendingLoop(context);
        } else {
          showPopupOK(context, "device.error_text".tr(), "device.cant_connect".tr());
        }
      });
    }
  }


  // DATA SEPARATOR WILL BE FOUND IN settings.dart
  // for example: switch1<DATA SEPARATOR>Valvola1,sensor<DATA SEPARATOR>Stato<DATA SEPARATOR>aperta,sensor<DATA SEPARATOR>Litri/s<DATA SEPARATOR>5.24;

  Card _addSwitchFeature(String feature)
  {
    // switch1$Valvola1,status$1,sensor$Stato$aperta,sensor$Litri/s$5.24;
    feature.replaceAll(";", "");
    String switchId = feature.split(dataSeparator)[0][feature.split(dataSeparator)[0].length - 1];
    String switchname = feature.split(dataSeparator)[1].split(",")[0];
    String text = "$switchId: $switchname";
    Color color = Theme.of(context).colorScheme.inversePrimary;

    for (String addon in feature.split(","))
    {
      if (addon.contains("sensor")) {
        String sensorName = addon.split(dataSeparator)[1];
        String sensorData = addon.split(dataSeparator)[2];
        text += " - $sensorName: $sensorData";
      } else if (addon.contains("status")) {
        String status = addon.split(dataSeparator)[1];
        if (status == "0") {
          color = Color.alphaBlend(Theme.of(context).colorScheme.surfaceContainerLow.withAlpha(50), const Color.fromARGB(255, 231, 67, 67));
        } else if (status == "1") {
          color = Color.alphaBlend(Theme.of(context).colorScheme.surfaceContainerLow.withAlpha(50), const Color.fromARGB(255, 59, 208, 59));
        }
      }
    }

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Text(text),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Card(
                color: color,
                child: InkWell(
                  enableFeedback: true,
                  child: SizedBox(
                    height: 50,
                    width: 50,
                    child: Icon(Icons.radio_button_checked, color: Color.alphaBlend(Colors.black.withAlpha(220), color))  // Theme.of(context).colorScheme.primary
                    ),
                    onTap: () async {
                      await widget.device.client.stopSendingLoop();

                      String statusCode = await widget.device.openCloseValve(switchId);
                      if (statusCode != "200 OK") {
                        showPopupOK(context, "device.retry_text".tr(), "device.cant_send_command".tr(args: [statusCode]));
                      }

                      widget.device.client.startSendingLoop(context);
                    },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Card _addTimestampFeature(String feature)
  {
    // timestamp1:TimestampName:timestamp;
    feature.replaceAll(";", "");
    //String timestampId = feature.split(dataSeparator)[0][feature.split(dataSeparator)[0].length - 1];
    String timestampName = feature.split(dataSeparator)[1];
    String timestamp = feature.split(dataSeparator)[2];
    String text = "$timestampName: $timestamp";

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Text(text),
            ),
          ],
        ),
      ),
    );
  }

  Card _addSensorFeature(String feature)
  {
    // sensor1:SensorName:SensorData;
    feature.replaceAll(";", "");
    //String sensorId = feature.split(dataSeparator)[0][feature.split(dataSeparator)[0].length - 1];
    String sensorName = feature.split(dataSeparator)[1];
    String sensorData = feature.split(dataSeparator)[2];
    String text = "";
    //text += "$sensorId: ";
    text += "$sensorName: $sensorData";

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Text(text),
            ),
          ],
        ),
      ),
    );
  }

  Card _addButtonFeature(String feature)
  {
    // button1&giao&dataToSend;
    feature.replaceAll(";", "");
    //String buttonId = feature.split(dataSeparator)[0][feature.split(dataSeparator)[0].length - 1];
    String buttonText = feature.split(dataSeparator)[1];
    String dataToSend = "";
    if (feature.split(dataSeparator).length == 3) {
      dataToSend = feature.split(dataSeparator)[2];
    }

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                ),
                child: Text(buttonText),
                onPressed: () async {
                  if (dataToSend == "") {
                    showPopupOK(context, "device.error_text".tr(), "device.no_content_sent".tr());
                  } else {
                    await widget.device.client.stopSendingLoop();

                    String statusCode = await widget.device.client.sendData(dataToSend);
                    if (statusCode != "200 OK") {
                      showPopupOK(context, "device.retry_text".tr(), "device.cant_send_command".tr(args: [statusCode]));
                    }

                    widget.device.client.startSendingLoop(context);
                  }
                }
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<TextEditingController> textInputControllers = List.empty(growable: true);

  Card _addTextInputFeature(String feature)
  {
    // textinput1$08:00-09:30,button$Imposta$send;
    feature.replaceAll(";", "");
    List<Widget> addons = List.empty(growable: true);
    int textInputId = int.parse(feature.split(dataSeparator)[0][feature.split(dataSeparator)[0].length - 1]);
    String textInputHintText = "";
    if (feature.contains(",")) {
      textInputHintText = feature.split(",")[0].split(dataSeparator)[1];
    } else {
      textInputHintText = feature.split(dataSeparator)[1];
    }

    String dataToSend = feature.split(dataSeparator)[3];
    TextEditingController textInputController = TextEditingController();
    if (textInputControllers.length >= textInputId) {
      textInputController = textInputControllers[textInputId - 1];
    } else {
      textInputControllers.add(textInputController);
    }

    for (String addon in feature.split(","))
    {
      if (addon.contains("button"))
      {
        String buttonText = addon.split(dataSeparator)[1];
        addons.add(
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Color.alphaBlend(Colors.white.withAlpha(150), Theme.of(context).colorScheme.inversePrimary),
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: Text(buttonText),
            onPressed: () async {
              await widget.device.client.stopSendingLoop();

              if (dataToSend.startsWith("send")) {
                // dataToSend: sendPOST ?key=<TEXTINPUT>
                String template = dataToSend.split("send")[1];
                String statusCode = await widget.device.client.sendData("$template${textInputController.text}");
                if (statusCode.split("\n")[0] != "200 OK") {
                  showPopupOK(context, "device.retry_text".tr(), "device.cant_send_command".tr(args: [statusCode]));
                }
                textInputController.clear();
                widget.device.client.startSendingLoop(context);
              } else {
                if (dataToSend == "") {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    showPopupOK(context, "device.error_text".tr(), "device.no_content_sent".tr());
                  });
                } else {
                  String statusCode = await widget.device.client.sendData(dataToSend);
                  if (statusCode.split("\n")[0] != "200 OK") {
                    showPopupOK(context, "device.retry_text".tr(), "device.cant_send_command".tr(args: [statusCode]));
                  }
                  widget.device.client.startSendingLoop(context);
                }
              }
            }
          ),
        );
      }
    }

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded( // Ensures the TextField takes up available space
              child: TextField(
                controller: textInputController,
                decoration: InputDecoration(
                  //border: const OutlineInputBorder(),
                  hintText: textInputHintText,
                ),
              ),
            ),
            ...addons
          ],
        ),
      ),
    );
  }

  List<List<String>> timePickerData = List.empty(growable: true);

  String padLeft(String input, int totalWidth, String paddingChar) {
    if (input.length >= totalWidth) {
      return input;
    }
    return paddingChar * (totalWidth - input.length) + input;
  }

  Card _addTimePickerFeature(String feature)
  {
    // "timepicker1$22:00-23:00,button$Imposta$sendPOST ?valve=1&schedule=;"
    feature.replaceAll(";", "");
    List<Widget> addons = List.empty(growable: true);
    int timePickerId = int.parse(feature.split(dataSeparator)[0][feature.split(dataSeparator)[0].length - 1]);
    String dataToSend = feature.split(dataSeparator)[3];
    List<String> receivedTime = List<String>.filled(2, "00:00");
    TimeOfDay startTime = TimeOfDay.now();
    TimeOfDay endTime = TimeOfDay.now();
    String timePickerReceivedData;
    if (feature.contains(",")) {
      timePickerReceivedData = feature.split(",")[0].split(dataSeparator)[1];
      if (timePickerReceivedData != "") {
        receivedTime = timePickerReceivedData.split("-");
      }
    } else {
      timePickerReceivedData = feature.split(dataSeparator)[1];
      if (timePickerReceivedData != "") {
        receivedTime = timePickerReceivedData.split("-");
      }
    }

    if (timePickerData.length >= timePickerId) {
      receivedTime = timePickerData[timePickerId - 1];
    } else {
      timePickerData.add(receivedTime);
    }

    try {
      if (receivedTime.length >= 2) {
        startTime = TimeOfDay(
          hour: int.parse(receivedTime[0].split(":")[0]),
          minute: int.parse(receivedTime[0].split(":")[1]),
        );
        endTime = TimeOfDay(
          hour: int.parse(receivedTime[1].split(":")[0]),
          minute: int.parse(receivedTime[1].split(":")[1]),
        );
      }
    } catch (e) {
      debug.log("Invalid time format: $e");
    }

    for (String addon in feature.split(","))
    {
      if (addon.contains("button"))
      {
        String buttonText = addon.split(dataSeparator)[1];
        addons.add(
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              //backgroundColor: Color.alphaBlend(Colors.white.withAlpha(150), Theme.of(context).colorScheme.inversePrimary),
              //backgroundColor: Color.alphaBlend(Theme.of(context).colorScheme.surfaceContainerHigh.withAlpha(30), Theme.of(context).colorScheme.primary),
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
            child: Text(buttonText),
            onPressed: () async {
              await widget.device.client.stopSendingLoop();

              if (dataToSend.startsWith("send")) {
                // dataToSend: sendPOST ?key=<TEXTINPUT>
                String template = dataToSend.split("send")[1];
                String timeToSend = "${padLeft("${startTime.hour}", 2, "0")}:${padLeft("${startTime.minute}", 2, "0")}-${padLeft("${endTime.hour}", 2, "0")}:${padLeft("${endTime.minute}", 2, "0")}";
                String statusCode = await widget.device.client.sendData("$template$timeToSend");
                if (statusCode.split("\n")[0] != "200 OK") {
                  showPopupOK(context, "device.retry_text".tr(), "device.cant_send_command".tr(args: [statusCode]));
                }
                widget.device.client.startSendingLoop(context);
              } else {
                if (dataToSend == "") {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    showPopupOK(context, "device.error_text".tr(), "device.no_content_sent".tr());
                  });
                } else {
                  String statusCode = await widget.device.client.sendData(dataToSend);
                  if (statusCode.split("\n")[0] != "200 OK") {
                    showPopupOK(context, "device.retry_text".tr(), "device.cant_send_command".tr(args: [statusCode]));
                  }
                  widget.device.client.startSendingLoop(context);
                }
              }
            }
          ),
        );
      }
    }


    Color timePickerColor;
    if (timePickerReceivedData != "${receivedTime[0]}-${receivedTime[1]}") {
        // const Color.fromARGB(255, 255, 187, 187)
        timePickerColor = Color.alphaBlend(Theme.of(context).colorScheme.surfaceContainerLow.withAlpha(50), const Color.fromARGB(255, 255, 72, 72));
      } else {
        //timePickerColor = const Color.fromARGB(255, 243, 243, 243);
        timePickerColor = Theme.of(context).colorScheme.surfaceContainerLow;
      }

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                  backgroundColor: timePickerColor,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(5)),
                  ),
                  ),
                  child: Text("${padLeft("${startTime.hour}", 2, "0")}:${padLeft("${startTime.minute}", 2, "0")}"),
                  onPressed: () async {
                  TimeOfDay? newTime = await showTimePicker(
                    initialEntryMode: TimePickerEntryMode.dial,
                    context: context,
                    initialTime: startTime,
                  );
                  if (newTime != null) {
                    timePickerData[timePickerId - 1][0] = "${padLeft("${newTime.hour}", 2, "0")}:${padLeft("${newTime.minute}", 2, "0")}";
                  }
                  },
                ),
                const SizedBox(width: 8), // Add spacing between buttons
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                  backgroundColor: timePickerColor,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(5)),
                  ),
                  ),
                  child: Text("${padLeft("${endTime.hour}", 2, "0")}:${padLeft("${endTime.minute}", 2, "0")}"),
                  onPressed: () async {
                  TimeOfDay? newTime = await showTimePicker(
                    initialEntryMode: TimePickerEntryMode.dial,
                    context: context,
                    initialTime: endTime,
                  );
                  if (newTime != null) {
                    timePickerData[timePickerId - 1][1] = "${padLeft("${newTime.hour}", 2, "0")}:${padLeft("${newTime.minute}", 2, "0")}";
                  }
                  },
                ),
              ],
            ),
            ...addons
          ],
        ),
      ),
    );
  }

  void _addExternalFeature() async
  {
    if (externalFeaturesWidgets.isEmpty) {
      for (String rawFeature in rawExternalFeatures.split("\n")) {
        rawFeature.replaceAll(";", "");
        int externalFeatureID = int.parse(rawFeature.split(dataSeparator)[1]);
        createExternalFeature(externalFeatureID);
      }
    }

    externalFeaturesWidgets.clear();
    
    // external1$externalFeatureID$updateOnce;

    int index = 0;
    for (String rawFeature in rawExternalFeatures.split("\n")) {
      rawFeature.replaceAll(";", "");
      int externalFeatureID = int.parse(rawFeature.split(dataSeparator)[1]);

      externalFeaturesWidgets.addAll(await getExternalFeature(widget.device.ip, externalFeatureID, index, context, addExternalFeaturesListener));
      index++;
    }

    updateExternalFeaturesListener.value = !updateExternalFeaturesListener.value;
  }

  List<Widget> _generateDirectUserIOs(Device device)
  {
    List<Widget> widgetList = List.empty(growable: true);

    for (String feature in device.features)
    {
      /**
       * example of feature:
       * switch1:Valvola1,sensor:Stato:aperta,sensor:Litri/s:5.24;
       * timestamp1:Tempo CPU:123 ms;
       */

      if (feature.startsWith("external")) {
        //_addExternalFeature(feature);
        if (!rawExternalFeaturesAdded) {
          // external features changes are not supported!
          rawExternalFeatures += feature;
        }
      } else if (feature.startsWith("switch")) {
        widgetList.add(_addSwitchFeature(feature));
      } else if (feature.startsWith("timestamp")) {
        widgetList.add(_addTimestampFeature(feature));
      } else if (feature.startsWith("sensor")) {
        widgetList.add(_addSensorFeature(feature));
      } else if (feature.startsWith("button")) {
        widgetList.add(_addButtonFeature(feature));
      } else if (feature.startsWith("textinput")) {
        widgetList.add(_addTextInputFeature(feature));
      } else if (feature.startsWith("timepicker")) {
        widgetList.add(_addTimePickerFeature(feature));
      }
    }

    if (!rawExternalFeaturesAdded && rawExternalFeatures != "") {
      rawExternalFeaturesAdded = true;
      addExternalFeaturesListener.value = !addExternalFeaturesListener.value;
    } else {
      updateExternalFeaturesListener.value = !updateExternalFeaturesListener.value;
    }

    if (widgetList.isEmpty)
    {
      return List.empty(growable: false);
    }

    return widgetList;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          ValueListenableBuilder(
            valueListenable: updateIOs,
            builder: (context, updateIOs, child) {
              return Column(
                 children: [...userIOs]
              );
            }
          ),
          ValueListenableBuilder(
            valueListenable: updateExternalFeaturesListener,
            builder: (context, value, _) {
              return Column(
                 children: [...externalFeaturesWidgets]
              );
            }
          ),
        ]
      )
    );
  }
}
