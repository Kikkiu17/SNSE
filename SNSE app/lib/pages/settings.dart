import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:developer' as dev;
import 'package:easy_localization/easy_localization.dart';

import '../main.dart'; // To access themeNotifier
import '../languages.dart';

const String dataSeparator = "\$";

int gatewayIpLast = 0;
String readableMaxIp = "";
bool darkModeSetByUser = false;
String _themeValue = "light";

const int defaultPort = 34677; // default port for ESP devices

String extServerIP = "";
const int extServerPort = 34678;

// Helper encode/decode functions:
String encode(Map<String, dynamic> map) => jsonEncode(map);
Map<String, dynamic> decode(String str) => jsonDecode(str);

class DefaultSavedSettings {
  final int maxIp = 64;
  final bool darkMode = false;
  final int scanTimeout = 30; // ms
  final bool isThemeSystem = true;
  final String extServerIP = "127.0.0.1";
}

class SavedSettings {
  static int _maxIp = DefaultSavedSettings().maxIp;
  static bool _darkMode = DefaultSavedSettings().darkMode;
  static int _scanTimeout = DefaultSavedSettings().scanTimeout;
  static bool _isThemeSystem = DefaultSavedSettings().isThemeSystem;
  static String _extServerIP = DefaultSavedSettings().extServerIP;

  Map<String, dynamic> toMap() {
    return {
      'maxIp': _maxIp,
      'darkMode': _darkMode,
      'scanTimeout': _scanTimeout,
      'isThemeSystem': _isThemeSystem,
      'extServerIP': _extServerIP
    };
  }

  void setDefault(BuildContext? context) {
    _maxIp = DefaultSavedSettings().maxIp;        // max number of IPs to scan
    _darkMode = DefaultSavedSettings().darkMode;
    _scanTimeout = DefaultSavedSettings().scanTimeout;
    _isThemeSystem = DefaultSavedSettings().isThemeSystem;
    _extServerIP = DefaultSavedSettings().extServerIP;
    //_locale = DefaultSavedSettings().locale;
    if (context != null) {
      context.resetLocale();
    }
  }

  void fromMap(Map<String, dynamic> map) {
    _maxIp = map['maxIp'];
    _darkMode = map['darkMode'];
    _scanTimeout = map['scanTimeout'];
    _isThemeSystem = map['isThemeSystem'];
    _extServerIP = map['extServerIP'];
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('savedSettings', encode(toMap()));
  }

  Future<void> load() async {
    setDefault(null); // make sure that there are no uninitialized variables

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

      return "sys";
    } else {
      return (_darkMode) ? "dark" : "light";
    }
  }

  void setExtServerIP(String ip) {
    _extServerIP = ip;
  }

  String getExtServerIP() {
    return _extServerIP;
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
    extServerIP = savedSettings.getExtServerIP();
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
    _themeValue = savedSettings.getThemeText();
    themeNotifier.value = savedSettings.isDarkMode() ? ThemeMode.dark : ThemeMode.light;


    if (!rebuild) {
      if (extServerIP.split('.').length == 4) {
        savedSettings.setExtServerIP(extServerIP);
      }

      if (readableMaxIp.split('.').length != 4) return dev.log("Invalid max IP value: $readableMaxIp, using default ${savedSettings.getMaxIp()}");

      int? maxIp = int.tryParse(readableMaxIp.split('.').last);
      if (maxIp == null || maxIp <= gatewayIpLast || maxIp > 255) return dev.log("Invalid max IP value: $readableMaxIp, using default ${savedSettings.getMaxIp()}");

      savedSettings.setMaxIp(maxIp);
    }
  }

  Future<void> _getNetworkInfo() async {
    try {
      _wifiIPv4 = await _networkInfo.getWifiIP();
    } on PlatformException catch (e) {
      dev.log('Failed to get Wifi IPv4', error: e);
    }

    try {
      _wifiSubmask = await _networkInfo.getWifiSubmask();
    } on PlatformException catch (e) {
      dev.log('Failed to get Wifi submask address', error: e);
    }

    try {
      _wifiGatewayIP = await _networkInfo.getWifiGatewayIP();
      if (_wifiGatewayIP != null) {
        gatewayIpLast = int.parse(_wifiGatewayIP!.split('.').last);
      }
    } on PlatformException catch (e) {
      dev.log('Failed to get Wifi gateway address', error: e);
    }

    readableMaxIp = "${(_wifiGatewayIP ?? "N/A").split(".").sublist(0, 3).join(".")}.${savedSettings.getMaxIp()}";

    dev.log("WiFi IPv4: $_wifiIPv4, Gateway: $_wifiGatewayIP, Submask: $_wifiSubmask");
    dev.log("Readable Max IP: $readableMaxIp");
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (rebuild) {
      rebuild = false;
      _getNetworkInfo();
      extServerIP = savedSettings.getExtServerIP();
    }
    
    return Scaffold(
      body: ListView(
        children: [
          ListTile(
            title: Text('settings.connection_info.title'.tr()),
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
                Text("settings.connection_info.current_ip".tr(args: [_wifiIPv4 ?? 'N/A'])),
                Text("settings.connection_info.gateway".tr(args: [_wifiGatewayIP ?? 'N/A'])),
                Text("settings.connection_info.subnet_mask".tr(args: [_wifiSubmask ?? 'N/A'])),
                Text("settings.connection_info.port".tr(args: [defaultPort.toString()])),
                Text("settings.connection_info.ext_server_ip_port".tr(args: [extServerPort.toString()])),
              ],
            ),
          ),
          ListTile(
            title: Text("settings.connection_info.ext_server_ip".tr()),
            subtitle: Text("settings.connection_info.ext_server_ip_description".tr()),
            trailing: SizedBox(
              width: 140,
              height: 25,
              child: TextField(
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.only(bottom: 1),
                  hintText: extServerIP,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  extServerIP = value;
                },
              ),
            ),
          ),
          ListTile(
            title: Text("settings.device_discovery.title".tr()),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
              //side: const BorderSide(width: 0.8),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          ListTile(
            title: Text("settings.device_discovery.max_ip".tr()),
            subtitle: Text("settings.device_discovery.max_ip_description".tr()),
            trailing: SizedBox(
              width: 140,
              height: 25,
              child: TextField(
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.only(bottom: 1),
                  hintText: readableMaxIp,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  readableMaxIp = value;
                },
              ),
            ),
          ),
          ListTile(
            title: Text("settings.device_discovery.timeout".tr()),
            subtitle: Text("settings.device_discovery.timeout_description".tr()),
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
            title: Text("settings.interface.title".tr()),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
              //side: const BorderSide(width: 0.8),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          ListTile(
            title: Text("settings.interface.theme.title".tr()),
            trailing: DropdownButton<String>(
                value: _themeValue,
                items: [
                  DropdownMenuItem(value: 'sys', child: Text("settings.interface.theme.system".tr())),
                  DropdownMenuItem(value: 'light', child: Text("settings.interface.theme.light_mode".tr())),
                  DropdownMenuItem(value: 'dark', child: Text("settings.interface.theme.dark_mode".tr())),
              ],
              onChanged: (value) {
                _themeValue = value!;
                setState(() {
                  if (value == 'dark') {
                    savedSettings.setDarkMode(true);
                    savedSettings.setThemeSystem(false);
                  } else if (value == 'light') {
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
          ListTile(
            title: Text("settings.interface.language_text".tr()),
            trailing: DropdownButton<String>(
              value: Localizations.localeOf(context).languageCode,
              items: languageDropDownMenuItems(context),
              onChanged: (value) {
                if (value != null) {
                  context.setLocale(Locale(value));
                }
              },
            ),
          ),
          ListTile(
            title: ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
              ),
              child: Text("settings.restore_to_default".tr()),
              onPressed: () {
                setState(() {
                  rebuild = true;
                  savedSettings.setDefault(context);
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