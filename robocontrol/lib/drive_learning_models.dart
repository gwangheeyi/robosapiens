import 'dart:math' as math;

class DriveLearningSample {
  const DriveLearningSample({
    this.id,
    required this.mapName,
    required this.taskId,
    required this.taskName,
    required this.robotId,
    required this.waypointName,
    required this.driveMode,
    required this.startedAt,
    required this.finishedAt,
    required this.linearVelocity,
    required this.linearAcceleration,
    required this.angularVelocity,
    required this.angularAcceleration,
    required this.goalTolerance,
    required this.goalX,
    required this.goalY,
    required this.actualX,
    required this.actualY,
    required this.positionError,
    this.goalHeading,
    this.actualHeading,
    this.headingError,
    required this.success,
    this.nav2Status,
    this.failureReason,
    this.errorLog,
  });

  final int? id;
  final String mapName, taskId, taskName, robotId, waypointName, driveMode;
  final DateTime startedAt, finishedAt;
  final double linearVelocity, linearAcceleration;
  final double angularVelocity, angularAcceleration, goalTolerance;
  final double goalX, goalY, actualX, actualY, positionError;
  final double? goalHeading, actualHeading, headingError;
  final bool success;
  final int? nav2Status;
  final String? failureReason;
  final String? errorLog;
  double get durationSeconds =>
      finishedAt.difference(startedAt).inMilliseconds / 1000;

  factory DriveLearningSample.fromJson(Map<String, dynamic> json) =>
      DriveLearningSample(
        id: (json['id'] as num?)?.toInt(),
        mapName: json['mapName'] as String? ?? '',
        taskId: json['taskId'] as String? ?? '',
        taskName: json['taskName'] as String? ?? '',
        robotId: json['robotId'] as String? ?? '',
        waypointName: json['waypointName'] as String? ?? '',
        driveMode: json['driveMode'] as String? ?? 'normal',
        startedAt: DateTime.parse(json['startedAt'] as String),
        finishedAt: DateTime.parse(json['finishedAt'] as String),
        linearVelocity: (json['linearVelocity'] as num).toDouble(),
        linearAcceleration: (json['linearAcceleration'] as num).toDouble(),
        angularVelocity: (json['angularVelocity'] as num).toDouble(),
        angularAcceleration: (json['angularAcceleration'] as num).toDouble(),
        goalTolerance: (json['goalTolerance'] as num).toDouble(),
        goalX: (json['goalX'] as num).toDouble(),
        goalY: (json['goalY'] as num).toDouble(),
        actualX: (json['actualX'] as num).toDouble(),
        actualY: (json['actualY'] as num).toDouble(),
        positionError: (json['positionError'] as num).toDouble(),
        goalHeading: (json['goalHeading'] as num?)?.toDouble(),
        actualHeading: (json['actualHeading'] as num?)?.toDouble(),
        headingError: (json['headingError'] as num?)?.toDouble(),
        success: json['success'] == true || json['success'] == 1,
        nav2Status: (json['nav2Status'] as num?)?.toInt(),
        failureReason: json['failureReason'] as String?,
        errorLog: json['errorLog'] as String?,
      );
}

class DriveLearningRecommendation {
  const DriveLearningRecommendation({
    required this.linearVelocity,
    required this.linearAcceleration,
    required this.angularVelocity,
    required this.angularAcceleration,
    required this.meanPositionError,
    required this.meanHeadingError,
    required this.samples,
  });
  final double linearVelocity, linearAcceleration;
  final double angularVelocity, angularAcceleration;
  final double meanPositionError, meanHeadingError;
  final int samples;
}

/// 같은 파라미터 조합을 묶고 위치 오차와 방향 오차가 가장 작은 조합을 고른다.
/// 한 번의 우연을 추천하지 않도록 두 번 이상 성공한 조합만 사용한다.
DriveLearningRecommendation? recommendDriveSettings(
  Iterable<DriveLearningSample> samples,
) {
  final groups = <String, List<DriveLearningSample>>{};
  for (final sample in samples.where((s) => s.success)) {
    final key = [
      sample.linearVelocity,
      sample.linearAcceleration,
      sample.angularVelocity,
      sample.angularAcceleration,
    ].map((v) => v.toStringAsFixed(3)).join('/');
    groups.putIfAbsent(key, () => []).add(sample);
  }
  DriveLearningRecommendation? best;
  double bestScore = double.infinity;
  for (final group in groups.values.where((g) => g.length >= 2)) {
    final position =
        group.map((s) => s.positionError).reduce((a, b) => a + b) /
        group.length;
    final headings = group
        .map((s) => s.headingError)
        .whereType<double>()
        .toList();
    final heading = headings.isEmpty
        ? 0.0
        : headings.reduce((a, b) => a + b) / headings.length;
    // 10도 방향 오차를 약 10cm 위치 오차와 같은 비중으로 본다.
    final score = position + heading * 0.1 / (10 * math.pi / 180);
    if (score >= bestScore) continue;
    bestScore = score;
    final first = group.first;
    best = DriveLearningRecommendation(
      linearVelocity: first.linearVelocity,
      linearAcceleration: first.linearAcceleration,
      angularVelocity: first.angularVelocity,
      angularAcceleration: first.angularAcceleration,
      meanPositionError: position,
      meanHeadingError: heading,
      samples: group.length,
    );
  }
  return best;
}

double angularError(double actual, double goal) =>
    math.atan2(math.sin(actual - goal), math.cos(actual - goal)).abs();
