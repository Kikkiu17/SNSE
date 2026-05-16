import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateChecker {
  static const String _githubApiUrl =
      "https://api.github.com/repos/Kikkiu17/SNSE/releases/latest";

  static final ValueNotifier<String?> latestVersionNotifier =
      ValueNotifier(null);
  static Map<String, dynamic>? _lastReleaseData;

  static Future<void> checkForUpdates(BuildContext context,
      {bool forceShow = false}) async {
    try {
      final response = await http.get(Uri.parse(_githubApiUrl));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _lastReleaseData = data;
        final String latestVersionTag =
            data['tag_name']; // e.g. "v1.6.3" or "1.6.3"
        String latestVersion = latestVersionTag.replaceAll('v', '').trim();

        final packageInfo = await PackageInfo.fromPlatform();
        String currentVersion = packageInfo.version;

        if (_isNewerVersion(currentVersion, latestVersion)) {
          latestVersionNotifier.value = latestVersion;

          final storage = await SharedPreferences.getInstance();
          String? ignoredVersion = storage.getString("ignored_update_version");

          if (forceShow || latestVersion != ignoredVersion) {
            if (context.mounted) {
              _showUpdateDialog(context, latestVersion);
            }
          }
        } else {
          latestVersionNotifier.value = null;
        }
      }
    } catch (e) {
      debugPrint("Failed to check for updates: $e");
    }
  }

  static bool _isNewerVersion(String current, String latest) {
    List<int> currentParts =
        current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> latestParts =
        latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      int c = currentParts.length > i ? currentParts[i] : 0;
      int l = latestParts.length > i ? latestParts[i] : 0;
      if (l > c) return true;
      if (c > l) return false;
    }
    return false;
  }

  static String _getDownloadUrl(Map<String, dynamic> data) {
    final List<dynamic> assets = data['assets'] ?? [];
    if (assets.isEmpty) return data['html_url'];

    String extension = "";
    if (Platform.isAndroid) {
      extension = ".apk";
    } else if (Platform.isLinux) {
      extension = ".AppImage";
    } else if (Platform.isWindows) {
      extension = ".exe";
    }

    if (extension.isNotEmpty) {
      for (var asset in assets) {
        String name = asset['name'] ?? "";
        if (name.toLowerCase().endsWith(extension.toLowerCase())) {
          return asset['browser_download_url'];
        }
      }
    }

    return data['html_url'];
  }

  static void _showUpdateDialog(BuildContext context, String newVersion) {
    bool dontRemind = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text("update_available_title".tr()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("update_available_desc".tr(args: [newVersion])),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: dontRemind,
                      onChanged: (value) {
                        setState(() {
                          dontRemind = value ?? false;
                        });
                      },
                    ),
                    Expanded(
                      child: Text(
                        "dont_remind_text".tr(),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("cancel_text".tr()),
              ),
              TextButton(
                onPressed: () async {
                  if (dontRemind) {
                    final storage = await SharedPreferences.getInstance();
                    await storage.setString(
                        "ignored_update_version", newVersion);
                  }
                  if (context.mounted) Navigator.pop(context);

                  String downloadUrl = _lastReleaseData != null
                      ? _getDownloadUrl(_lastReleaseData!)
                      : "https://github.com/Kikkiu17/SNSE/releases/latest";

                  final Uri url = Uri.parse(downloadUrl);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                child: Text("download_text".tr()),
              ),
            ],
          );
        });
      },
    );
  }
}
