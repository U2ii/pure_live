import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:pure_live/pages/index.dart';
import 'package:pure_live/common/index.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

class PopularPage extends StatefulWidget {
  const PopularPage({Key? key}) : super(key: key);

  @override
  State<PopularPage> createState() => _PopularPageState();
}

class _PopularPageState extends State<PopularPage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final provider = Provider.of<PopularProvider>(context);
  late final tabController = TabController(
    initialIndex: provider.preferIndex,
    length: provider.platformRooms.length,
    vsync: this,
  );

  bool get showAction => MediaQuery.of(context).size.width < 640;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        scrolledUnderElevation: 0,
        leading: showAction ? const MenuButton() : null,
        actions: showAction ? [const SearchButton()] : null,
        title: TabBar(
          controller: tabController,
          isScrollable: true,
          labelColor: Theme.of(context).colorScheme.onBackground,
          labelStyle:
              const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          unselectedLabelColor: Theme.of(context).disabledColor,
          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          indicatorSize: TabBarIndicatorSize.label,
          indicatorColor: Theme.of(context).colorScheme.primary,
          tabs: provider.platformRooms.values
              .map((value) => Tab(text: value.name))
              .toList(),
        ),
      ),
      body: TabBarView(
        controller: tabController,
        children: provider.platformRooms.keys
            .map((e) => _RoomGridView(platform: e))
            .toList(),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _RoomGridView extends StatefulWidget {
  final String platform;

  const _RoomGridView({
    Key? key,
    required this.platform,
  }) : super(key: key);

  @override
  _RoomGridViewState createState() => _RoomGridViewState();
}

class _RoomGridViewState extends State<_RoomGridView>
    with AutomaticKeepAliveClientMixin {
  late final provider = Provider.of<PopularProvider>(context);
  final refreshController = RefreshController(initialRefresh: false);
  final scrollController = ScrollController();

  int get crossAxisCount {
    double screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = screenWidth > 1280
        ? 5
        : (screenWidth > 960 ? 4 : (screenWidth > 640 ? 3 : 2));
    return crossAxisCount;
  }

  void _onRefresh() {
    provider.onRefresh(widget.platform).then(
          (value) => value
              ? refreshController.refreshCompleted()
              : refreshController.refreshFailed(),
        );
  }

  bool loading = false;
  void _onLoading() {
    if (loading) return;

    loading = true;
    provider.onLoading(widget.platform).then((value) {
      loading = false;
      value ? refreshController.loadComplete() : refreshController.loadFailed();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final rooms = provider.platformRooms[widget.platform]?.rooms ?? [];

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent &&
            event.scrollDelta.direction >= 0 &&
            event.scrollDelta.direction <= pi) {
          final pos = scrollController.position;
          if (pos.maxScrollExtent - pos.pixels < 40) {
            _onLoading();
          }
        }
      },
      child: SmartRefresher(
        enablePullDown: true,
        enablePullUp: true,
        header: const WaterDropHeader(),
        footer: const OnLoadingFooter(),
        controller: refreshController,
        onRefresh: _onRefresh,
        onLoading: _onLoading,
        child: rooms.isNotEmpty
            ? MasonryGridView.count(
                padding: const EdgeInsets.all(5),
                controller: scrollController,
                crossAxisCount: crossAxisCount,
                itemCount: rooms.length,
                itemBuilder: (context, index) => RoomCard(
                  room: rooms[index],
                  dense: true,
                ),
              )
            : EmptyView(
                icon: Icons.live_tv_rounded,
                title: S.of(context).empty_live_title,
                subtitle: S.of(context).empty_live_subtitle,
              ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
