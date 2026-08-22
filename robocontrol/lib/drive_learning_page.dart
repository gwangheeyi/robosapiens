import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'drive_learning_store.dart';

class DriveLearningPage extends StatefulWidget {
  const DriveLearningPage({
    super.key,
    required this.mapName,
    required this.onApply,
  });
  final String mapName;
  final Future<void> Function(DriveLearningRecommendation value) onApply;

  @override
  State<DriveLearningPage> createState() => _DriveLearningPageState();
}

class _DriveLearningPageState extends State<DriveLearningPage> {
  late Future<List<DriveLearningSample>> _future = _load();
  String? _waypoint;
  String? _mode;

  Future<List<DriveLearningSample>> _load() =>
      loadDriveLearningSamples(mapName: widget.mapName);
  void _reload() => setState(() => _future = _load());
  String _n(double value, [int digits = 3]) => value.toStringAsFixed(digits);

  Future<void> _showFailure(DriveLearningSample sample) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.error_outline, color: Color(0xFFDC2626)),
      title: Text('${sample.taskName} · ${sample.waypointName} 실패'),
      content: SizedBox(
        width: 760,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sample.failureReason ?? '원인을 분류하지 못했습니다.'),
            if (sample.nav2Status != null)
              Text('Nav2 status: ${sample.nav2Status}'),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 420),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF0F172A),
              child: SingleChildScrollView(
                child: SelectableText(
                  (sample.errorLog ?? '').trim().isEmpty
                      ? '관련 오류 로그를 찾지 못했습니다.'
                      : sample.errorLog!,
                  style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    ),
  );

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<DriveLearningSample>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: SelectableText('주행학습 기록을 읽지 못했습니다.\n${snapshot.error}'),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final all = snapshot.data!;
      final waypoints =
          all
              .map((s) => s.waypointName)
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      final shown = all
          .where(
            (s) =>
                (_waypoint == null || s.waypointName == _waypoint) &&
                (_mode == null || s.driveMode == _mode),
          )
          .toList();
      final recommendation = recommendDriveSettings(shown);
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '주행학습',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${widget.mapName} · RMF 이동 완료 시 실제 odometry와 목표를 자동 비교합니다.',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _reload,
                  tooltip: '새로고침',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                DropdownButton<String?>(
                  value: _waypoint,
                  hint: const Text('모든 Waypoint'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('모든 Waypoint'),
                    ),
                    for (final value in waypoints)
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (v) => setState(() => _waypoint = v),
                ),
                DropdownButton<String?>(
                  value: _mode,
                  hint: const Text('모든 모드'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('모든 모드')),
                    DropdownMenuItem(value: 'normal', child: Text('일반모드')),
                    DropdownMenuItem(value: 'forced', child: Text('강제모드')),
                  ],
                  onChanged: (v) => setState(() => _mode = v),
                ),
                Chip(label: Text('${shown.length}회 기록')),
              ],
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: recommendation == null
                    ? const Text('같은 설정으로 성공한 기록이 2회 이상 쌓이면 추천값을 표시합니다.')
                    : Row(
                        children: [
                          Expanded(
                            child: Text(
                              '추천  선속도 ${_n(recommendation.linearVelocity)} m/s · 선가속도 ${_n(recommendation.linearAcceleration)} m/s²\n'
                              '각속도 ${_n(recommendation.angularVelocity)} rad/s · 각가속도 ${_n(recommendation.angularAcceleration)} rad/s²\n'
                              '${recommendation.samples}회 평균 위치오차 ${_n(recommendation.meanPositionError * 100, 1)} cm · '
                              '방향오차 ${_n(recommendation.meanHeadingError * 180 / math.pi, 1)}°',
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: () => widget.onApply(recommendation),
                            icon: const Icon(Icons.tune),
                            label: const Text('추천값 적용'),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Card(
                child: shown.isEmpty
                    ? const Center(child: Text('아직 기록이 없습니다. RMF 작업을 실행해 주세요.'))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('완료 시각')),
                              DataColumn(label: Text('작업 / Waypoint')),
                              DataColumn(label: Text('로봇 / 모드')),
                              DataColumn(label: Text('선속도 / 가속도')),
                              DataColumn(label: Text('각속도 / 가속도')),
                              DataColumn(label: Text('위치 오차')),
                              DataColumn(label: Text('방향 오차')),
                              DataColumn(label: Text('시간')),
                              DataColumn(label: Text('결과 / 원인')),
                            ],
                            rows: [
                              for (final s in shown)
                                DataRow(
                                  cells: [
                                    DataCell(
                                      Text(
                                        s.finishedAt
                                            .toLocal()
                                            .toString()
                                            .substring(0, 19),
                                      ),
                                    ),
                                    DataCell(
                                      Text('${s.taskName}\n${s.waypointName}'),
                                    ),
                                    DataCell(
                                      Text(
                                        '${s.robotId}\n${s.driveMode == 'forced' ? '강제' : '일반'}',
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '${_n(s.linearVelocity)} / ${_n(s.linearAcceleration)}',
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '${_n(s.angularVelocity)} / ${_n(s.angularAcceleration)}',
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '${_n(s.positionError * 100, 1)} cm',
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        s.headingError == null
                                            ? '-'
                                            : '${_n(s.headingError! * 180 / math.pi, 1)}°',
                                      ),
                                    ),
                                    DataCell(
                                      Text('${_n(s.durationSeconds, 1)}초'),
                                    ),
                                    DataCell(
                                      s.success
                                          ? const Text(
                                              '성공',
                                              style: TextStyle(
                                                color: Color(0xFF15803D),
                                              ),
                                            )
                                          : TextButton.icon(
                                              onPressed: () => _showFailure(s),
                                              icon: const Icon(
                                                Icons.error_outline,
                                                size: 18,
                                              ),
                                              label: Text(
                                                s.failureReason ?? '실패 로그',
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
