import 'dart:convert';
import 'package:http/http.dart' as http;

class VersionUtil {
  static const String version = '1.0.7';
  static const String projectUrl = 'https://github.com/Jackiu1997/pure_live';
  static const String releaseUrl =
      'https://api.github.com/repos/Jackiu1997/pure_live/releases';
  static const String issuesUrl =
      'https://github.com/Jackiu1997/pure_live/issues';
  static const String kanbanUrl =
      'https://jackiu-notes.notion.site/50bc0d3d377445eea029c6e3d4195671?v=663125e639b047cea5e69d8264926b8b';

  static const String githubUrl = 'https://github.com/Jackiu1997';
  static const String email = 'jackiu1997@gmail.com';
  static const String emailUrl =
      'mailto:jackiu1997@gmail.com?subject=PureLive Feedback';
  static const String telegramGroup = 't.me/pure_live_channel';
  static const String telegramGroupUrl = 'https://t.me/pure_live_channel';

  static String latestVersion = version;
  static String latestUpdateLog = '';

  static Future<void> checkUpdate() async {
    try {
      var response = await http.get(Uri.parse(releaseUrl));
      var latest = (await jsonDecode(response.body))[0];
      latestVersion = latest['tag_name'].replaceAll('v', '');
      latestUpdateLog = latest['body'];
    } catch (e) {
      latestUpdateLog = e.toString();
    }
  }

  static bool hasNewVersion() {
    List latestVersions = latestVersion.split('-')[0].split('.');
    List versions = version.split('-')[0].split('.');
    for (int i = 0; i < latestVersions.length; i++) {
      if (int.parse(latestVersions[i]) > int.parse(versions[i])) {
        return true;
      } else if (int.parse(latestVersions[i]) < int.parse(versions[i])) {
        return false;
      }
    }
    return false;
  }
}
