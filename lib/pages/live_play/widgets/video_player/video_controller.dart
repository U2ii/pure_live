import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:better_player/better_player.dart';
import 'package:bordered_text/bordered_text.dart';
import 'package:dart_vlc/dart_vlc.dart';
import 'package:flutter/services.dart';
import 'package:get/get_rx/get_rx.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:pure_live/common/index.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock/wakelock.dart';
import 'package:window_manager/window_manager.dart';

import 'video_controller_panel.dart';

class VideoController with ChangeNotifier {
  final GlobalKey playerKey;
  final RoomInfo room;
  final DanmakuStream danmakuStream;
  final String datasourceType;
  String datasource;
  final bool allowBackgroundPlay;
  final bool allowScreenKeepOn;
  final bool allowFullScreen;
  final bool fullScreenByDefault;
  final bool autoPlay;
  final videoFit = BoxFit.contain.obs;

  // Video player status
  Player? desktopController;
  BetterPlayerController? mobileController;
  VolumeController volumeController = VolumeController()..showSystemUI = false;
  ScreenBrightness brightnessController = ScreenBrightness();

  final hasError = false.obs;
  final isPlaying = false.obs;
  final isBuffering = false.obs;
  final isPipMode = false.obs;
  final isFullscreen = false.obs;
  final isWindowFullscreen = false.obs;
  bool get supportPip => Platform.isAndroid;
  bool get supportWindowFull => Platform.isWindows || Platform.isLinux;

  bool get fullscreenUI => isFullscreen.value || isWindowFullscreen.value;

  // Controller ui status
  Timer? showControllerTimer;
  final showController = true.obs;
  final showSettting = false.obs;
  final showLocked = false.obs;

  void enableController() {
    showControllerTimer?.cancel();
    showControllerTimer = Timer(const Duration(seconds: 2), () {
      showController.value = false;
    });
    showController.value = true;
  }

  // Battery level control
  final Battery _battery = Battery();
  final batteryLevel = 100.obs;
  void initBattery() {
    _battery.batteryLevel.then((value) => batteryLevel.value = value);
    _battery.onBatteryStateChanged.listen((state) async {
      batteryLevel.value = await _battery.batteryLevel;
    });
  }

  // Timed shutdown control
  final shutdownMinute = 0.obs;
  Timer? _shutdownTimer;
  void setShutdownTimer(int minutes) {
    showControllerTimer?.cancel();
    _shutdownTimer?.cancel();
    shutdownMinute.value = minutes;
    if (minutes == 0) return;
    _shutdownTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      shutdownMinute.value--;
      if (shutdownMinute.value == 0) exit(0);
    });
  }

  // Danmaku player control
  BarrageWallController barrageWallController = BarrageWallController();
  final hideDanmaku = false.obs;
  final danmakuArea = 0.5.obs;
  final danmakuSpeed = 8.0.obs;
  final danmakuFontSize = 16.0.obs;
  final danmakuFontBorder = 0.5.obs;
  final danmakuOpacity = 1.0.obs;
  final danmakuAmount = 100.obs;

  VideoController({
    required this.playerKey,
    required this.room,
    required this.danmakuStream,
    required this.datasourceType,
    required this.datasource,
    this.allowBackgroundPlay = false,
    this.allowScreenKeepOn = false,
    this.allowFullScreen = true,
    this.fullScreenByDefault = false,
    this.autoPlay = true,
    BoxFit fitMode = BoxFit.contain,
  }) {
    videoFit.value = fitMode;
    if (allowScreenKeepOn) Wakelock.enable();
    initController();
    initStateListener();
    initDanmakuListener();
    initBattery();
  }

  void initController() {
    if (Platform.isWindows || Platform.isLinux) {
      desktopController = Player(id: 100, registerTexture: true);
      setDataSource(datasource);
    } else if (Platform.isAndroid || Platform.isIOS) {
      mobileController = BetterPlayerController(
        BetterPlayerConfiguration(
          autoPlay: true,
          fit: videoFit.value,
          fullScreenByDefault: fullScreenByDefault,
          allowedScreenSleep: !allowScreenKeepOn,
          autoDetectFullscreenDeviceOrientation: true,
          autoDetectFullscreenAspectRatio: true,
          errorBuilder: (context, errorMessage) => Container(),
          routePageBuilder: (context, animation, second, controllerProvider) =>
              AnimatedBuilder(
            animation: animation,
            builder: (context, child) => MobileFullscreen(
              controller: this,
              controllerProvider: controllerProvider,
            ),
          ),
        ),
      );
      mobileController?.setControlsEnabled(false);
      setDataSource(datasource);
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
  }

  void initStateListener() {
    if (Platform.isWindows || Platform.isLinux) {
      desktopController?.playbackStream.listen(desktopStateListener);
    } else if (Platform.isAndroid || Platform.isIOS) {
      mobileController?.addEventsListener(mobileStateListener);
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
  }

  dynamic desktopStateListener(dynamic state) {
    hasError.value = desktopController?.playback.isCompleted ?? false;
    isPlaying.value = desktopController?.playback.isPlaying ?? false;
    isBuffering.value = (desktopController?.bufferingProgress ?? 1.0) < 1.0;
  }

  dynamic mobileStateListener(dynamic state) {
    hasError.value =
        mobileController?.videoPlayerController?.value.hasError ?? false;
    isPlaying.value = mobileController?.isPlaying() ?? false;
    isBuffering.value = mobileController?.isBuffering() ?? false;
    isPipMode.value =
        mobileController?.videoPlayerController?.value.isPip ?? false;
  }

  void initDanmakuListener() {
    hideDanmaku.value = PrefUtil.getBool('hideDanmaku') ?? false;
    hideDanmaku.listen((data) {
      PrefUtil.setBool('hideDanmaku', data);
    });
    danmakuArea.value = PrefUtil.getDouble('danmakuArea') ?? 0.5;
    danmakuArea.listen((data) {
      PrefUtil.setDouble('danmakuArea', data);
    });
    danmakuSpeed.value = PrefUtil.getDouble('danmakuSpeed') ?? 8;
    danmakuSpeed.listen((data) {
      PrefUtil.setDouble('danmakuSpeed', data);
    });
    danmakuFontSize.value = PrefUtil.getDouble('danmakuFontSize') ?? 16;
    danmakuFontSize.listen((data) {
      PrefUtil.setDouble('danmakuFontSize', data);
    });
    danmakuFontBorder.value = PrefUtil.getDouble('danmakuFontBorder') ?? 0.5;
    danmakuFontBorder.listen((data) {
      PrefUtil.setDouble('danmakuFontBorder', data);
    });
    danmakuOpacity.value = PrefUtil.getDouble('danmakuOpacity') ?? 1.0;
    danmakuOpacity.listen((data) {
      PrefUtil.setDouble('danmakuOpacity', data);
    });
    danmakuAmount.value = PrefUtil.getInt('danmakuAmount') ?? 100;
    barrageWallController.setMaxBarrageSize(danmakuAmount.value);
    danmakuAmount.listen((data) {
      barrageWallController.setMaxBarrageSize(data);
      PrefUtil.setInt('danmakuAmount', data);
    });
    danmakuStream.listen((info) {
      barrageWallController.send([
        Bullet(
          child: DanmakuText(
            message: info.msg,
            danmakuFontSize: danmakuFontSize,
            danmakuFontBorder: danmakuFontBorder,
          ),
        ),
      ]);
    });
  }

  @override
  void dispose() {
    super.dispose();
    if (allowScreenKeepOn) Wakelock.disable();
    _shutdownTimer?.cancel();
    brightnessController.resetScreenBrightness();
    barrageWallController.dispose();
    desktopController?.dispose();
    mobileController?.removeEventsListener(mobileStateListener);
    mobileController?.dispose();
  }

  void refresh() {
    if (Platform.isWindows || Platform.isLinux) {
      setDataSource(datasource);
    } else if (Platform.isAndroid || Platform.isIOS) {
      mobileController?.retryDataSource();
    }
  }

  void setDataSource(String url) {
    datasource = url;
    // fix datasource empty error
    if (datasource.isEmpty) {
      hasError.value = true;
      return;
    }

    if (Platform.isWindows || Platform.isLinux) {
      desktopController?.pause();
      desktopController?.open(
        Media.directShow(rawUrl: datasource),
        autoStart: true,
      );
    } else if (Platform.isAndroid || Platform.isIOS) {
      mobileController?.setupDataSource(BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        url,
        liveStream: true,
        notificationConfiguration: allowBackgroundPlay
            ? BetterPlayerNotificationConfiguration(
                showNotification: true,
                title: room.title,
                author: room.nick,
                imageUrl: room.cover,
                activityName: "MainActivity",
              )
            : null,
      ));
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
  }

  void setVideoFit(BoxFit fit) {
    videoFit.value = fit;
    if (Platform.isWindows || Platform.isLinux) {
    } else if (Platform.isAndroid || Platform.isIOS) {
      mobileController?.setOverriddenFit(videoFit.value);
      mobileController?.retryDataSource();
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
    notifyListeners();
  }

  void togglePlayPause() {
    if (Platform.isWindows || Platform.isLinux) {
      isPlaying.value ? desktopController!.pause() : desktopController!.play();
    } else if (Platform.isAndroid || Platform.isIOS) {
      isPlaying.value ? mobileController!.pause() : mobileController!.play();
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
  }

  void toggleFullScreen(BuildContext context) {
    // disable locked
    showLocked.value = false;
    // fix danmaku overlap bug
    if (!hideDanmaku.value) {
      hideDanmaku.value = true;
      Timer(const Duration(milliseconds: 500), () {
        hideDanmaku.value = false;
      });
    }
    // fix obx setstate when build
    showControllerTimer?.cancel();
    Timer(const Duration(milliseconds: 500), () {
      enableController();
    });

    if (Platform.isWindows || Platform.isLinux) {
      if (!isFullscreen.value) {
        WindowManager.instance.setFullScreen(true);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DesktopFullscreen(controller: this),
          ),
        );
      } else {
        WindowManager.instance.setFullScreen(false);
        Navigator.pop(context);
        // TODO: 重设大小，修复窗口大小BUG
        WindowManager.instance.getSize().then((value) => WindowManager.instance
            .setSize(Size(value.width + 1, value.height + 1)));
      }
      isFullscreen.toggle();
    } else if (Platform.isAndroid || Platform.isIOS) {
      mobileController?.toggleFullScreen();
      Timer(const Duration(milliseconds: 400), () {
        isFullscreen.toggle();
        // fix immersion status bar problem
        if (Platform.isAndroid) {
          SystemChrome.setEnabledSystemUIMode(!isFullscreen.value
              ? SystemUiMode.edgeToEdge
              : SystemUiMode.immersiveSticky);
        }
      });
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
  }

  void toggleWindowFullScreen(BuildContext context) {
    // disable locked
    showLocked.value = false;
    // fix danmaku overlap bug
    if (!hideDanmaku.value) {
      hideDanmaku.value = true;
      Timer(const Duration(milliseconds: 500), () {
        hideDanmaku.value = false;
      });
    }
    // fix obx setstate when build
    showControllerTimer?.cancel();
    Timer(const Duration(milliseconds: 500), () {
      enableController();
    });

    if (Platform.isWindows || Platform.isLinux) {
      if (!isWindowFullscreen.value) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DesktopFullscreen(controller: this),
          ),
        );
      } else {
        Navigator.pop(context);
      }
      isWindowFullscreen.toggle();
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
    enableController();
  }

  void enterPipMode(BuildContext context) async {
    if ((Platform.isAndroid || Platform.isIOS)) {
      if (await mobileController?.isPictureInPictureSupported() ?? false) {
        mobileController?.enablePictureInPicture(playerKey);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            margin: EdgeInsets.symmetric(horizontal: 16),
            content: Text('暂不支持画中画'),
          ),
        );
      }
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
  }

  // volumn & brightness
  Future<double> volumn() async {
    if (Platform.isWindows || Platform.isLinux) {
      return Future(() => desktopController?.general.volume ?? 1);
    } else if (Platform.isAndroid || Platform.isIOS) {
      return await volumeController.getVolume();
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
  }

  Future<double> brightness() async {
    if (Platform.isWindows || Platform.isLinux) {
      return await brightnessController.current;
    } else if (Platform.isAndroid || Platform.isIOS) {
      return await brightnessController.current;
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
  }

  void setVolumn(double value) async {
    if (Platform.isWindows || Platform.isLinux) {
      desktopController?.setVolume(value);
    } else if (Platform.isAndroid || Platform.isIOS) {
      volumeController.setVolume(value);
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
  }

  void setBrightness(double value) async {
    if (Platform.isWindows || Platform.isLinux) {
      brightnessController.setScreenBrightness(value);
    } else if (Platform.isAndroid || Platform.isIOS) {
      brightnessController.setScreenBrightness(value);
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
  }
}

class MobileFullscreen extends StatelessWidget {
  const MobileFullscreen({
    Key? key,
    required this.controller,
    required this.controllerProvider,
  }) : super(key: key);

  final VideoController controller;
  final BetterPlayerControllerProvider controllerProvider;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: WillPopScope(
        onWillPop: () {
          controller.toggleFullScreen(context);
          return Future(() => true);
        },
        child: Container(
          alignment: Alignment.center,
          color: Colors.black,
          child: Stack(
            alignment: Alignment.center,
            children: [
              controllerProvider,
              VideoControllerPanel(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}

class DesktopFullscreen extends StatelessWidget {
  const DesktopFullscreen({Key? key, required this.controller})
      : super(key: key);

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Container(
        alignment: Alignment.center,
        color: Colors.black,
        child: Hero(
          tag: controller.datasource,
          child: Stack(children: [
            Positioned.fill(
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                child: Obx(() => Video(
                      player: controller.desktopController,
                      fit: controller.videoFit.value,
                    )),
              ),
            ),
            VideoControllerPanel(controller: controller),
          ]),
        ),
      ),
    );
  }
}

class DanmakuText extends StatelessWidget {
  const DanmakuText({
    Key? key,
    required this.message,
    required this.danmakuFontSize,
    required this.danmakuFontBorder,
  }) : super(key: key);

  final String message;
  final RxDouble danmakuFontSize;
  final RxDouble danmakuFontBorder;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => BorderedText(
        strokeWidth: danmakuFontBorder.value,
        child: Text(
          message,
          maxLines: 1,
          style: TextStyle(
            fontSize: danmakuFontSize.value,
            fontWeight: FontWeight.w400,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
