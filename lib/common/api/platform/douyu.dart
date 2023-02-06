import 'dart:convert';
import 'dart:developer';
import 'package:flutter_js/flutter_js.dart';
import 'package:pure_live/common/index.dart';
import 'package:http/http.dart' as http;

class DouyuApi {
  static Future<dynamic> _getJson(String url) async {
    var resp = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 12_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148'
      },
    );
    return await jsonDecode(resp.body);
  }

  static Future<Map?> getHomeJs(String rid) async {
    String roomUrl = "https://www.douyu.com/" + rid;
    String response = (await http.get(Uri.parse(roomUrl))).body;

    String realRid = response.substring(
        response.indexOf("\$ROOM.room_id =") + ("\$ROOM.room_id =").length);
    realRid = realRid.substring(0, realRid.indexOf(";")).trim();
    if (rid != realRid) {
      roomUrl = "https://www.douyu.com/" + realRid;
      response = (await http.get(Uri.parse(roomUrl))).body;
    }

    final pattern = RegExp(
        "(vdwdae325w_64we[\\s\\S]*function ub98484234[\\s\\S]*?)function");
    final matcher = pattern.allMatches(response);
    if (matcher.isEmpty) return null;
    String result = matcher.toList()[0][0]!;
    String homejs = result.replaceAll("eval.*?;", "strc;");
    return {
      "homejs": homejs,
      "real_rid": realRid,
    };
  }

  static final jsEngine = getJavascriptRuntime();
  static bool loadedJs = false;
  static Future<String> getSign(String rid, String tt, String ub9) async {
    // load crypto-js package
    if (!loadedJs) {
      final cryptojs = (await http.get(Uri.parse(
              'https://cdnjs.cloudflare.com/ajax/libs/crypto-js/3.1.9-1/crypto-js.js')))
          .body;
      jsEngine.evaluate(cryptojs);
      loadedJs = true;
    }

    ub9 = ub9.substring(0, ub9.lastIndexOf('function'));
    jsEngine.evaluate(ub9);
    final params = jsEngine
        .evaluate(
            'ub98484234(\'$rid\', \'10000000000000000000000000001501\', \'$tt\')')
        .toString();
    return params;
  }

  static Map<String, String> handleParams(String params) {
    Map<String, String> paramsMap = {};
    for (String param in params.split("&")) {
      final arr1 = param.split("=");
      final key = arr1[0].trim();
      final value = arr1[1].trim();
      paramsMap[key] = value;
    }
    return paramsMap;
  }

  static Future<Map<String, Map<String, String>>> getRoomStreamLink(
      RoomInfo room) async {
    Map<String, Map<String, String>> links = {};

    final rid = room.roomId;
    try {
      // 获取房间主页JS
      final result = await getHomeJs(rid);
      final realRid = result!["real_rid"];
      final homejs = result["homejs"];
      // 执行JS获取签名信息
      final tt = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      final params = (await getSign(rid, tt, homejs)) + "&cdn=ws-h5&rate=0";

      // 发送请求获取直播流信息
      String requestUrl =
          "https://www.douyu.com/lapi/live/getH5Play/" + realRid;
      final response1 = await http.post(
        Uri.parse(requestUrl),
        body: handleParams(params),
      );
      final response = jsonDecode(response1.body);
      final data = response["data"];

      // 获取真实直播Key
      final url = data["rtmp_live"];
      final key = url.substring(0, url.indexOf(".")).split("_")[0];

      // 获取支持分辨率
      Map<String, String> resolutions = {};
      data["multirates"].forEach((e) {
        resolutions[e['name']] = e['rate'] == 0 ? '' : '_${e['bit']}';
      });

      List<String> cdns = ['akm', 'hw', 'ws'];
      for (String res in resolutions.keys) {
        String v = resolutions[res]!;
        links[res] = {};
        for (String cdn in cdns) {
          links[res]![cdn] =
              'https://$cdn-tct.douyucdn.cn/live/$key$v.flv?uuid=';
        }
      }
    } catch (e) {
      log(e.toString(), name: 'DouyuApi.getRoomStreamLink');
      return links;
    }
    return links;
  }

  static Future<RoomInfo> getRoomInfo(RoomInfo room) async {
    try {
      dynamic body = await _getJson(
          'https://open.douyucdn.cn/api/RoomApi/room/${room.roomId}');
      if (body['error'] == 0) {
        Map data = body['data'];
        room.nick = data['owner_name'] ?? '';
        room.title = data['room_name'] ?? '';
        room.avatar = data['avatar'] ?? '';
        room.cover = data['room_thumb'] ?? '';
        room.area = data['cate_name'] ?? '';
        room.watching = data['hn']?.toString() ?? '';
        room.liveStatus =
            (data.containsKey('room_status') && data['room_status'] == '1')
                ? LiveStatus.live
                : LiveStatus.offline;
      }
    } catch (e) {
      log(e.toString(), name: 'DouyuApi.getRoomInfo');
      return room;
    }
    return room;
  }

  static Future<List<RoomInfo>> getRecommend(int page, int size) async {
    List<RoomInfo> list = [];

    try {
      int start =
          size * (page - 1) ~/ 8 + ((size * (page - 1) % 8 == 0) ? 0 : 1);
      start = (start == 0) ? 1 : start;
      int end = size * (page) ~/ 8 + ((size * (page) % 8 == 0) ? 0 : 1);

      for (int i = start; i <= end; i++) {
        String url = "https://m.douyu.com/api/room/list?page=$i&type=";
        dynamic response = await _getJson(url);
        dynamic result = response["data"];
        if (response["code"] == 0) {
          List<dynamic> roomInfoList = result["list"];
          for (var roomInfo in roomInfoList) {
            RoomInfo room = RoomInfo(roomInfo["rid"].toString());
            room.platform = 'douyu';
            room.nick = roomInfo["nickname"] ?? '';
            room.title = roomInfo["roomName"] ?? '';
            room.cover = roomInfo["roomSrc"] ?? '';
            room.avatar = roomInfo["avatar"] ?? '';
            room.watching = roomInfo["hn"] ?? '';
            room.liveStatus =
                (roomInfo.containsKey("isLive") && roomInfo["isLive"] == 1)
                    ? LiveStatus.live
                    : LiveStatus.offline;
            list.add(room);
          }
        }
      }
    } catch (e) {
      log(e.toString(), name: 'DouyuApi.getRecommend');
      return list;
    }
    return list;
  }

  static Future<List<List<AreaInfo>>> getAreaList() async {
    List<List<AreaInfo>> areaList = [];
    String url = "https://m.douyu.com/api/cate/list";

    try {
      dynamic response = await _getJson(url);
      Map<String, String> cate1Map = {};
      Map<String, List<AreaInfo>> cate2Map = {};
      if (response["code"] == 0) {
        List<dynamic> cate1InfoList = response["data"]["cate1Info"];
        for (var element in cate1InfoList) {
          String cate1Name = element["cate1Name"];
          String cate1Id = element["cate1Id"].toString();
          cate1Map[cate1Id] = cate1Name;
          cate2Map[cate1Id] = [];
        }

        List<dynamic> areaInfoList = response["data"]["cate2Info"];
        for (var areaInfo in areaInfoList) {
          final typeId = areaInfo["cate1Id"].toString();
          if ("21" == typeId || !cate1Map.containsKey(typeId)) {
            continue;
          }

          AreaInfo area = AreaInfo();
          area.areaType = typeId;
          area.typeName = cate1Map[typeId]!;

          area.platform = "douyu";
          area.areaId = areaInfo["cate2Id"]?.toString() ?? '';
          area.areaName = areaInfo["cate2Name"] ?? '';
          area.areaPic = areaInfo["pic"] ?? '';
          area.shortName = areaInfo["shortName"] ?? '';

          cate2Map[typeId]?.add(area);
        }
      }

      cate2Map.forEach((key, value) {
        if (value.isNotEmpty) areaList.add(value);
      });
    } catch (e) {
      log(e.toString(), name: 'DouyuApi.getAreaList');
      return areaList;
    }
    return areaList;
  }

  static Future<List<RoomInfo>> getAreaRooms(
      AreaInfo area, int page, int size) async {
    List<RoomInfo> list = [];

    try {
      int start = size * (page - 1) ~/ 8 + 1;
      start = (start == 0) ? 1 : start;
      int end = size * page ~/ 8 + ((size * (page) % 8 == 0) ? 0 : 1);

      for (int i = start; i <= end; i++) {
        String url =
            "https://m.douyu.com/api/room/list?page=$i&type=${area.shortName}";
        dynamic response = await _getJson(url);
        dynamic result = response["data"];
        if (response["code"] == 0) {
          List<dynamic> roomInfoList = result["list"];
          for (var roomInfo in roomInfoList) {
            RoomInfo room = RoomInfo(roomInfo["rid"].toString());
            room.platform = 'douyu';
            room.nick = roomInfo["nickname"] ?? '';
            room.title = roomInfo["roomName"] ?? '';
            room.cover = roomInfo["roomSrc"] ?? '';
            room.avatar = roomInfo["avatar"] ?? '';
            room.area = area.areaName;
            room.watching = roomInfo["hn"] ?? '';
            room.liveStatus =
                (roomInfo.containsKey("isLive") && roomInfo["isLive"] == 1)
                    ? LiveStatus.live
                    : LiveStatus.offline;
            list.add(room);
          }
        }
      }
    } catch (e) {
      log(e.toString(), name: 'DouyuApi.getAreaRooms');
      return list;
    }
    return list;
  }

  static Future<List<RoomInfo>> search(String keyWords) async {
    List<RoomInfo> list = [];
    String url = "https://m.douyu.com/api/search/anchor";

    try {
      Map<String, String> headers = {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 12_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
        'Content-Type': 'application/json',
      };
      Map data = {
        "sk": keyWords,
        "offset": 0,
        "limit": 20,
      };
      dynamic resp = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(data),
      );
      dynamic response = jsonDecode(resp.body);
      if (response["error"] == 0) {
        List<dynamic> ownerList = response["data"]["list"];
        for (var ownerInfo in ownerList) {
          RoomInfo owner = RoomInfo(ownerInfo['roomId'].toString());
          owner.platform = "douyu";
          owner.userId = ownerInfo['ownerUID']?.toString() ?? '';
          owner.nick = ownerInfo["nickname"] ?? '';
          owner.title = ownerInfo["roomName"] ?? '';
          owner.cover = ownerInfo["roomSrc"] ?? '';
          owner.avatar = ownerInfo["avatar"] ?? '';
          owner.area = ownerInfo["cateName"] ?? '';
          owner.watching = ownerInfo["hn"] ?? '';
          owner.liveStatus =
              (ownerInfo.containsKey("isLive") && ownerInfo["isLive"] == 1)
                  ? LiveStatus.live
                  : LiveStatus.offline;
          list.add(owner);
        }
      }
    } catch (e) {
      log(e.toString(), name: 'DouyuApi.search');
      return list;
    }
    return list;
  }
}
