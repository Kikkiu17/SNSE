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

  //static DevicePage? page;
  static List<Widget> pages = List.filled(maxPages, loadingTile, growable: false);
  static Device _selectedDevice = Device();
  static int _selectedIndex = 0;
  static int _lastSelectedIndex = 0;

  bool darkTheme = false;
  bool firstRun = true;
  late Locale lastLocale;

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

  void _createDeviceList() async
  {
   if (_updateExistingIDs) {
      _updateExistingIDs = false;
      _existingIPandIDs = await _getData();
    }

    setState(() {
      pages[homePageIndex] = loadingTile;
    });

    // cerca nuovi dispositivi e crea le tile
    discoverDevices(_existingIPandIDs).then((deviceList) {
      if (!mounted) return; // don't use context if the widget isn't mounted
      _existingIPandIDs = List.empty(growable: true);
      List<Widget> cardList = List.empty(growable: true);
      List<String> ipsAndIds = List.empty(growable: true);
      for (Device dev in deviceList) {
        cardList.add(_createDeviceTile(dev, context));
        cardList.add(
          const Padding(padding: EdgeInsets.only(top: 8.0))
        );
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

      _saveItem(ipsAndIds);  // save found device list

      // rebuild everything with the new device list
      setState(() {
        pages[homePageIndex] = ListView(
          children: cardList,
        );
      });
    });
  }

  ListTile _createDeviceTile(Device device, BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      tileColor: (device.name == "OFFLINE") ? Color.alphaBlend(Theme.of(context).colorScheme.surfaceContainer.withAlpha(200), const Color.fromARGB(255, 255, 148, 148)) : theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        //side: const BorderSide(width: 0.8),
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
          child: Icon(Icons.edit, color: (device.name == "OFFLINE") ? Colors.grey : Theme.of(context).colorScheme.primary)  // Theme.of(context).colorScheme.primary
        ),
        onTap: () {
          // bottone di modifica del nome del dispositivo
          // se il dispositivo è offline, mostra un popup di errore
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
        // bottone di selezione del dispositivo
        // se il dispositivo è offline, mostra un popup di errore
        if (device.name == "OFFLINE") {
          showPopupOK(context, "Impossibile effettuare l'azione", "Il dispositivo sembra essere offline. prova ad aggiornare la lista.");
        } else {
          pages[devicePageIndex] = device.setThisDevicePage();
          setState(() {
            _lastSelectedIndex = homePageIndex;
            _selectedIndex = devicePageIndex; // actually switch to the device page
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
            //_createDeviceList();
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

    return const Text("");

  }

  bool backInterceptor(bool stopDefaultButtonEvent, RouteInfo info) {
    setState(() {
      if (_selectedIndex == homePageIndex) {
        exit(0); // exit app if back button is pressed on home page
      }

      _selectedIndex = _lastSelectedIndex;   

      if (_selectedIndex == settingsPageIndex) {
        _lastSelectedIndex = homePageIndex;
      }       
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (firstRun) {
      firstRun = false;

      // set app language to device language, if available
      context.setLocale(Locale(Localizations.localeOf(context).languageCode));
      lastLocale = context.locale;
    }

    if (context.locale != lastLocale) {
      lastLocale = context.locale;

      if (_selectedDevice.name == "") {
        pages[devicePageIndex] = grayTextCenteredTile("no_device_selected".tr());
        pages[settingsPageIndex] = const SettingsPage();
      }

      // rebuild device list to update language
      _createDeviceList();
    }

    pageToRender = pages[_selectedIndex];

    // Titles for the AppBar
    final List<String> titles = [
      context.tr("devices_text"),
      _selectedDevice.name,
      context.tr("settings_text"),
      context.tr("socket_text"),
    ];

    // Get theme colors
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.unselectedWidgetColor;

    return Scaffold (
      appBar: AppBar(
        title: Text(titles[_selectedIndex]),
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
          // check if theme has been changed
          bool currentThemeDark = false;
          if (themeNotifier.value == ThemeMode.dark) {
            currentThemeDark = true;
          }
          if (darkTheme != currentThemeDark && index == homePageIndex) {
            // reload pages that need to be reloaded on theme change
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
