/// 프로젝트 실행 스크립트를 앱에서 띄우고 내린다.
///
/// 앱이 띄운 것만 앱이 내린다. 사용자가 터미널에서 직접 띄운 것을 앱이 종료할
/// 때 같이 죽이면 놀랄 일이다.
///
/// 자식 프로세스를 **자기 프로세스 그룹**으로 띄운다(`setsid`). 그래야 앱이
/// 죽어도 ros2 launch 가 함께 끌려가지 않고, 반대로 내릴 때는 그룹째 한 번에
/// 정리할 수 있다.
library;

import 'dart:io';

import 'rmf_config_export.dart';

class RmfRunResult {
  const RmfRunResult({required this.success, required this.message});
  final bool success;
  final String message;
}

/// 앱이 띄운 프로젝트. 종료할 때 이것만 정리한다.
String? _startedProject;
int? _startedPid;

/// 앱이 지금 띄워 둔 프로젝트 이름. 없으면 null.
String? get runningProjectName => _startedProject;

Directory? _findProjectRoot() {
  final configured = Platform.environment['RMF_ROOT'];
  if (configured != null && configured.isNotEmpty) {
    final directory = Directory(configured).absolute;
    if (Directory('${directory.path}/rmf_maps').existsSync()) return directory;
  }
  var directory = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    if (Directory('${directory.path}/rmf_maps').existsSync()) return directory;
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return null;
}

String? _mapDirectory(String mapName) {
  final root = _findProjectRoot();
  if (root == null) return null;
  return '${root.path}/rmf_maps/${safeMapDirectoryName(mapName)}';
}

/// `run_<맵이름>.sh` 를 띄운다.
Future<RmfRunResult> startProject(String mapName) async {
  if (_startedProject != null) {
    return RmfRunResult(
      success: false,
      message: '이미 `$_startedProject` 를 띄워 두었습니다. 먼저 중지하세요.',
    );
  }
  final directory = _mapDirectory(mapName);
  if (directory == null) {
    return const RmfRunResult(
      success: false,
      message: 'rmf_maps 디렉터리를 찾을 수 없습니다. RMF_ROOT 를 지정하세요.',
    );
  }
  final script = File('$directory/run_$mapName.sh');
  if (!script.existsSync()) {
    return RmfRunResult(
      success: false,
      message:
          '${script.path} 가 없습니다.\n'
          '설정 파일 메뉴에서 `디스크로 내보내기`를 먼저 누르세요.',
    );
  }
  try {
    // detached 로 띄우면 Dart 가 새 세션을 만들어 주므로 앱이 죽어도 함께
    // 끌려가지 않는다. 다만 여기서 받는 pid 는 그룹 리더가 아니다 — 그룹 정리는
    // 실행 스크립트가 남긴 PGID 파일을 보고 중지 스크립트가 한다.
    final process = await Process.start(
      'bash',
      [script.path],
      workingDirectory: directory,
      mode: ProcessStartMode.detachedWithStdio,
    );
    _startedProject = mapName;
    _startedPid = process.pid;
    return RmfRunResult(
      success: true,
      message: '`$mapName` 을 띄웠습니다 (pid $_startedPid).',
    );
  } catch (error) {
    return RmfRunResult(success: false, message: '$error');
  }
}

/// `stop_<맵이름>.sh` 로 내린다. [mapName] 을 주지 않으면 앱이 띄운 것을 내린다.
Future<RmfRunResult> stopProject([String? mapName]) async {
  final target = mapName ?? _startedProject;
  if (target == null) {
    return const RmfRunResult(success: false, message: '앱이 띄워 둔 프로젝트가 없습니다.');
  }
  final directory = _mapDirectory(target);
  if (directory == null) {
    return const RmfRunResult(
      success: false,
      message: 'rmf_maps 디렉터리를 찾을 수 없습니다.',
    );
  }
  final buffer = StringBuffer();
  final script = File('$directory/stop_$target.sh');
  if (script.existsSync()) {
    try {
      final result = await Process.run('bash', [
        script.path,
      ], workingDirectory: directory).timeout(const Duration(seconds: 60));
      buffer.writeln(result.stdout.toString().trim());
      final error = result.stderr.toString().trim();
      if (error.isNotEmpty) buffer.writeln(error);
    } catch (error) {
      buffer.writeln('중지 스크립트 실패: $error');
    }
  } else {
    buffer.writeln('${script.path} 가 없습니다. 프로세스 그룹만 정리합니다.');
  }
  // 중지 스크립트가 없거나 놓친 것이 있으면 여기서 마무리한다.
  //
  // 그룹 번호는 실행 스크립트가 남긴 파일에서 읽는다. Process.start 가 돌려준
  // pid 는 그룹 리더가 아니라서 그 번호로 그룹을 끊으면 엉뚱한 곳을 건드린다.
  final pgidFile = File('$directory/.$target.pgid');
  if (pgidFile.existsSync()) {
    final pgid = int.tryParse((await pgidFile.readAsString()).trim());
    if (pgid != null) {
      final alive = await Process.run('kill', ['-0', '--', '-$pgid']);
      if (alive.exitCode == 0) {
        await Process.run('kill', ['-INT', '--', '-$pgid']);
        await Future<void>.delayed(const Duration(seconds: 3));
        await Process.run('kill', ['-TERM', '--', '-$pgid']);
        buffer.writeln('프로세스 그룹 $pgid 를 정리했습니다.');
      }
    }
    if (pgidFile.existsSync()) await pgidFile.delete();
  }
  _startedProject = null;
  _startedPid = null;
  return RmfRunResult(success: true, message: buffer.toString().trim());
}

/// 지난 실행에서 정리되지 않고 남은 프로젝트.
class OrphanedProject {
  const OrphanedProject({required this.mapName, required this.pgid});

  final String mapName;
  final int pgid;
}

/// 강제 종료로 남은 프로젝트를 찾는다.
///
/// 실행 스크립트가 남긴 `.<맵이름>.pgid` 를 훑어 그 프로세스 그룹이 아직 살아
/// 있는지 본다. 앱이 강제로 죽으면(kill -9·전원) 종료 훅이 돌지 않으므로 이
/// 파일과 프로세스가 그대로 남는다.
///
/// 프로세스가 이미 없는 파일은 조용히 지운다. 남지도 않은 것을 두고 알릴 일은
/// 아니다.
Future<List<OrphanedProject>> findOrphanedProjects() async {
  final root = _findProjectRoot();
  if (root == null) return const [];
  final maps = Directory('${root.path}/rmf_maps');
  if (!maps.existsSync()) return const [];
  final found = <OrphanedProject>[];
  for (final entry in maps.listSync()) {
    if (entry is! Directory) continue;
    for (final file in entry.listSync()) {
      if (file is! File) continue;
      final name = file.uri.pathSegments.last;
      if (!name.startsWith('.') || !name.endsWith('.pgid')) continue;
      final mapName = name.substring(1, name.length - '.pgid'.length);
      // 앱이 지금 띄워 둔 것은 남은 것이 아니다.
      if (mapName == _startedProject) continue;
      final pgid = int.tryParse((await file.readAsString()).trim());
      if (pgid == null) {
        await file.delete();
        continue;
      }
      // 음수는 프로세스 그룹. 시그널 0 은 살아 있는지만 확인한다.
      final alive = await Process.run('kill', ['-0', '--', '-$pgid']);
      if (alive.exitCode != 0) {
        await file.delete();
        continue;
      }
      found.add(OrphanedProject(mapName: mapName, pgid: pgid));
    }
  }
  found.sort((a, b) => a.mapName.compareTo(b.mapName));
  return found;
}
