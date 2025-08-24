import 'dart:io' show Socket;

import '../discovery.dart';
import 'package:flutter/material.dart';
import 'device.dart';
//import 'package:flashy_tab_bar2/flashy_tab_bar2.dart';
import '../flashytabbar/flashy_tab_bar2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings.dart';
import '../main.dart';

import '../tiles/tiles.dart';

const int maxPages = 3;
const int homePageIndex = 0;
const int devicePageIndex = 1;
const int settingsPageIndex = 2;

class HomePage extends StatefulWidget
{
  final SharedPreferences storage;
  const HomePage({super.key, required this.storage});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Socket? socket;
  static Widget pageToRender = const Text('Caricamento...');

  static bool _updateExistingIDs = true;

  static List<String> _existingIPandIDs = List.empty(growable: true);

  //static DevicePage? page;
  static List<Widget> pages = List.filled(maxPages, loadingTile, growable: false);
  static Device _selectedDevice = Device();
  static int _selectedIndex = 0;

  bool darkTheme = false;

@override
  void initState() {
    pages[devicePageIndex] = grayTextCenteredTile("Nessun dispositivo selezionato");
    pages[settingsPageIndex] = const SettingsPage();
    _createDeviceList();
    super.initState();
  }

@override
  void dispose() {
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
        ipsAndIds.add("${dev.ip};${dev.id}");
      }


      if (cardList.isNotEmpty) {
        cardList.add(
          const Padding(padding: EdgeInsets.only(top: 8.0))
        );

        // list update button
        cardList.add(
        ListTile(
            title: ElevatedButton(
              child: const Text("Aggiorna"),
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
        cardList.add(grayTextCenteredTile("Nessun dispositivo trovato"));
      }

      // discovery button
      cardList.add(
      ListTile(
          title: ElevatedButton(
            child: const Text("Trova nuovi dispositivi"),
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
                //_updateExistingIDs = true;
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
            _selectedIndex = devicePageIndex; // actually switch to the device page
            _selectedDevice = device;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    pageToRender = pages[_selectedIndex];

    // Titles for the AppBar
    final List<String> titles = [
      "Dispositivi",
      _selectedDevice.name,
      "Impostazioni",
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
            child: (_selectedIndex == homePageIndex) ? const Text("") :
            IconButton(
              icon: const Icon(Icons.notifications),
              onPressed: () {
                forceShowNotification = true;
              },
            )
          ),
        ],
      ),
      body: Center(child: FractionallySizedBox(widthFactor: 0.95, child: pageToRender)),
      bottomNavigationBar: FlashyTabBar(
        animationCurve: Curves.fastEaseInToSlowEaseOut,
        animationDuration: const Duration(milliseconds: 350),
        selectedIndex: _selectedIndex,
        iconSize: 35,
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

          _selectedIndex = index;
        }),
        items: [
          FlashyTabBarItem(
            icon: const Icon(Icons.list),
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            title: const Text('Lista', style: TextStyle(fontSize: 16)),
          ),
          FlashyTabBarItem(
            icon: const Icon(Icons.sensors),
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            title: const Text('Dispositivo', style: TextStyle(fontSize: 16)),
          ),
          FlashyTabBarItem(
            icon: const Icon(Icons.settings),
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            title: const Text('Impostazioni', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
