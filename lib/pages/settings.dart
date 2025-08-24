import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:developer' as developer;
import '../main.dart'; // To access themeNotifier

const String dataSeparator = "\$";

int gatewayIpLast = 0;
String readableMaxIp = "";
bool darkModeSetByUser = false;
String _themeValue = "Chiaro";

const int defaultPort = 34677; // default port for ESP devices

// Helper encode/decode functions:
String encode(Map<String, dynamic> map) => jsonEncode(map);
Map<String, dynamic> decode(String str) => jsonDecode(str);

class DefaultSavedSettings {
  final int maxIp = 64;
  final bool darkMode = false;
  final int scanTimeout = 15; // ms
  final bool isThemeSystem = true;
}

class SavedSettings {
  static int _maxIp = DefaultSavedSettings().maxIp;
  static bool _darkMode = DefaultSavedSettings().darkMode;
  static int _scanTimeout = DefaultSavedSettings().scanTimeout;
  static bool _isThemeSystem = DefaultSavedSettings().isThemeSystem;

  Map<String, dynamic> toMap() {
    return {
      'maxIp': _maxIp,
      'darkMode': _darkMode,
      'scanTimeout': _scanTimeout,
      'isThemeSystem': _isThemeSystem,
    };
  }

  void setDefault() {
    _maxIp = DefaultSavedSettings().maxIp;        // max number of IPs to scan
    _darkMode = DefaultSavedSettings().darkMode;
    _scanTimeout = DefaultSavedSettings().scanTimeout;
    _isThemeSystem = DefaultSavedSettings().isThemeSystem;
  }

  void fromMap(Map<String, dynamic> map) {
    _maxIp = map['maxIp'];
    _darkMode = map['darkMode'];
    _scanTimeout = map['scanTimeout'];
    _isThemeSystem = map['isThemeSystem'];
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('savedSettings', encode(toMap()));
  }

  Future<void> load() async {
    setDefault(); // make sure that there are no uninitialized variables

    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('savedSettings');
    if (str != null) {
      fromMap(decode(str));

      _themeValue = getThemeText();

      // Apply loaded settings (change notifiers)
      themeNotifier.value = _darkMode ? ThemeMode.dark : ThemeMode.light;
    }
  }

  int getMaxIp() {
    return _maxIp;
  }

  void setMaxIp(int value) {
    _maxIp = value;
  }

  bool isDarkMode() {
    return _darkMode;
  }

  void setDarkMode(bool value) {
    _darkMode = value;
  }

  int getScanTimeout() {
    return _scanTimeout;
  }

  void setScanTimeout(int value) {
    _scanTimeout = value;
  }

  bool isThemeSystem() {
    return _isThemeSystem;
  }

  void setThemeSystem(bool value) {
    _isThemeSystem = value;
  }

  String getThemeText() {
    if (_isThemeSystem) {
      var brightness = SchedulerBinding.instance.platformDispatcher.platformBrightness;
      bool isDarkMode = brightness == Brightness.dark;

      if (isDarkMode) {
        _darkMode = true;
      } else {
        _darkMode = false;
      }

      return "Sistema";
    } else {
      return (_darkMode) ? "Scuro" : "Chiaro";
    }
  }
}

SavedSettings savedSettings = SavedSettings();

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with WidgetsBindingObserver {
  final NetworkInfo _networkInfo = NetworkInfo();
  String? _wifiIPv4,
        _wifiGatewayIP,
        _wifiSubmask;

  bool rebuild = false;

  @override
  void initState() {
    _getNetworkInfo();
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void dispose() {
    applySettings();
    savedSettings.save(); // Save settings on dispose
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached ||
    state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      // app in background
      applySettings();
      savedSettings.save(); // Save settings on pause
    }
  }

  void applySettings() {
    // SAVE IP
    if (!rebuild) {
      if (readableMaxIp.split('.').length != 4) return developer.log("Invalid max IP value: $readableMaxIp, using default ${savedSettings.getMaxIp()}");

      int? maxIp = int.tryParse(readableMaxIp.split('.').last);
      if (maxIp == null || maxIp <= gatewayIpLast || maxIp > 255) return developer.log("Invalid max IP value: $readableMaxIp, using default ${savedSettings.getMaxIp()}");

      savedSettings.setMaxIp(maxIp);
    }

    _themeValue = savedSettings.getThemeText();
    themeNotifier.value = savedSettings.isDarkMode() ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> _getNetworkInfo() async {
    try {
      _wifiIPv4 = await _networkInfo.getWifiIP();
    } on PlatformException catch (e) {
      developer.log('Failed to get Wifi IPv4', error: e);
    }

    try {
      _wifiSubmask = await _networkInfo.getWifiSubmask();
    } on PlatformException catch (e) {
      developer.log('Failed to get Wifi submask address', error: e);
    }

    try {
      _wifiGatewayIP = await _networkInfo.getWifiGatewayIP();
      if (_wifiGatewayIP != null) {
        gatewayIpLast = int.parse(_wifiGatewayIP!.split('.').last);
      }
    } on PlatformException catch (e) {
      developer.log('Failed to get Wifi gateway address', error: e);
    }

    readableMaxIp = "${(_wifiGatewayIP ?? "N/A").split(".").sublist(0, 3).join(".")}.${savedSettings.getMaxIp()}";

    developer.log("WiFi IPv4: $_wifiIPv4, Gateway: $_wifiGatewayIP, Submask: $_wifiSubmask");
    developer.log("Readable Max IP: $readableMaxIp");
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (rebuild) {
      rebuild = false;
      _getNetworkInfo();
    }
    return Scaffold(
      body: ListView(
        children: [
          ListTile(
            title: const Text('Informazioni WiFi'),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
              //side: const BorderSide(width: 0.8),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          ListTile(
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("IP di questo dispositivo: ${_wifiIPv4 ?? 'N/A'}"),
                Text("Gateway: ${_wifiGatewayIP ?? 'N/A'}"),
                Text("Subnet mask: ${_wifiSubmask ?? 'N/A'}"),
                const Text("Porta usata per le connessioni: $defaultPort"),
              ],
            ),
          ),
          ListTile(
            title: const Text('Ricerca Dispositivi'),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
              //side: const BorderSide(width: 0.8),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          ListTile(
            title: const Text("Massimo IP per la ricerca"),
            subtitle: const Text("Verranno scansionati tutti gli IP a partire dal gateway fino all'IP specificato"),
            trailing: SizedBox(
              width: 150,
              child: TextField(
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: readableMaxIp,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  readableMaxIp = value;
                },
              ),
            ),
          ),
          ListTile(
            title: const Text("Timeout di ricerca"),
            subtitle: const Text("Timeout di ogni dispositivo scansionato. Se il dispositivo non risponde entro il timeout inserito (in millisecondi), si passa al prossimo"),
            trailing: SizedBox(
              width: 50,
              child: TextField(
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: "${savedSettings.getScanTimeout().toString()} ms",
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) {
                  savedSettings.setScanTimeout(int.tryParse(value) ?? savedSettings.getScanTimeout());
                },
              ),
            ),
          ),
          ListTile(
            title: const Text('Interfaccia'),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
              //side: const BorderSide(width: 0.8),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          ListTile(
            title: const Text('Tema'),
            trailing: DropdownButton<String>(
                value: _themeValue,
                items: const [
                DropdownMenuItem(value: 'Sistema', child: Text('Sistema')),
                DropdownMenuItem(value: 'Chiaro', child: Text('Chiaro')),
                DropdownMenuItem(value: 'Scuro', child: Text('Scuro')),
              ],
              onChanged: (value) {
                _themeValue = value!;
                setState(() {
                  if (value == 'Scuro') {
                    savedSettings.setDarkMode(true);
                    savedSettings.setThemeSystem(false);
                  } else if (value == 'Chiaro') {
                    savedSettings.setDarkMode(false);
                    savedSettings.setThemeSystem(false);
                  } else {
                    savedSettings.setThemeSystem(true);
                    var brightness = MediaQuery.of(context).platformBrightness;
                    bool isDarkMode = brightness == Brightness.dark;

                    if (isDarkMode) {
                      savedSettings.setDarkMode(true);
                    } else {
                      savedSettings.setDarkMode(false);
                    }
                  }

                  applySettings();
                });
              },
            ),
          ),
          /*ListTile(
            title: ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
              ),
              child: const Text("Salva"),
              onPressed: () {
                applySettings();
                savedSettings.save();
              }
            )
          ),*/
          ListTile(
            title: ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
              ),
              child: const Text("Ripristina a default"),
              onPressed: () {
                setState(() {
                  rebuild = true;
                  savedSettings.setDefault();
                  applySettings();
                  savedSettings.save();
                });
              }
            )
          ),
        ],
      ),
    );
  }
}