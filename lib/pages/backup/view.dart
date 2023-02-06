import 'dart:io';

import 'package:date_format/date_format.dart' hide S;
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pure_live/common/index.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({Key? key}) : super(key: key);

  @override
  _BackupPageState createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  late final settings = Provider.of<SettingsProvider>(context, listen: false);
  late String backupDirectory = settings.backupDirectory;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          SectionTitle(title: S.of(context).backup_recover),
          ListTile(
            title: Text(S.of(context).create_backup),
            subtitle: Text(S.of(context).create_backup_subtitle),
            onTap: () => createBackup(),
          ),
          ListTile(
            title: Text(S.of(context).recover_backup),
            subtitle: Text(S.of(context).recover_backup_subtitle),
            onTap: () => recoverBackup(),
          ),
          SectionTitle(title: S.of(context).auto_backup),
          ListTile(
            title: Text(S.of(context).backup_directory),
            subtitle: Text(backupDirectory),
            onTap: () => selectBackupDirectory(),
          ),
        ],
      ),
    );
  }

  Future<bool> requestStoragePermission() async {
    if (await Permission.manageExternalStorage.isDenied) {
      final status = Permission.manageExternalStorage.request();
      return status.isGranted;
    }
    return true;
  }

  void createBackup() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final granted = await requestStoragePermission();
      if (!granted) {
        SnackBarUtil.error(context, '请先授予读写文件权限');
        return;
      }
    }

    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null) return;

    final dateStr = formatDate(
      DateTime.now(),
      [yyyy, '-', mm, '-', dd, 'T', HH, '_', nn, '_', ss],
    );
    final file = File('$selectedDirectory/purelive_$dateStr.txt');
    if (settings.backup(file)) {
      SnackBarUtil.success(context, S.of(context).create_backup_success);
      // 首次同步备份目录
      if (settings.backupDirectory.isEmpty) {
        settings.backupDirectory = selectedDirectory;
        setState(() => backupDirectory = selectedDirectory);
      }
    } else {
      SnackBarUtil.error(context, S.of(context).create_backup_failed);
    }
  }

  void recoverBackup() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: S.of(context).select_recover_file,
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    if (settings.recover(file)) {
      SnackBarUtil.success(context, S.of(context).recover_backup_success);
    } else {
      SnackBarUtil.error(context, S.of(context).recover_backup_failed);
    }
  }

  void selectBackupDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null) return;

    settings.backupDirectory = selectedDirectory;
    setState(() => backupDirectory = selectedDirectory);
  }
}
