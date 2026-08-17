/// 내려받는 동안 화면이 멈추면 안 된다.
///
/// 데스크톱은 앱이 프레임을 못 그리면 "응답하지 않습니다 — 중지할까요?" 를
/// 띄운다. 실제로 그랬고, 까닭은 받은 것을 **화면 isolate 에서 ZIP 으로 누른**
/// 것이었다. 실측(190MB safetensors 한 개) —
///
///     기본 압축(BEST_SPEED)  9,471ms   결과 190MB
///     압축 없이 담기            534ms   결과 190MB
///
/// 그래서 둘을 고쳤다. 압축을 끄고, 그마저도 일꾼 isolate 에서 한다.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/workcell_policy.dart';
import 'package:rmf_control_ui/workcell_policy_store_io.dart';

void main() {
  group('ZIP 으로 담기', () {
    Archive sample() => Archive()
      ..addFile(ArchiveFile('config.json', 2, Uint8List.fromList([0x7b, 0x7d])))
      ..addFile(
        ArchiveFile(
          'model.safetensors',
          64,
          Uint8List.fromList(List.generate(64, (index) => index * 7 % 256)),
        ),
      );

    test('누르지 않고 담는다', () {
      final zipped = zipPolicyFiles(sample());
      // ZIP local file header 의 압축 방식(8~9바이트)이 0 이면 그냥 담은 것이다.
      // 학습 결과는 눌러도 줄지 않는데 누르는 데만 열 배 넘게 걸린다.
      expect(zipped[8], 0);
      expect(zipped[9], 0);
    });

    test('담은 것을 그대로 되읽는다', () {
      final decoded = ZipDecoder().decodeBytes(zipPolicyFiles(sample()));
      expect(decoded.files.map((file) => file.name), [
        'config.json',
        'model.safetensors',
      ]);
      expect(decoded.findFile('config.json')!.content, [0x7b, 0x7d]);
      expect(decoded.findFile('model.safetensors')!.content.length, 64);
    });

    test('ZIP 서명을 가진 진짜 ZIP 이다', () {
      final zipped = zipPolicyFiles(sample());
      expect(validatePolicyArchive('policy.zip', zipped), isNull);
    });
  });

  group('일꾼 isolate', () {
    test('주소가 틀리면 일꾼을 띄우기 전에 막는다', () {
      expect(
        () => downloadHuggingFacePolicy(repositoryUrl: 'https://example.com/a'),
        throwsA(isA<FormatException>()),
      );
    });

    test('일꾼이 실패하면 그 까닭이 화면 쪽으로 돌아온다', () async {
      // 없는 저장소다. 망이 없으면 접속 오류로, 있으면 404 로 끝난다 — 어느
      // 쪽이든 예외가 화면 isolate 까지 돌아와야 한다. 돌아오지 못하면 설치
      // 팝업이 영영 안 닫힌다.
      await expectLater(
        downloadHuggingFacePolicy(
          repositoryUrl: 'robosapiens-test/__no_such_policy__',
        ),
        throwsA(isA<Object>()),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('취소 표', () {
    test('세운 순간을 알린다', () async {
      final token = PolicyInstallCancelToken();
      var told = false;
      unawaited(token.whenCancelled.then((_) => told = true));
      expect(token.isCancelled, isFalse);
      token.cancel();
      await Future<void>.delayed(Duration.zero);
      // 화면과 일꾼이 다른 isolate 라 표를 세운 순간을 알려 줘야 한다.
      expect(told, isTrue);
      expect(token.isCancelled, isTrue);
    });

    test('두 번 눌러도 탈이 없다', () {
      final token = PolicyInstallCancelToken();
      token.cancel();
      expect(token.cancel, returnsNormally);
      expect(token.throwIfCancelled, throwsA(isA<PolicyInstallCancelled>()));
    });
  });
}
