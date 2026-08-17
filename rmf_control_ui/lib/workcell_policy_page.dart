/// WorkCell Policy 관리 화면.
///
/// Policy 는 프로젝트별로 가진다. 창고가 늘고 policy 가 쌓이면 전부 한 목록에
/// 두고 고르는 것이 불가능해지기 때문이다. 다만 소속은 이름표일 뿐이라 프로젝트를
/// 지워도 policy 는 남고, [PolicyEditDialog] 에서 다른 프로젝트로 옮길 수 있다.
///
/// 학습 결과 ZIP 은 git 에 올리지 않으므로 다른 자리에서 받은 저장소에는
/// **목록에는 있으나 파일이 없는** policy 가 생긴다. 그런 policy 에는 내려받기
/// 단추를 내밀어 Hugging Face 에서 그때의 revision 그대로 다시 받게 한다.
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'map_project_store.dart';
import 'movable_dialog.dart';
import 'rmf_project_config.dart';
import 'workcell_policy_store.dart';

class WorkcellPolicyPage extends StatefulWidget {
  const WorkcellPolicyPage({
    super.key,
    required this.projectName,
    required this.robots,
    required this.onChanged,
  });

  final String? projectName;
  final List<RmfProjectRobot> robots;

  /// 이 프로젝트가 가진 policy 가 바뀌면 알린다. 작업 화면의 픽업 목록이 이걸
  /// 본다.
  final ValueChanged<List<WorkcellPolicy>> onChanged;

  @override
  State<WorkcellPolicyPage> createState() => _WorkcellPolicyPageState();
}

class _WorkcellPolicyPageState extends State<WorkcellPolicyPage> {
  /// 프로젝트를 가리지 않은 전체 목록. 화면에서 걸러 보여 준다.
  List<WorkcellPolicy> _all = const [];

  /// 소속을 고를 때 쓰는 프로젝트 이름들.
  List<String> _projects = const [];

  bool _loading = false;
  bool _projectOnly = true;
  String? _error;

  /// 설치가 몇 %까지 왔는지. 팝업의 막대가 이 값만 듣고 다시 그린다.
  final ValueNotifier<PolicyInstallProgress> _progress = ValueNotifier(
    const PolicyInstallProgress(phase: PolicyInstallPhase.metadata),
  );

  List<RmfProjectRobot> get _workcells =>
      widget.robots.where((robot) => !robot.isMobile).toList();

  /// 지금 화면에 보이는 것. 이 프로젝트만 볼지 전체를 볼지에 따라 갈린다.
  List<WorkcellPolicy> get _visible {
    final project = widget.projectName;
    if (!_projectOnly || project == null) return _all;
    return [
      for (final policy in _all)
        if (policy.projectName == project) policy,
    ];
  }

  List<WorkcellPolicy> get _mine {
    final project = widget.projectName;
    if (project == null) return const [];
    return [
      for (final policy in _all)
        if (policy.projectName == project) policy,
    ];
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant WorkcellPolicyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectName != widget.projectName) _reload();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await loadGlobalWorkcellPolicies();
      final projects = await listMapProjects();
      if (!mounted) return;
      setState(() {
        _all = all;
        _projects = [for (final project in projects) project.mapName];
        _loading = false;
      });
      widget.onChanged(List.unmodifiable(_mine));
    } catch (error) {
      if (!mounted) return;
      // MySQL 이 안 떠 있으면 여기서 걸린다. 무엇이 안 됐는지 화면에 남긴다.
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  /// 진행률 팝업을 띄우고, 그 팝업을 닫는 함수를 돌려준다.
  ///
  /// 팝업을 기다리지 않고 바로 돌려주어야 그 아래에서 설치를 이어 갈 수 있다.
  /// 두 번 닫으면 뒤에 있던 화면까지 사라지므로 한 번만 닫는다.
  VoidCallback _openProgressDialog(String title, {VoidCallback? onCancel}) {
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showMovableDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PolicyInstallDialog(
          title: title,
          progress: _progress,
          onCancel: onCancel,
        ),
      ),
    );
    var open = true;
    return () {
      if (!open) return;
      open = false;
      navigator.pop();
    };
  }

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    final file = picked?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null || !mounted) return;
    // 고른 파일은 이미 Uint8List 다. 다시 복사하면 190MB 를 한 번 더 만든다.
    await _registerArchive(file.name, bytes);
  }

  Future<void> _fromHuggingFace() async {
    final source = await showMovableDialog<_HuggingFaceDraft>(
      context: context,
      builder: (_) => const _HuggingFaceDialog(),
    );
    if (source == null || !mounted) return;
    setState(() => _loading = true);
    final cancelToken = PolicyInstallCancelToken();
    _progress.value = const PolicyInstallProgress(
      phase: PolicyInstallPhase.metadata,
    );
    final close = _openProgressDialog(
      'Hugging Face에서 Policy 설치',
      onCancel: cancelToken.cancel,
    );
    try {
      final downloaded = await downloadHuggingFacePolicy(
        repositoryUrl: source.repositoryUrl,
        onProgress: (progress) => _progress.value = progress,
        cancelToken: cancelToken,
      );
      close();
      if (!mounted) return;
      await _registerArchive(
        downloaded.fileName,
        downloaded.bytes,
        sourceRepository: downloaded.repositoryId,
        sourceRevision: downloaded.revision,
      );
    } on PolicyInstallCancelled {
      _message('Policy 설치를 취소했습니다.');
    } catch (error) {
      _message('Hugging Face에서 불러오지 못했습니다: $error');
    } finally {
      close();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _registerArchive(
    String archiveName,
    Uint8List bytes, {
    String? sourceRepository,
    String? sourceRevision,
  }) async {
    final project = widget.projectName;
    if (project == null || project.isEmpty) return;
    final archiveError = validatePolicyArchive(archiveName, bytes);
    if (archiveError != null) {
      _message(archiveError);
      return;
    }
    final draft = await showMovableDialog<_PolicyDraft>(
      context: context,
      builder: (_) => _PolicyUploadDialog(
        archiveName: archiveName,
        archiveBytes: bytes.length,
        workcells: _workcells,
      ),
    );
    if (draft == null || !mounted) return;
    final policy = WorkcellPolicy(
      name: draft.name,
      version: draft.version,
      objectType: draft.objectType,
      robotModel: draft.robotModel,
      archiveName: archiveName,
      archiveBytes: bytes.length,
      deployedWorkcells: draft.workcells,
      createdAt: DateTime.now(),
      sourceRepository: sourceRepository,
      sourceRevision: sourceRevision,
      projectName: project,
      storageKey: policyStorageKey(draft.name, draft.version),
    );
    // ZIP 을 보관함에 옮겨 적는 동안에도 몇 %인지 보인다. 수백 MB를 쓰는
    // 일이라 아무것도 안 보이면 앱이 멈춘 줄 안다.
    _progress.value = PolicyInstallProgress(
      phase: PolicyInstallPhase.save,
      fileName: archiveName,
    );
    final close = _openProgressDialog('${policy.id} 저장');
    try {
      await saveWorkcellPolicy(project, policy, bytes);
    } catch (error) {
      close();
      _message('$error');
      return;
    } finally {
      close();
    }
    await _reload();
    _message('${policy.id} 를 $project 프로젝트에 등록했습니다. 로봇 관리에서 설비에 붙이세요.');
  }

  /// 이름·버전·물품·모델·소속 프로젝트를 고친다. 학습 결과는 건드리지 않는다.
  Future<void> _edit(WorkcellPolicy policy) async {
    final edited = await showMovableDialog<WorkcellPolicy>(
      context: context,
      builder: (_) => PolicyEditDialog(
        policy: policy,
        projects: _projects,
        others: [
          for (final item in _all)
            if (item.id != policy.id) item,
        ],
      ),
    );
    if (edited == null || !mounted) return;
    try {
      await updateWorkcellPolicy(original: policy, edited: edited);
    } catch (error) {
      _message('$error');
      return;
    }
    await _reload();
    _message('${edited.id} 정보를 고쳤습니다.');
  }

  /// 목록에는 있으나 파일이 없는 policy 를 Hugging Face 에서 다시 받는다.
  Future<void> _download(WorkcellPolicy policy) async {
    final cancelToken = PolicyInstallCancelToken();
    _progress.value = const PolicyInstallProgress(
      phase: PolicyInstallPhase.metadata,
    );
    final close = _openProgressDialog(
      '${policy.id} 내려받기',
      onCancel: cancelToken.cancel,
    );
    try {
      await downloadPolicyArchive(
        policy,
        onProgress: (progress) => _progress.value = progress,
        cancelToken: cancelToken,
      );
      close();
      await _reload();
      _message('${policy.id} 를 다시 받았습니다.');
    } on PolicyInstallCancelled {
      _message('내려받기를 취소했습니다.');
    } catch (error) {
      _message('내려받지 못했습니다: $error');
    } finally {
      close();
    }
  }

  /// Hugging Face 출처가 없는 policy 는 사람이 ZIP 을 다시 올려 채운다.
  Future<void> _restore(WorkcellPolicy policy) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    final bytes = picked?.files.singleOrNull?.bytes;
    if (bytes == null || !mounted) return;
    try {
      await restorePolicyArchive(policy, bytes);
    } catch (error) {
      _message('$error');
      return;
    }
    await _reload();
    _message('${policy.id} 의 ZIP 을 채웠습니다.');
  }

  /// 공용 policy 를 이 프로젝트 것으로 가져온다.
  Future<void> _claim(WorkcellPolicy policy) async {
    final project = widget.projectName;
    if (project == null) return;
    try {
      await bindWorkcellPolicy(project, policy);
    } catch (error) {
      _message('$error');
      return;
    }
    await _reload();
    _message('${policy.id} 를 $project 프로젝트로 가져왔습니다.');
  }

  /// 이 프로젝트에서 뗀다. Policy 자체는 공용으로 남는다.
  Future<void> _release(WorkcellPolicy policy) async {
    final project = widget.projectName;
    if (project == null) return;
    final confirmed = await showMovableDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('프로젝트에서 뗄까요?'),
        content: Text(
          '${policy.id} 를 $project 프로젝트에서 뗍니다.\n'
          'Policy 와 학습 결과는 공용으로 남아 다른 프로젝트에서 다시 쓸 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('프로젝트에서 떼기'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await deleteWorkcellPolicy(project, policy);
    } catch (error) {
      _message('$error');
      return;
    }
    await _reload();
    _message('${policy.id} 를 $project 프로젝트에서 뗐습니다.');
  }

  /// 목록에서도 디스크에서도 없앤다. 어느 프로젝트도 쓰지 않을 때만 열린다.
  Future<void> _deleteForever(WorkcellPolicy policy) async {
    final confirmed = await showMovableDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_forever_outlined, size: 32),
        title: const Text('아주 지울까요?'),
        content: Text(
          '${policy.id} 를 목록과 디스크에서 모두 지웁니다.\n'
          '되돌릴 수 없습니다'
          '${policy.canDownload ? ' — 다만 ${policy.sourceRepository} 에서 다시 받을 수 있습니다.' : '.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('아주 지우기'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await deleteGlobalWorkcellPolicy(policy);
    } catch (error) {
      _message('$error');
      return;
    }
    await _reload();
    _message('${policy.id} 를 지웠습니다.');
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final noProject = widget.projectName == null;
    final visible = _visible;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WorkCell Policy 관리',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text('프로젝트별 보관 · 기본 정보 수정 · 없는 ZIP 다시 받기'),
                  ],
                ),
              ),
              Wrap(
                spacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('다시 읽기'),
                  ),
                  OutlinedButton.icon(
                    onPressed: noProject || _loading ? null : _fromHuggingFace,
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('Hugging Face에서 불러오기'),
                  ),
                  FilledButton.icon(
                    onPressed: noProject || _loading ? null : _upload,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Policy ZIP 등록'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text('이 프로젝트 (${_mine.length})'),
                    icon: const Icon(Icons.folder_outlined, size: 17),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('전체 (${_all.length})'),
                    icon: const Icon(Icons.inventory_2_outlined, size: 17),
                  ),
                ],
                selected: {noProject ? false : _projectOnly},
                onSelectionChanged: noProject
                    ? null
                    : (selected) =>
                          setState(() => _projectOnly = selected.first),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  noProject
                      ? '프로젝트를 열면 그 프로젝트의 Policy 만 따로 볼 수 있습니다.'
                      : 'Policy 는 프로젝트를 지워도 남습니다. 소속은 `수정` 에서 바꿉니다.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_error != null)
            _Notice('Policy 목록을 읽지 못했습니다: $_error')
          else if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (visible.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  noProject
                      ? '프로젝트를 먼저 열어 주세요.'
                      : _projectOnly
                      ? '이 프로젝트에 등록된 Policy 가 없습니다.'
                      : '등록된 Policy 가 없습니다.',
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final policy = visible[index];
                  final mine = policy.projectName == widget.projectName;
                  return PolicyListTile(
                    policy: policy,
                    openProject: widget.projectName,
                    onEdit: () => unawaited(_edit(policy)),
                    onDownload: policy.archiveMissing && policy.canDownload
                        ? () => unawaited(_download(policy))
                        : null,
                    onRestore: policy.archiveMissing
                        ? () => unawaited(_restore(policy))
                        : null,
                    onClaim: !noProject && policy.projectName == null
                        ? () => unawaited(_claim(policy))
                        : null,
                    onRelease: mine && !noProject
                        ? () => unawaited(_release(policy))
                        : null,
                    onDelete: policy.projectName == null
                        ? () => unawaited(_deleteForever(policy))
                        : null,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Policy 한 줄. 지금 쓸 수 있는 것과 없는 것을 한눈에 가른다.
///
/// ZIP 이 없으면 이름 옆에 그렇게 적고 받는 단추를 내민다. 그 표시가 없으면
/// 사람은 작업을 걸어 놓고 로봇이 멈춘 뒤에야 파일이 없다는 것을 알게 된다.
class PolicyListTile extends StatelessWidget {
  const PolicyListTile({
    super.key,
    required this.policy,
    required this.openProject,
    this.onEdit,
    this.onDownload,
    this.onRestore,
    this.onClaim,
    this.onRelease,
    this.onDelete,
  });

  final WorkcellPolicy policy;

  /// 지금 열린 프로젝트. 소속을 견주어 무엇을 내밀지 가른다.
  final String? openProject;

  final VoidCallback? onEdit;

  /// Hugging Face 에서 다시 받기. 파일이 있거나 출처를 모르면 null.
  final VoidCallback? onDownload;

  /// 사람이 ZIP 을 다시 올리기. 파일이 있으면 null.
  final VoidCallback? onRestore;

  final VoidCallback? onClaim;
  final VoidCallback? onRelease;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: policy.archiveMissing
                    ? const Color(0xFFFEE2E2)
                    : policy.isDeployed
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFFEF3C7),
                child: Icon(
                  policy.archiveMissing
                      ? Icons.cloud_off_outlined
                      : policy.isDeployed
                      ? Icons.check
                      : Icons.inventory_2,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            policy.id,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (policy.archiveMissing)
                          const _PolicyBadge(
                            label: '파일 없음',
                            color: Color(0xFFDC2626),
                          )
                        else if (policy.projectName == null)
                          const _PolicyBadge(
                            label: '공용',
                            color: Color(0xFF2563EB),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '프로젝트: ${policy.projectName ?? '공용 (소속 없음)'}'
                      ' · 물품: ${policy.objectType.isEmpty ? '미지정' : policy.objectType}'
                      ' · 모델: ${policy.robotModel}\n'
                      '설비: ${policy.deployedWorkcells.isEmpty ? '아직 안 붙임' : policy.deployedWorkcells.join(', ')}'
                      ' · ZIP ${formatPolicyBytes(policy.archiveBytes)}'
                      '${policy.sourceRepository == null ? '' : '\nHugging Face: ${policy.sourceRepository} @ ${policy.sourceRevision}'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (policy.archiveMissing)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                policy.canDownload
                    ? '학습 결과 파일이 이 자리에 없습니다. ZIP 은 git 에 올리지 않으므로 다시 받아야 씁니다.'
                    : '학습 결과 파일이 없고 받아 올 곳도 모릅니다. ZIP 을 다시 올려 주세요.',
                style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
              ),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              if (onDownload != null)
                FilledButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.cloud_download_outlined, size: 18),
                  label: const Text('Hugging Face에서 내려받기'),
                ),
              if (onRestore != null)
                OutlinedButton.icon(
                  onPressed: onRestore,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('ZIP 다시 올리기'),
                ),
              if (onEdit != null)
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('수정'),
                ),
              if (onClaim != null)
                OutlinedButton.icon(
                  onPressed: onClaim,
                  icon: const Icon(Icons.add_link, size: 18),
                  label: Text('$openProject 프로젝트로 가져오기'),
                ),
              if (onRelease != null)
                OutlinedButton.icon(
                  onPressed: onRelease,
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('프로젝트에서 떼기'),
                ),
              if (onDelete != null)
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_forever_outlined, size: 18),
                  label: const Text('아주 지우기'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _PolicyBadge extends StatelessWidget {
  const _PolicyBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
    ),
  );
}

/// Policy 의 기본 정보를 고치는 팝업.
///
/// 고치는 것은 이름표뿐이다 — 학습 결과 ZIP 은 그대로 두고, 파일이 놓인 자리도
/// 옮기지 않는다. 그래서 파일이 없는 자리에서도 이름과 소속을 정리할 수 있다.
class PolicyEditDialog extends StatefulWidget {
  const PolicyEditDialog({
    super.key,
    required this.policy,
    required this.projects,
    this.others = const [],
  });

  final WorkcellPolicy policy;

  /// 소속으로 고를 수 있는 프로젝트 이름.
  final List<String> projects;

  /// 이미 있는 다른 policy. 이름이 겹치는지 여기서 본다.
  final List<WorkcellPolicy> others;

  @override
  State<PolicyEditDialog> createState() => _PolicyEditDialogState();
}

class _PolicyEditDialogState extends State<PolicyEditDialog> {
  late final _name = TextEditingController(text: widget.policy.name);
  late final _version = TextEditingController(text: widget.policy.version);
  late final _object = TextEditingController(text: widget.policy.objectType);
  late final _model = TextEditingController(text: widget.policy.robotModel);
  late String? _project = widget.policy.projectName;
  String? _error;

  /// 소속 없음(공용)을 드롭다운에서 고르기 위한 값.
  static const String _unassigned = '';

  @override
  void dispose() {
    _name.dispose();
    _version.dispose();
    _object.dispose();
    _model.dispose();
    super.dispose();
  }

  WorkcellPolicy get _edited => widget.policy.copyWith(
    name: _name.text.trim(),
    version: _version.text.trim(),
    objectType: _object.text.trim(),
    robotModel: _model.text.trim(),
    projectName: _project,
    clearProject: _project == null,
  );

  void _submit() {
    final edited = _edited;
    final error = validatePolicyEdit(
      original: widget.policy,
      edited: edited,
      others: widget.others,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, edited);
  }

  @override
  Widget build(BuildContext context) {
    final projects = {
      ...widget.projects,
      if (widget.policy.projectName != null) widget.policy.projectName!,
    }.toList()..sort();
    return AlertDialog(
      title: Text('${widget.policy.id} 기본 정보'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Policy 이름 *'),
              ),
              TextField(
                controller: _version,
                decoration: const InputDecoration(labelText: '버전 *'),
              ),
              TextField(
                controller: _object,
                decoration: const InputDecoration(labelText: '집을 물품'),
              ),
              TextField(
                controller: _model,
                decoration: const InputDecoration(labelText: '호환 로봇팔 모델 *'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _project ?? _unassigned,
                decoration: const InputDecoration(
                  labelText: '소속 프로젝트',
                  helperText: '프로젝트를 지워도 Policy 는 남습니다. 여기서 다른 프로젝트로 옮깁니다.',
                ),
                items: [
                  const DropdownMenuItem(
                    value: _unassigned,
                    child: Text('공용 (소속 없음)'),
                  ),
                  for (final project in projects)
                    DropdownMenuItem(value: project, child: Text(project)),
                ],
                onChanged: (value) => setState(
                  () => _project = value == _unassigned ? null : value,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '학습 결과(ZIP)는 고치지 않습니다. 파일이 놓인 자리도 그대로입니다: '
                '${widget.policy.storagePath}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: SelectableText(
                    _error!,
                    style: const TextStyle(color: Color(0xFFDC2626)),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _submit, child: const Text('저장')),
      ],
    );
  }
}

/// WorkCell 한 대에 policy 를 붙이고 떼는 팝업.
///
/// 로봇 관리에서 설비 로봇을 열면 여기로 온다. Policy 관리 화면은 policy 쪽에서
/// 보는 자리라 "이 설비가 무엇을 할 수 있는가"를 보려면 로봇을 하나씩 눌러
/// 확인해야 했다. 붙여 둔 policy 는 작업의 픽업 단계에서 그 WorkCell 의 것으로
/// 고를 수 있다.
class WorkcellPolicyAttachDialog extends StatefulWidget {
  const WorkcellPolicyAttachDialog({
    super.key,
    required this.robotId,
    required this.robotName,
    required this.robotModel,
    required this.policies,
    required this.onSave,
  });

  final String robotId;
  final String robotName;

  /// 이 설비의 로봇팔 모델. 같은 모델로 학습한 policy 만 붙일 수 있다.
  final String robotModel;

  /// 프로젝트에 연결된 것과 전역 보관함을 합친 목록.
  final List<WorkcellPolicy> policies;

  /// 바뀐 policy 를 저장하고, 저장 뒤의 전체 목록을 돌려준다. 저장은 파일을
  /// 만지는 일이라 화면 밖(로봇 관리)에서 맡는다.
  final Future<List<WorkcellPolicy>> Function(WorkcellPolicy policy) onSave;

  @override
  State<WorkcellPolicyAttachDialog> createState() =>
      _WorkcellPolicyAttachDialogState();
}

class _WorkcellPolicyAttachDialogState
    extends State<WorkcellPolicyAttachDialog> {
  late List<WorkcellPolicy> _policies = widget.policies;
  final _object = TextEditingController();
  String? _selected;
  bool _busy = false;
  String? _error;

  List<WorkcellPolicy> get _attached =>
      policiesForWorkcell(_policies, widget.robotId);

  List<WorkcellPolicy> get _candidates => policyCandidatesForWorkcell(
    policies: _policies,
    robotId: widget.robotId,
    robotModel: widget.robotModel,
  );

  @override
  void dispose() {
    _object.dispose();
    super.dispose();
  }

  Future<void> _save(WorkcellPolicy policy) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final policies = await widget.onSave(policy);
      if (!mounted) return;
      setState(() {
        _policies = policies;
        _selected = null;
        _object.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attach() async {
    final id = _selected;
    final policy = _candidates.where((item) => item.id == id).firstOrNull;
    if (policy == null) {
      setState(() => _error = '붙일 Policy 를 고르세요.');
      return;
    }
    // 물품 이름이 있어야 작업에서 "무엇을 집는 policy" 인지 알아본다. 전역
    // 보관함에서 갓 가져온 policy 는 비어 있으므로 여기서 받는다.
    final object = _object.text.trim().isEmpty
        ? policy.objectType
        : _object.text.trim();
    if (object.isEmpty) {
      setState(() => _error = '이 Policy 로 집을 물품을 적으세요.');
      return;
    }
    await _save(
      attachPolicyToWorkcell(policy, widget.robotId, objectType: object),
    );
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates;
    return AlertDialog(
      title: Text('${widget.robotId} · ${widget.robotName} Policy'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '모델 ${widget.robotModel} · 붙은 Policy ${_attached.length}개',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (_attached.isEmpty)
                const Text(
                  '이 WorkCell 에 붙은 Policy 가 없습니다.',
                  style: TextStyle(color: Color(0xFFB45309)),
                )
              else
                for (final policy in _attached)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.model_training_outlined),
                      title: Text(policy.id),
                      subtitle: Text(
                        '물품: ${policy.objectType.isEmpty ? '미지정' : policy.objectType}'
                        ' · ZIP ${formatPolicyBytes(policy.archiveBytes)}',
                      ),
                      trailing: IconButton(
                        tooltip: '이 WorkCell 에서 떼기',
                        onPressed: _busy
                            ? null
                            : () => _save(
                                detachPolicyFromWorkcell(
                                  policy,
                                  widget.robotId,
                                ),
                              ),
                        icon: const Icon(Icons.link_off),
                      ),
                    ),
                  ),
              const Divider(height: 26),
              const Text(
                'Policy 추가',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (candidates.isEmpty)
                Text(
                  '${widget.robotModel} 모델에 붙일 수 있는 Policy 가 없습니다. '
                  'Policy 관리에서 먼저 등록하세요.',
                  style: const TextStyle(color: Color(0xFF64748B)),
                )
              else ...[
                DropdownButtonFormField<String>(
                  initialValue: _selected,
                  decoration: const InputDecoration(
                    labelText: '붙일 Policy',
                    isDense: true,
                  ),
                  items: [
                    for (final policy in candidates)
                      DropdownMenuItem(
                        value: policy.id,
                        child: Text(
                          '${policy.id}'
                          '${policy.objectType.isEmpty ? '' : ' · ${policy.objectType}'}',
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _selected = value;
                          final policy = candidates
                              .where((item) => item.id == value)
                              .firstOrNull;
                          _object.text = policy?.objectType ?? '';
                        }),
                ),
                TextField(
                  controller: _object,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: '집을 물품 *',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _attach,
                    icon: const Icon(Icons.add_link),
                    label: const Text('이 WorkCell 에 붙이기'),
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: SelectableText(
                    _error!,
                    style: const TextStyle(color: Color(0xFFDC2626)),
                  ),
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}

/// Policy 설치가 몇 %까지 왔는지 보여주는 팝업.
///
/// LeRobot policy 는 수백 MB라 내려받는 데 몇 분씩 걸린다. 도는 원만 보이면
/// 기다려도 되는 것인지 알 수 없어 막대와 퍼센트, 지금 받는 파일 이름까지
/// 함께 적는다. 받는 동안 뒤의 목록을 보고 싶을 수 있으므로 끌어 옮길 수 있게
/// [showMovableDialog] 로 띄운다.
class PolicyInstallDialog extends StatelessWidget {
  const PolicyInstallDialog({
    super.key,
    required this.title,
    required this.progress,
    this.onCancel,
  });

  /// 진행률 막대를 가리키는 키. 테스트가 이 막대의 값을 읽어 확인한다.
  static const Key barKey = Key('policy-install-progress');

  final String title;
  final ValueListenable<PolicyInstallProgress> progress;

  /// 취소할 수 없는 단계(저장 등)에서는 null 이라 취소 단추가 없다.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 460,
      child: ValueListenableBuilder<PolicyInstallProgress>(
        valueListenable: progress,
        builder: (_, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${value.phase.label} · ${value.percent}%',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                key: barKey,
                value: value.ratio,
                minHeight: 12,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              value.detail,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    ),
    actions: [
      if (onCancel != null)
        TextButton(onPressed: onCancel, child: const Text('취소')),
    ],
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Text(text, style: const TextStyle(color: Color(0xFFB45309))),
  );
}

class _HuggingFaceDraft {
  const _HuggingFaceDraft(this.repositoryUrl);
  final String repositoryUrl;
}

class _HuggingFaceDialog extends StatefulWidget {
  const _HuggingFaceDialog();
  @override
  State<_HuggingFaceDialog> createState() => _HuggingFaceDialogState();
}

class _HuggingFaceDialogState extends State<_HuggingFaceDialog> {
  final _repository = TextEditingController();

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  void _submit() {
    if (parseHuggingFaceRepository(_repository.text) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('올바른 Hugging Face 모델 주소를 입력하세요.')),
      );
      return;
    }
    Navigator.pop(context, _HuggingFaceDraft(_repository.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Hugging Face에서 Policy 불러오기'),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _repository,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Hugging Face 모델 주소 *',
              hintText: 'https://huggingface.co/owner/policy',
              helperText: '주소를 입력하면 저장소의 policy 파일을 자동으로 내려받습니다.',
            ),
          ),
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '비공개 저장소는 앱 실행 환경에 HF_TOKEN을 설정하세요. '
              '토큰은 Policy 정보에 저장되지 않습니다.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(onPressed: _submit, child: const Text('다운로드')),
    ],
  );
}

class _PolicyDraft {
  const _PolicyDraft(
    this.name,
    this.version,
    this.objectType,
    this.robotModel,
    this.workcells,
  );
  final String name;
  final String version;
  final String objectType;
  final String robotModel;
  final List<String> workcells;
}

class _PolicyUploadDialog extends StatefulWidget {
  const _PolicyUploadDialog({
    required this.archiveName,
    required this.archiveBytes,
    required this.workcells,
  });
  final String archiveName;
  final int archiveBytes;
  final List<RmfProjectRobot> workcells;
  @override
  State<_PolicyUploadDialog> createState() => _PolicyUploadDialogState();
}

class _PolicyUploadDialogState extends State<_PolicyUploadDialog> {
  final _name = TextEditingController();
  final _version = TextEditingController(text: '1.0.0');
  final _object = TextEditingController();
  late final _model = TextEditingController(text: _models.firstOrNull ?? '');
  final Set<String> _targets = {};

  List<String> get _models =>
      widget.workcells.map((e) => e.model).toSet().toList();

  @override
  void dispose() {
    _name.dispose();
    _version.dispose();
    _object.dispose();
    _model.dispose();
    super.dispose();
  }

  void _submit() {
    final error = validatePolicyName(_name.text);
    if (error != null ||
        _version.text.trim().isEmpty ||
        _object.text.trim().isEmpty ||
        _model.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error ?? '버전·물품·로봇 모델을 입력하세요.')));
      return;
    }
    Navigator.pop(
      context,
      _PolicyDraft(
        _name.text.trim(),
        _version.text.trim(),
        _object.text.trim(),
        _model.text.trim(),
        _targets.toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Policy 등록'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: Text(widget.archiveName),
              subtitle: Text(
                '${(widget.archiveBytes / 1024 / 1024).toStringAsFixed(1)}MB · ZIP 형식 확인 완료',
              ),
            ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Policy 이름 *'),
            ),
            TextField(
              controller: _version,
              decoration: const InputDecoration(labelText: '버전 *'),
            ),
            TextField(
              controller: _object,
              decoration: const InputDecoration(labelText: '집을 물품 *'),
            ),
            TextField(
              controller: _model,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '호환 로봇팔 모델 *',
                helperText: _models.isEmpty
                    ? '이 모델의 설비 로봇에만 붙일 수 있습니다.'
                    : '이 프로젝트의 설비 모델: ${_models.join(', ')}',
              ),
            ),
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '바로 붙일 WorkCell (나중에 로봇 관리에서 붙여도 됩니다)',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            for (final cell in widget.workcells.where(
              (cell) => cell.model == _model.text.trim(),
            ))
              CheckboxListTile(
                value: _targets.contains(cell.robotId),
                title: Text('${cell.displayName} (${cell.robotId})'),
                subtitle: Text(cell.dataSource.label),
                onChanged: (checked) => setState(() {
                  if (checked == true) {
                    _targets.add(cell.robotId);
                  } else {
                    _targets.remove(cell.robotId);
                  }
                }),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(onPressed: _submit, child: const Text('등록')),
    ],
  );
}
