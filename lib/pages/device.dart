// warning not needed, context is always mounted here
// ignore_for_file: use_build_context_synchronously

import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'dart:async';
import 'package:easy_localization/easy_localization.dart';

import '../discovery.dart';
import '../tiles/tiles.dart';
import 'settings.dart';

const int updateTime = 250; // ms
const int maxTimeouts = 5;
bool update = true;
bool forceShowNotification = false;

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

class ESPSocket {
  late Socket socket;
  static String _answer = "";
  static bool _dataReceived = false;
  static bool _error = false;
  static bool _busy = false;

  void setBusy(bool value) {
    _busy = value;
  }

  bool isBusy() {
    return _busy;
  }

  void dataHandler(data) async {
    _answer = String.fromCharCodes(data).trim();
    developer.log("Received: $_answer");
    _dataReceived = true;
  }

  void errorHandler(error, StackTrace trace) {
    developer.log("Error in socket: $error", stackTrace: trace);
    _error = true;
  }

  Future<String> sendAndWaitForAnswerTimeout(data) async {
    _busy = true;
    socket.write(data);

    int elapsed = 0;
    while (!_dataReceived && !_error && elapsed < timeout) {
      await Future.delayed(const Duration(milliseconds: 10));
      elapsed += 10;
    }

    _busy = false;

    if (_error) {
      _dataReceived = false;
      _error = false;
      return "";
    }

    if (!_dataReceived) {
      return "";
    }

    _dataReceived = false;
    return _answer;
  }

  /*Future<String> getAnswerTimeout() async {
    await socket.flush();
    try {
      var answer = await _completer.future.timeout(Duration(milliseconds: timeout));
      _completer = Completer();
      answer = utf8.decode(answer);
      return answer;
    } catch (e) {
      return "";
    }
  }*/

  Future<bool> connect(String ip, int port) async {
    try {
      socket = await Socket.connect(ip, defaultPort);
    } catch (e) {
      developer.log("Error connecting to socket: $e");
      return false;
    }

    developer.log("Connected to $ip");
    _busy = false;
    
    socket.listen(
      dataHandler,
      onError: errorHandler,
      cancelOnError: false
    );

    return true;
  }

  Future<void> flush() async {
    _busy = false;
    await socket.flush();
  }

  Future<void> close() async {
    _busy = false;
    await socket.flush();
    await socket.close();
  }
}

class Device {
  String id = "";
  String name = "";
  String ip = "";
  List<String> features = List.empty(growable: true);
  final ESPSocket espsocket = ESPSocket();
  bool updatingValues = false;
  int _lastNotificationID = 0;

  Future<String> sendName(String name) async {
    while (!await espsocket.connect(ip, defaultPort)) {}
    await espsocket.flush();
    String resp = await espsocket.sendAndWaitForAnswerTimeout("POST ?wifi=changename&name=$name");
    await espsocket.close();
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

  Future<bool> getFeatures() async {
    String response = await espsocket.sendAndWaitForAnswerTimeout("GET ?features");
    if (!response.contains("200 OK") || response == "") {
      return false;
    }
    features = response.split("\n")[1].split(";");
    return true;
  }

  DevicePage setThisDevicePage() {
    return DevicePage(device: this);
  }

  Future<String> getNotification(bool showAnyway) async {
    String response = await espsocket.sendAndWaitForAnswerTimeout("GET ?notification");
    if (!response.contains("200 OK") || response.contains("Vuoto")) {
      return "";
    }

    try {
      response = response.split("200 OK")[1].trim();
      int notificationID = int.parse(response.split(dataSeparator)[0]);

      if (notificationID != _lastNotificationID || showAnyway) {
        _lastNotificationID = notificationID;
        return response.split(dataSeparator)[1];
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

  Future<bool> getAndShowNotification(BuildContext context, bool showAnyway) async {
    String notificationText = await getNotification(showAnyway);
    if (notificationText != "" || showAnyway) {
      if (context.mounted) {
        if (notificationText == "" && showAnyway) {
          showNoNewNotifications(context);
        } else {
          showNotification(context, notificationText);
        }
        showAnyway = false;
        return true;
      }
    }
    return false;
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

  // FUNZIONI PERSONALIZZATE PER L'APPLICAZIONE SPECIFICA
  // FUNZIONI PULSANTE
  Future<String> openCloseValve(String id) async {
    //await espsocket.flush();
    String resp = await espsocket.sendAndWaitForAnswerTimeout("GET ?valve=$id");
    if (resp.contains("200 OK")) {
      String isOpen = resp.split("\n")[1];
      if (isOpen == "aperta") {
        espsocket.sendAndWaitForAnswerTimeout("POST ?valve=$id&cmd=close");
      } else if (isOpen == "chiusa") {
        espsocket.sendAndWaitForAnswerTimeout("POST ?valve=$id&cmd=open");
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

Future<bool> connect(BuildContext context, Device dev) async {
  bool connected = await dev.espsocket.connect(dev.ip, defaultPort);

  if (connected) {
    developer.log("Starting");
    startUpdate(context, dev);
    return true;
  }

  return false;
}

void startUpdate(BuildContext context, Device dev) async {
  update = true;
  exit = false;
  updateDirectUserIOs(context, dev);
}

Future<bool> stopUpdate(Device dev) async {
  const int delayDuration = 5;
  update = false;
  int elapsed = 0;
  while (!exit) {
    await Future.delayed(const Duration(milliseconds: delayDuration));
    // wait for the update to finish
    elapsed += delayDuration;
    if (elapsed > timeout) {
      return false;
    }
  }
  return true;
}

Future<bool> waitBusy(Device dev) async {
  // returns whether the device is not busy
  const int delayDuration = 5;
  int elapsed = 0;
  while (dev.espsocket.isBusy()) {
    await Future.delayed(const Duration(milliseconds: delayDuration));
    elapsed += delayDuration;
    if (elapsed > timeout) {
      dev.espsocket.setBusy(false);
      return true;
    }
  }

  return true;
}

bool exit = false;
List<Widget> userIOs = List.empty(growable: true);
bool firstRun = true;

class _DevicePageState extends State<DevicePage> with WidgetsBindingObserver {
  void _generateIOsListener() {
    if (!update) return;
    updateIOs.value = false;
    userIOs = _generateDirectUserIOs(widget.device);
    updateIOs.value = true;
  }

  @override
  void initState() {
    super.initState();
    firstRun = true;
    userIOs = List.empty(growable: true);
    userIOs.add(loadingTileNoText);
    generateIOs = ValueNotifier(false);
    generateIOs.addListener(_generateIOsListener);

    connect(context, widget.device).then((connected) {
      if (connected) {
        userIOs = _generateDirectUserIOs(widget.device);
      }
    });

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    firstRun = false;
    Future.microtask(() async {
      await stopUpdate(widget.device);
      generateIOs.removeListener(_generateIOsListener);
      generateIOs.dispose();
      //widget.device.espsocket.flush();
      //widget.device.espsocket.socket.flush();
      //widget.device.espsocket.socket.destroy();
      widget.device.espsocket.close();
    });

    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached ||
    state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      // app in background
      Future.microtask(() async {
        await stopUpdate(widget.device);
        widget.device.espsocket.close();
        //widget.device.espsocket.socket.flush();
        //widget.device.espsocket.socket.destroy();
      });
    } else if (state == AppLifecycleState.resumed) {
      // app in foreground
      connect(context, widget.device);
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
                      bool notBusy = await waitBusy(widget.device);
                      if (!notBusy) {
                        showPopupOK(context, "device.error_text".tr(), "device.device_still_busy".tr());
                        return;
                      }

                      bool stopped = await stopUpdate(widget.device);
                      if (!stopped) {
                        showPopupOK(context, "device.error_text".tr(), "device.values_update_timeout".tr());
                        return;
                      }

                      String statusCode = await widget.device.openCloseValve(switchId);
                      if (statusCode != "200 OK") {
                        showPopupOK(context, "device.retry_text".tr(), "device.cant_send_command".tr(args: [statusCode]));
                      }

                      startUpdate(context, widget.device);
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
                    bool notBusy = await waitBusy(widget.device);
                    if (!notBusy) {
                      showPopupOK(context, "device.error_text".tr(), "device.device_still_busy".tr());
                      return;
                    }

                    bool stopped = await stopUpdate(widget.device);
                    if (!stopped) {
                      showPopupOK(context, "device.error_text".tr(), "device.values_update_timeout".tr());
                      return;
                    }

                    String statusCode = await widget.device.espsocket.sendAndWaitForAnswerTimeout(dataToSend);
                    if (statusCode != "200 OK") {
                      showPopupOK(context, "device.retry_text".tr(), "device.cant_send_command".tr(args: [statusCode]));
                    }

                    startUpdate(context, widget.device);
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
              bool notBusy = await waitBusy(widget.device);
              if (!notBusy) {
                showPopupOK(context, "device.error_text".tr(), "device.device_still_busy".tr());
                return;
              }

              bool stopped = await stopUpdate(widget.device);
              if (!stopped) {
                showPopupOK(context, "device.error_text".tr(), "device.values_update_timeout".tr());
                return;
              }

              if (dataToSend.startsWith("send")) {
                // dataToSend: sendPOST ?key=<TEXTINPUT>
                String template = dataToSend.split("send")[1];
                String statusCode = await widget.device.espsocket.sendAndWaitForAnswerTimeout("$template${textInputController.text}");
                if (statusCode.split("\n")[0] != "200 OK") {
                  showPopupOK(context, "device.retry_text".tr(), "device.cant_send_command".tr(args: [statusCode]));
                }
                textInputController.clear();
                startUpdate(context, widget.device);
              } else {
                if (dataToSend == "") {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    showPopupOK(context, "device.error_text".tr(), "device.no_content_sent".tr());
                  });
                } else {
                  String statusCode = await widget.device.espsocket.sendAndWaitForAnswerTimeout(dataToSend);
                  if (statusCode.split("\n")[0] != "200 OK") {
                    showPopupOK(context, "device.retry_text".tr(), "device.cant_send_command".tr(args: [statusCode]));
                  }
                  startUpdate(context, widget.device);
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
    TimeOfDay startTime;
    TimeOfDay endTime;
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

    if (receivedTime.length < 2) {
      startTime = TimeOfDay.now();
      endTime = TimeOfDay.now();
    } else {
      startTime = TimeOfDay(
      hour: int.parse(receivedTime[0].split(":")[0]),
      minute: int.parse(receivedTime[0].split(":")[1]),
      );
      endTime = TimeOfDay(
      hour: int.parse(receivedTime[1].split(":")[0]),
      minute: int.parse(receivedTime[1].split(":")[1]),
      );
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
              bool notBusy = await waitBusy(widget.device);
              if (!notBusy) {
                showPopupOK(context, "device.error_text".tr(), "device.device_still_busy".tr());
                return;
              }

              bool stopped = await stopUpdate(widget.device);
              if (!stopped) {
                showPopupOK(context, "device.error_text".tr(), "device.values_update_timeout".tr());
                return;
              }

              if (dataToSend.startsWith("send")) {
                // dataToSend: sendPOST ?key=<TEXTINPUT>
                String template = dataToSend.split("send")[1];
                String timeToSend = "${padLeft("${startTime.hour}", 2, "0")}:${padLeft("${startTime.minute}", 2, "0")}-${padLeft("${endTime.hour}", 2, "0")}:${padLeft("${endTime.minute}", 2, "0")}";
                String statusCode = await widget.device.espsocket.sendAndWaitForAnswerTimeout("$template$timeToSend");
                if (statusCode.split("\n")[0] != "200 OK") {
                  showPopupOK(context, "device.retry_text".tr(), "device.cant_send_command".tr(args: [statusCode]));
                }
                startUpdate(context, widget.device);
              } else {
                if (dataToSend == "") {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    showPopupOK(context, "device.error_text".tr(), "device.no_content_sent".tr());
                  });
                } else {
                  String statusCode = await widget.device.espsocket.sendAndWaitForAnswerTimeout(dataToSend);
                  if (statusCode.split("\n")[0] != "200 OK") {
                    showPopupOK(context, "device.retry_text".tr(), "device.cant_send_command".tr(args: [statusCode]));
                  }
                  startUpdate(context, widget.device);
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

      if (feature.startsWith("switch")) {
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
        ]
      )
    );
  }
}

DateTime lastUpdateTime = DateTime.now().subtract(const Duration(seconds: 10));

void updateDirectUserIOs(BuildContext context, Device dev) async {
  if (exit) return;

  final start = DateTime.now();

  final updateTimeDiff = DateTime.now().difference(lastUpdateTime).inMilliseconds;
  if (updateTimeDiff < updateTime && !firstRun) {
    exit = true;
    return;
    // if the time it took to update is less than the required update time, it means there is another
    // thread executing this function, so stop this one
  }
  lastUpdateTime = DateTime.now();

  bool notBusy = await waitBusy(dev);
  if (notBusy) {
    dev.updatingValues = true;
    //await Future.delayed(const Duration(milliseconds: 5));
    await dev.getAndShowNotification(context, forceShowNotification);
    forceShowNotification = false;
    await dev.getFeatures();
    generateIOs.value = !generateIOs.value;
  }

  final elapsed = DateTime.now().difference(start).inMilliseconds;
  if (elapsed < updateTime) {
    await Future.delayed(Duration(milliseconds: updateTime - elapsed));
  }

  if (!update) {
    exit = true;
    return;
  }
  dev.updatingValues = false;

  updateDirectUserIOs(context, dev);
}
