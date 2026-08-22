library;

class ExternalPythonResult {
  const ExternalPythonResult({
    required this.success,
    required this.exitCode,
    required this.output,
    required this.duration,
  });

  final bool success;
  final int exitCode;
  final String output;
  final Duration duration;
}

class ExternalPythonRequest {
  const ExternalPythonRequest({
    required this.filePath,
    this.arguments = const [],
    this.timeout = const Duration(minutes: 5),
  });

  final String filePath;
  final List<String> arguments;
  final Duration timeout;
}

class RobotArmPolicyRequest {
  const RobotArmPolicyRequest({
    required this.runnerPath,
    required this.policyPath,
    required this.policyId,
    required this.armNamespace,
    required this.pinkyNamespace,
    required this.rosDomainId,
    this.robotModel = '',
    this.runSeconds = 6,
  });

  final String runnerPath;
  final String policyPath;
  final String policyId;
  final String armNamespace;
  final String pinkyNamespace;
  final int rosDomainId;
  final String robotModel;
  final double runSeconds;
}

/// 따옴표로 묶은 인자를 지원하는 간단한 인자 분리기.
List<String> splitCommandArguments(String input) {
  final result = <String>[];
  final current = StringBuffer();
  String? quote;
  var escaped = false;
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    if (escaped) {
      current.write(char);
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        current.write(char);
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
    } else if (char.trim().isEmpty) {
      if (current.isNotEmpty) {
        result.add(current.toString());
        current.clear();
      }
    } else {
      current.write(char);
    }
  }
  if (escaped) current.write(r'\');
  if (current.isNotEmpty) result.add(current.toString());
  return result;
}

bool odomTwistShowsStopped(
  String output, {
  double linearTolerance = 0.01,
  double angularTolerance = 0.02,
}) {
  for (final line in output.split('\n').reversed) {
    final values = line
        .trim()
        .split(',')
        .map((value) => double.tryParse(value.trim()))
        .toList();
    if (values.length < 6 || values.any((value) => value == null)) continue;
    final numbers = values.cast<double>();
    final linear = numbers
        .take(3)
        .every((value) => value.abs() <= linearTolerance);
    final angular = numbers
        .skip(3)
        .take(3)
        .every((value) => value.abs() <= angularTolerance);
    return linear && angular;
  }
  return false;
}
