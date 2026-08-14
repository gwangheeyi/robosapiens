import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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
  final ValueChanged<List<WorkcellPolicy>> onChanged;

  @override
  State<WorkcellPolicyPage> createState() => _WorkcellPolicyPageState();
}

class _WorkcellPolicyPageState extends State<WorkcellPolicyPage> {
  List<WorkcellPolicy> _policies = const [];
  bool _loading = false;

  List<RmfProjectRobot> get _workcells =>
      widget.robots.where((robot) => !robot.isMobile).toList();

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

  Future<void> _reload() async {
    final project = widget.projectName;
    if (project == null || project.isEmpty) {
      setState(() => _policies = const []);
      return;
    }
    setState(() => _loading = true);
    final policies = await loadWorkcellPolicies(project);
    if (!mounted) return;
    setState(() {
      _policies = policies..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _loading = false;
    });
    widget.onChanged(List.unmodifiable(_policies));
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
    await _registerArchive(file.name, Uint8List.fromList(bytes));
  }

  Future<void> _fromHuggingFace() async {
    final source = await showDialog<_HuggingFaceDraft>(
      context: context,
      builder: (_) => const _HuggingFaceDialog(),
    );
    if (source == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final downloaded = await downloadHuggingFacePolicy(
        repositoryId: source.repositoryId,
        revision: source.revision,
        fileName: source.fileName,
      );
      if (!mounted) return;
      await _registerArchive(
        downloaded.fileName,
        downloaded.bytes,
        sourceRepository: downloaded.repositoryId,
        sourceRevision: downloaded.revision,
      );
    } catch (error) {
      _message('Hugging Face에서 불러오지 못했습니다: $error');
    } finally {
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
    final draft = await showDialog<_PolicyDraft>(
      context: context,
      builder: (_) => _PolicyUploadDialog(
        archiveName: archiveName,
        archiveBytes: bytes.length,
        workcells: _workcells,
      ),
    );
    if (draft == null || !mounted) return;
    if (_policies.any(
      (policy) => policy.id == '${draft.name}@${draft.version}',
    )) {
      _message('같은 이름과 버전의 Policy가 이미 있습니다.');
      return;
    }
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
    );
    await saveWorkcellPolicy(project, policy, bytes);
    await _reload();
    _message('${policy.id} 등록 및 WorkCell 배포가 완료되었습니다.');
  }

  Future<void> _delete(WorkcellPolicy policy) async {
    final project = widget.projectName;
    if (project == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Policy를 삭제할까요?'),
        content: Text(
          '${policy.id} 원본과 WorkCell 배포본이 함께 삭제됩니다.\n'
          '이 Policy를 사용하는 기존 작업은 실행할 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await deleteWorkcellPolicy(project, policy);
    await _reload();
    _message('${policy.id}를 삭제했습니다.');
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final noProject = widget.projectName == null;
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
                    Text('학습 Policy ZIP 등록 · 버전 관리 · 물품 연결 · WorkCell 배포'),
                  ],
                ),
              ),
              Wrap(
                spacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: noProject || _workcells.isEmpty || _loading
                        ? null
                        : _fromHuggingFace,
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('Hugging Face에서 불러오기'),
                  ),
                  FilledButton.icon(
                    onPressed: noProject || _workcells.isEmpty || _loading
                        ? null
                        : _upload,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Policy ZIP 등록 및 배포'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (noProject)
            const _Notice('먼저 프로젝트를 열어 주세요.')
          else if (_workcells.isEmpty)
            const _Notice('로봇 메뉴에서 설치 로봇(WorkCell)을 먼저 등록하세요.')
          else if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_policies.isEmpty)
            const Expanded(child: Center(child: Text('등록된 Policy가 없습니다.')))
          else
            Expanded(
              child: ListView.separated(
                itemCount: _policies.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final policy = _policies[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: policy.isDeployed
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFFEF3C7),
                        child: Icon(
                          policy.isDeployed ? Icons.check : Icons.inventory_2,
                        ),
                      ),
                      title: Text(
                        policy.id,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '물품: ${policy.objectType} · 모델: ${policy.robotModel}\n'
                        '배포: ${policy.deployedWorkcells.isEmpty ? '미배포' : policy.deployedWorkcells.join(', ')} '
                        '· ZIP ${(policy.archiveBytes / 1024 / 1024).toStringAsFixed(1)}MB'
                        '${policy.sourceRepository == null ? '' : '\nHugging Face: ${policy.sourceRepository} @ ${policy.sourceRevision}'}',
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: 'Policy 및 배포본 삭제',
                        onPressed: () => _delete(policy),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
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
  const _HuggingFaceDraft(this.repositoryId, this.revision, this.fileName);
  final String repositoryId;
  final String revision;
  final String fileName;
}

class _HuggingFaceDialog extends StatefulWidget {
  const _HuggingFaceDialog();
  @override
  State<_HuggingFaceDialog> createState() => _HuggingFaceDialogState();
}

class _HuggingFaceDialogState extends State<_HuggingFaceDialog> {
  final _repository = TextEditingController();
  final _revision = TextEditingController(text: 'main');
  final _file = TextEditingController(text: 'policy.zip');

  @override
  void dispose() {
    _repository.dispose();
    _revision.dispose();
    _file.dispose();
    super.dispose();
  }

  void _submit() {
    if (!RegExp(
          r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$',
        ).hasMatch(_repository.text.trim()) ||
        !_file.text.trim().toLowerCase().endsWith('.zip')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Repository는 owner/name, 파일은 저장소 안의 ZIP 경로로 입력하세요.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      _HuggingFaceDraft(
        _repository.text.trim(),
        _revision.text.trim().isEmpty ? 'main' : _revision.text.trim(),
        _file.text.trim(),
      ),
    );
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
              labelText: 'Repository ID *',
              hintText: 'robosapiens/can-pick-policy',
            ),
          ),
          TextField(
            controller: _revision,
            decoration: const InputDecoration(
              labelText: 'Revision *',
              helperText: '운영 배포에는 branch보다 commit hash 또는 tag를 권장합니다.',
            ),
          ),
          TextField(
            controller: _file,
            decoration: const InputDecoration(
              labelText: '저장소 내 ZIP 파일 경로 *',
              hintText: 'releases/policy.zip',
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
  String? _model;
  final Set<String> _targets = {};

  List<String> get _models =>
      widget.workcells.map((e) => e.model).toSet().toList();

  @override
  void initState() {
    super.initState();
    _model = _models.firstOrNull;
  }

  @override
  void dispose() {
    _name.dispose();
    _version.dispose();
    _object.dispose();
    super.dispose();
  }

  void _submit() {
    final error = validatePolicyName(_name.text);
    if (error != null ||
        _version.text.trim().isEmpty ||
        _object.text.trim().isEmpty ||
        _model == null ||
        _targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? '버전·물품·로봇 모델을 입력하고 배포할 WorkCell을 선택하세요.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      _PolicyDraft(
        _name.text.trim(),
        _version.text.trim(),
        _object.text.trim(),
        _model!,
        _targets.toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Policy 등록 및 배포'),
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
            DropdownButtonFormField<String>(
              initialValue: _model,
              decoration: const InputDecoration(labelText: '호환 로봇팔 모델 *'),
              items: [
                for (final model in _models)
                  DropdownMenuItem(value: model, child: Text(model)),
              ],
              onChanged: (value) => setState(() => _model = value),
            ),
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '배포할 WorkCell *',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            for (final cell in widget.workcells.where(
              (cell) => cell.model == _model,
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
      FilledButton(onPressed: _submit, child: const Text('등록 및 배포')),
    ],
  );
}
