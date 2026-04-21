import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:snse/pages/directsocket.dart';
import 'package:back_button_interceptor/back_button_interceptor.dart';

import '../main.dart';
import 'settings.dart';

import 'device.dart';
import '../discovery.dart';
import '../tiles/tiles.dart';
import '../flashytabbar/flashy_tab_bar2.dart';

const int maxPages = 4;
const int homePageIndex = 0;
const int devicePageIndex = 1;
//const int directSocketPageIndex = 2;
const int settingsPageIndex = 2;
const int directSocketPageIndex = 3; // not used in the tab bar

class HomePage extends StatefulWidget
{
  final SharedPreferences storage;
  const HomePage({super.key, required this.storage});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Socket? socket;
  static Widget pageToRender = Text("loading_text".tr());
  static bool _updateExistingIDs = true;
  static List<String> _existingIPandIDs = List.empty(growable: true);
  static List<String> _manuallyAddedIPs = List.empty(growable: true);

  static List<Widget> pages = List.filled(maxPages, loadingTile, growable: false);
  static Device _selectedDevice = Device();
  static int _selectedIndex = 0;
  static int _lastSelectedIndex = 0;

  bool darkTheme = false;
  bool firstRun = true;
  late Locale lastLocale;

  // Tracks how many devices have been found so far during an active scan.
  // Reset to null when not scanning so the badge is hidden.
  int? _foundDeviceCount;

@override
  void initState() {
    super.initState();
    pages[devicePageIndex] = grayTextCenteredTile("no_device_selected".tr());
    pages[settingsPageIndex] = const SettingsPage();
    pages[directSocketPageIndex] = const DirectSocketPage();
    _createDeviceList();
    BackButtonInterceptor.add(backInterceptor);
  }

@override
  void dispose() {
    BackButtonInterceptor.remove(backInterceptor);
    super.dispose();
  }

  void _saveItem(List<String> ids) async {
    await widget.storage.setStringList("devices", ids);
  }

  Future<List<String>> _getData() async {
    var item = widget.storage.getStringList("devices");
    if (item == null) return List.empty();
    return item.cast<String>();
  }

  Future<void> _createDeviceList() async {
    if (_updateExistingIDs) {
      _updateExistingIDs = false;
      _existingIPandIDs = await _getData();
      if (_manuallyAddedIPs.isNotEmpty && _existingIPandIDs.isNotEmpty) {
        _existingIPandIDs.addAll(_manuallyAddedIPs);
      }
    }

    if (!mounted) return;
    setState(() {
      _foundDeviceCount = 0;  // show 0 immediately so the badge appears before results arrive
      pages[homePageIndex] = loadingTile;
    });

    final deviceList = await discoverDevices(
      _existingIPandIDs,
      onScanComplete: (ipCount) {
        if (mounted) setState(() { _foundDeviceCount = ipCount; });
      },
      onDeviceFound: (count) {
        if (mounted) setState(() { _foundDeviceCount = count; });
      },
    );

    if (!mounted) return;

    // --- AGGIUNTO: Ordina per IP decrescente ---
    deviceList.sort((a, b) {
      final aParts = a.ip.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final bParts = b.ip.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      
      for (int i = 0; i < 4; i++) {
        if (aParts.length > i && bParts.length > i) {
          if (bParts[i] != aParts[i]) return bParts[i].compareTo(aParts[i]);
        }
      }
      return 0;
    });
    // ------------------------------------------

    // Do NOT reset _foundDeviceCount - the badge stays visible on the homepage.

    _existingIPandIDs = List.empty(growable: true);
    List<Widget> cardList = List.empty(growable: true);
    List<String> ipsAndIds = List.empty(growable: true);

    for (Device dev in deviceList) {
      cardList.add(_createDeviceTile(dev, context));
      cardList.add(const Padding(padding: EdgeInsets.only(top: 8.0)));
      ipsAndIds.add("${dev.ip};${dev.id}");
    }

    if (cardList.isNotEmpty) {
      // list update button
      cardList.add(
      ListTile(
          title: ElevatedButton(
              child: Text(context.tr("update_text")),
            onPressed: () {
              setState(() {
                _updateExistingIDs = true;
                _createDeviceList();
              });
            }
          )
        )
      );
    } else {
      print("nope");
      cardList.add(grayTextCenteredTile(context.tr("no_device_found")));
    }

    // discovery button
    cardList.add(
    ListTile(
        title: ElevatedButton(
          child: Text(context.tr("discover_devices_text")),
          onPressed: () {
            setState(() {
              _updateExistingIDs = false;
              _createDeviceList();
            });
          }
        )
      )
    );

    _saveItem(ipsAndIds);

    setState(() {
      pages[homePageIndex] = ListView(children: cardList);
    });
  }

  ListTile _createDeviceTile(Device device, BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      tileColor: (device.name == "OFFLINE") ? Color.alphaBlend(Theme.of(context).colorScheme.surfaceContainer.withAlpha(200), const Color.fromARGB(255, 255, 148, 148)) : theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      leading: CircleAvatar(
        backgroundColor: (device.name == "OFFLINE") ? Theme.of(context).colorScheme.surfaceContainerLow : null,
        child: const Icon(Icons.sensors)
      ),
      title: Text(device.name),
      subtitle: Text("${device.id} | ${device.ip}"),
      trailing: InkWell(
        child: SizedBox(
          height: 50,
          width: 50,
          child: Icon(Icons.edit, color: (device.name == "OFFLINE") ? Colors.grey : Theme.of(context).colorScheme.primary)
        ),
        onTap: () {
          if (device.name == "OFFLINE") {
            showPopupOK(context, "Impossibile effettuare l'azione", "Il dispositivo sembra essere offline. prova ad aggiornare la lista.");
          } else {
            device.changeName(context).then((value) {
              setState(() {
                _updateExistingIDs = true;
                _createDeviceList();
              });
            });
          }
        },
      ),
      enableFeedback: true,
      onTap: () {
        if (device.name == "OFFLINE") {
          showPopupOK(context, "Impossibile effettuare l'azione", "Il dispositivo sembra essere offline. prova ad aggiornare la lista.");
        } else {
          pages[devicePageIndex] = device.setThisDevicePage();
          setState(() {
            _lastSelectedIndex = homePageIndex;
            _selectedIndex = devicePageIndex;
            _selectedDevice = device;
          });
        }
      },
    );
  }

  Widget getActionButton() {
    if (_selectedIndex == devicePageIndex && _selectedDevice.name != "") {
      return IconButton(
        icon: const Icon(Icons.notifications),
        onPressed: () {
          forceShowNotification = true;
        },
      );
    }

    if (_selectedIndex == settingsPageIndex) {
      return IconButton(
        icon: const Icon(Icons.dns_rounded),
        onPressed: () {
          setState(() {
            _selectedIndex = directSocketPageIndex;
            _lastSelectedIndex = settingsPageIndex;
          });
        },
      );
    }

    if (_selectedIndex == directSocketPageIndex) {
      return IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () {
          setState(() {
            _selectedIndex = _lastSelectedIndex; 
            _lastSelectedIndex = homePageIndex;         
          });
        },
      );
    }

    String newDeviceIp = "";

    if (_selectedIndex == homePageIndex) {
      return IconButton(
        icon: const Icon(Icons.add),
        onPressed: () {
          showDialog (
            context: context,
            builder: (BuildContext context) => AlertDialog(
              title: Text("add_manually_text".tr()),
              content: TextField(
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: "direct_socket.device_ip".tr(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (text) {
                  newDeviceIp = text;
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text("cancel_text".tr()),
                ),
                TextButton(
                  onPressed: () async {
                    if (newDeviceIp == "") {
                      showPopupOK(context, "device.error_text".tr(), "device.ip_not_empty".tr());
                      return;
                    }

                    _updateExistingIDs = true;
                    if (!_manuallyAddedIPs.contains(newDeviceIp)) {
                      _manuallyAddedIPs.add(newDeviceIp);
                    }
                    await _createDeviceList();

                    setState(() {
                      _manuallyAddedIPs = List.empty(growable: true);
                    });

                    if (context.mounted) {
                      Navigator.pop(context, true);
                    }
                  },
                  child: Text("add_text".tr()),
                )
              ],
            )
          );
        },
      );
    }

    return const Text("");
  }

  bool backInterceptor(bool stopDefaultButtonEvent, RouteInfo info) {
    setState(() {
      if (_selectedIndex == homePageIndex) {
        exit(0);
      }

      _selectedIndex = _lastSelectedIndex;   

      if (_selectedIndex == settingsPageIndex) {
        _lastSelectedIndex = homePageIndex;
      }       
    });
    return true;
  }

  // Builds the AppBar title for the home tab.
  // While scanning, a small animated badge shows the running device count
  // so the user gets live feedback that something is happening.
  Widget _buildHomeTitle(BuildContext context) {
    final String baseTitle = context.tr("devices_text");

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(baseTitle),
        if (_foundDeviceCount != null) ...[
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: child,
            ),
            child: Container(
              key: ValueKey<int>(_foundDeviceCount!),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_foundDeviceCount',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (firstRun) {
      firstRun = false;
      context.setLocale(Locale(Localizations.localeOf(context).languageCode));
      lastLocale = context.locale;
    }

    if (context.locale != lastLocale) {
      lastLocale = context.locale;

      if (_selectedDevice.name == "") {
        pages[devicePageIndex] = grayTextCenteredTile("no_device_selected".tr());
        pages[settingsPageIndex] = const SettingsPage();
      }

      _updateExistingIDs = true;
      _createDeviceList();
    }

    pageToRender = pages[_selectedIndex];

    final List<Widget> titleWidgets = [
      _buildHomeTitle(context),
      Text(_selectedDevice.name),
      Text(context.tr("settings_text")),
      Text(context.tr("socket_text")),
    ];

    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.unselectedWidgetColor;

    return Scaffold (
      appBar: AppBar(
        title: titleWidgets[_selectedIndex],
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18.0),
            child: getActionButton(),
          ),
        ],
      ),
      body: Center(child: FractionallySizedBox(widthFactor: 0.95, child: pageToRender)),
      bottomNavigationBar: FlashyTabBar(
        animationCurve: Curves.fastEaseInToSlowEaseOut,
        animationDuration: const Duration(milliseconds: 350),
        selectedIndex: _selectedIndex,
        iconSize: 30,
        showElevation: false,
        backgroundColor: theme.colorScheme.surface,
        onItemSelected: (index) => setState(() {
          bool currentThemeDark = false;
          if (themeNotifier.value == ThemeMode.dark) {
            currentThemeDark = true;
          }
          if (darkTheme != currentThemeDark && index == homePageIndex) {
            darkTheme = currentThemeDark;
            _updateExistingIDs = true;
            _createDeviceList();
          }

          _lastSelectedIndex = homePageIndex;
          _selectedIndex = index;
        }),
        items: [
          FlashyTabBarItem(
            icon: const Icon(Icons.list),
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            title: Text(context.tr("list_text"), style: const TextStyle(fontSize: 16)),
          ),
          FlashyTabBarItem(
            icon: const Icon(Icons.sensors),
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            title: Text(context.tr("device_text"), style: const TextStyle(fontSize: 16)),
          ),
          FlashyTabBarItem(
            icon: const Icon(Icons.settings),
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            title: Text(context.tr("settings_text"), style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}