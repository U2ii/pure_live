import 'package:cached_network_image/cached_network_image.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/pages/index.dart';
import 'package:wakelock/wakelock.dart';

import 'widgets/index.dart';

class LivePlayPage extends StatefulWidget {
  final String preferResolution;

  const LivePlayPage({
    Key? key,
    required this.room,
    required this.preferResolution,
  }) : super(key: key);

  final RoomInfo room;

  @override
  State<LivePlayPage> createState() => _LivePlayPageState();
}

class _LivePlayPageState extends State<LivePlayPage> {
  late FavoriteProvider favorite;
  late SettingsProvider settings;
  late DanmakuStream danmakuStream;

  Map<String, Map<String, String>> _streamList = {};
  String _selectedResolution = '';
  String _datasource = '';

  // 控制唯一子组件
  VideoController? controller;
  final _playerKey = GlobalKey();
  final _danmakuViewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    danmakuStream = DanmakuStream(room: widget.room);
    LiveApi.getRoomStreamLink(widget.room).then((value) {
      _streamList = value;
      setPreferResolution();
      controller = VideoController(
        playerKey: _playerKey,
        room: widget.room,
        danmakuStream: danmakuStream,
        datasourceType: 'network',
        datasource: _datasource,
        allowBackgroundPlay: settings.enableBackgroundPlay,
        allowScreenKeepOn: settings.enableScreenKeepOn,
        fullScreenByDefault: settings.enableFullScreenDefault,
        autoPlay: true,
      );
      setState(() {});
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    danmakuStream.dispose();
    super.dispose();
  }

  void setPreferResolution() {
    if (_streamList.isEmpty || _streamList.values.first.isEmpty) return;

    for (var key in _streamList.keys) {
      if (widget.preferResolution.contains(key)) {
        _selectedResolution = key;
        _datasource = _streamList[key]!.values.first;
        return;
      }
    }
    // 蓝光8M/4M选择缺陷
    if (widget.preferResolution.contains('蓝光')) {
      for (var key in _streamList.keys) {
        if (key.contains('蓝光')) {
          _selectedResolution = key;
          _datasource = _streamList[key]!.values.first;
          return;
        }
      }
    }
    // 偏好选择失败，选择最低清晰度
    _selectedResolution = _streamList.keys.last;
    _datasource = _streamList.values.last.values.first;
  }

  void setResolution(String name, String url) {
    setState(() => _selectedResolution = name);
    _datasource = url;
    controller?.setDataSource(_datasource);
  }

  @override
  Widget build(BuildContext context) {
    favorite = Provider.of<FavoriteProvider>(context);
    settings = Provider.of<SettingsProvider>(context);
    if (settings.enableScreenKeepOn) {
      Wakelock.toggle(enable: settings.enableScreenKeepOn);
    }

    double screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          CircleAvatar(
            foregroundImage: (widget.room.avatar == '')
                ? null
                : NetworkImage(widget.room.avatar),
            radius: 13,
            backgroundColor: Theme.of(context).disabledColor,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.room.nick,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              Text(
                '${widget.room.platform.toUpperCase()} / ${widget.room.area}',
                style:
                    Theme.of(context).textTheme.caption?.copyWith(fontSize: 8),
              ),
            ],
          ),
        ]),
        actions: [
          IconButton(
            tooltip: S.of(context).dlan_button_info,
            onPressed: showDlnaCastDialog,
            icon: const Icon(CustomIcons.cast),
          ),
        ],
      ),
      body: SafeArea(
        child: screenWidth > 640
            ? Row(children: <Widget>[
                Flexible(
                  flex: 5,
                  child: _buildVideoPlayer(width: screenWidth / 8.0 * 5.0),
                ),
                Flexible(
                  flex: 3,
                  child: Column(children: [
                    _buildResolutions(),
                    const Divider(height: 1),
                    Expanded(
                      child: DanmakuListView(
                        key: _danmakuViewKey,
                        room: widget.room,
                        danmakuStream: danmakuStream,
                      ),
                    ),
                  ]),
                ),
              ])
            : Column(
                children: <Widget>[
                  _buildVideoPlayer(width: screenWidth),
                  _buildResolutions(),
                  const Divider(height: 1),
                  Expanded(
                    child: DanmakuListView(
                      key: _danmakuViewKey,
                      room: widget.room,
                      danmakuStream: danmakuStream,
                    ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FavoriteFloatingButton(room: widget.room),
    );
  }

  Widget _buildVideoPlayer({required double width}) {
    return Hero(
      tag: widget.room.roomId,
      child: AspectRatio(
        aspectRatio: 19.5 / 9,
        child: Container(
          color: Colors.black,
          child: controller == null
              ? Card(
                  elevation: 0,
                  margin: const EdgeInsets.all(0),
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero),
                  clipBehavior: Clip.antiAlias,
                  color: Theme.of(context).focusColor,
                  child: CachedNetworkImage(
                    imageUrl: widget.room.cover,
                    fit: BoxFit.fill,
                    errorWidget: (context, error, stackTrace) => const Center(
                      child: Icon(Icons.live_tv_rounded, size: 48),
                    ),
                  ),
                )
              : VideoPlayer(
                  key: _playerKey,
                  controller: controller!,
                  width: width,
                  height: width / 19.5 * 9.0,
                ),
        ),
      ),
    );
  }

  Widget _buildResolutions() {
    // room watching or followers
    Widget info = Container();
    if (widget.room.followers.isNotEmpty) {
      info = Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.person_rounded, size: 14),
        const SizedBox(width: 4),
        Text(
          readableCount(widget.room.followers),
          style: Theme.of(context).textTheme.caption,
        ),
      ]);
    } else if (widget.room.watching.isNotEmpty) {
      info = Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.whatshot_rounded, size: 14),
        const SizedBox(width: 4),
        Text(
          readableCount(widget.room.watching),
          style: Theme.of(context).textTheme.caption,
        ),
      ]);
    }

    // resolution popmenu buttons
    final resButtons = _streamList.keys
        .map<Widget>((res) => PopupMenuButton(
              tooltip: res,
              color: Theme.of(context).colorScheme.surfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              offset: const Offset(0.0, 5.0),
              position: PopupMenuPosition.under,
              icon: Text(
                res,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: res == _selectedResolution
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
              ),
              onSelected: (String url) => setResolution(res, url),
              itemBuilder: (context) => _streamList[res]!
                  .keys
                  .map((cdn) => PopupMenuItem<String>(
                        child: Text(
                          cdn,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: _streamList[res]![cdn] ==
                                            controller?.datasource
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                        ),
                        value: _streamList[res]![cdn],
                      ))
                  .toList(),
            ))
        .toList();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Padding(padding: const EdgeInsets.all(8), child: info),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: resButtons,
      ),
    );
  }

  void showDlnaCastDialog() {
    showDialog(
      context: context,
      builder: (context) => LiveDlnaPage(datasource: _datasource),
    );
  }
}

class FavoriteFloatingButton extends StatelessWidget {
  const FavoriteFloatingButton({
    Key? key,
    required this.room,
  }) : super(key: key);

  final RoomInfo room;

  @override
  Widget build(BuildContext context) {
    final favorite = Provider.of<FavoriteProvider>(context);
    return favorite.isFavorite(room)
        ? FloatingActionButton(
            elevation: 2,
            backgroundColor: Theme.of(context).cardColor,
            tooltip: S.of(context).unfollow,
            onPressed: () => favorite.removeRoom(room),
            child: CircleAvatar(
              foregroundImage:
                  (room.avatar == '') ? null : NetworkImage(room.avatar),
              radius: 18,
              backgroundColor: Theme.of(context).disabledColor,
            ),
          )
        : FloatingActionButton.extended(
            elevation: 2,
            backgroundColor: Theme.of(context).cardColor,
            onPressed: () => favorite.addRoom(room),
            icon: CircleAvatar(
              foregroundImage:
                  (room.avatar == '') ? null : NetworkImage(room.avatar),
              radius: 18,
              backgroundColor: Theme.of(context).disabledColor,
            ),
            label: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.of(context).follow,
                  style: Theme.of(context).textTheme.caption,
                ),
                Text(
                  room.nick,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
  }
}
