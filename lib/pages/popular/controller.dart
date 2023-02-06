import 'dart:math';

import 'package:pure_live/common/index.dart';

class PlatformRooms {
  String tag = 'bilibili';
  String name = '哔哩';
  int page = 0;
  List<RoomInfo> rooms = [];

  PlatformRooms({
    this.tag = '',
    this.name = '',
    this.page = 0,
  });
}

class PopularProvider with ChangeNotifier {
  final BuildContext context;

  PopularProvider(this.context) {
    final platform =
        Provider.of<SettingsProvider>(context, listen: false).preferPlatform;
    preferIndex =
        max(0, platformRooms.keys.toList().indexWhere((e) => e == platform));
    initRefresh();
  }

  late final int preferIndex;
  Map<String, PlatformRooms> platformRooms = {
    'bilibili': PlatformRooms(tag: 'bilibili', name: '哔哩'),
    'douyu': PlatformRooms(tag: 'douyu', name: '斗鱼'),
    'huya': PlatformRooms(tag: 'huya', name: '虎牙'),
  };

  void initRefresh() async {
    for (final platform in platformRooms.keys) {
      platformRooms[platform]?.rooms =
          await LiveApi.getRecommend(platform, page: 0);
    }
    notifyListeners();
  }

  Future<bool> onRefresh(String platform) async {
    platformRooms[platform]?.page = 0;
    platformRooms[platform]?.rooms = await LiveApi.getRecommend(platform,
        page: platformRooms[platform]?.page ?? 0);
    notifyListeners();
    return platformRooms[platform]?.rooms.isNotEmpty ?? false;
  }

  Future<bool> onLoading(String platform) async {
    platformRooms[platform]?.page++;
    final items = await LiveApi.getRecommend(platform,
        page: platformRooms[platform]?.page ?? 0);
    if (items.isNotEmpty) {
      for (var item in items) {
        if (platformRooms[platform]?.rooms.contains(item) ?? true) continue;
        platformRooms[platform]?.rooms.add(item);
      }
    }
    notifyListeners();
    return items.isNotEmpty;
  }
}
