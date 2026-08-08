/// 끌어서 옮길 수 있는 팝업.
///
/// 팝업이 화면 한가운데 고정되면 그 아래의 지도나 목록을 볼 수 없다. 오류
/// 내용을 보면서 해당 Waypoint를 찾거나, 설정값을 바꾸면서 결과를 확인해야
/// 하는 일이 잦아서 팝업은 언제나 옆으로 치울 수 있어야 한다.
///
/// 이 파일의 [showMovableDialog] 는 `showDialog` 와 인자가 같으므로 그대로
/// 바꿔 쓰면 된다. 새 팝업도 이쪽을 쓴다.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// [showDialog] 와 같은 자리에 쓴다. 만들어진 팝업을 [MovableDialog] 로 감싸
/// 끌어 옮길 수 있게 한다.
Future<T?> showMovableDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  bool useRootNavigator = true,
}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  barrierColor: barrierColor,
  useRootNavigator: useRootNavigator,
  builder: (dialogContext) => MovableDialog(child: builder(dialogContext)),
);

/// 팝업을 끌어서 옮길 수 있게 감싼다.
///
/// 팝업 맨 위에 얇은 이동 손잡이를 얹는다. 표면 전체를 끌게 하면 안에서 끌어
/// 쓰는 것들과 부딪힌다 — 본문 글자 선택, 목록 스크롤, 크기 조절 손잡이가
/// 모두 같은 드래그를 두고 다툰다. 손잡이를 따로 두면 그런 다툼이 없고,
/// 옮길 수 있다는 것도 눈에 보인다.
class MovableDialog extends StatefulWidget {
  const MovableDialog({super.key, required this.child});

  /// 손잡이가 차지하는 높이. AlertDialog 의 위쪽 여백 안에 들어가므로 제목이나
  /// 아이콘을 가리지 않는다.
  static const double handleHeight = 20;

  /// 이동 손잡이를 가리키는 키. 테스트에서 이 부분만 끌어 확인한다.
  static const Key handleKey = Key('movable-dialog-handle');

  final Widget child;

  @override
  State<MovableDialog> createState() => _MovableDialogState();
}

class _MovableDialogState extends State<MovableDialog> {
  Offset _offset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    // 화면 밖으로 완전히 빠져나가면 다시 잡을 수 없다. 어느 방향으로 끌든
    // 절반은 남도록 묶는다.
    final limitX = math.max(0.0, screen.width / 2);
    final limitY = math.max(0.0, screen.height / 2);
    return Transform.translate(
      offset: _offset,
      child: Stack(
        children: [
          widget.child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MovableDialog.handleHeight,
            child: MouseRegion(
              key: MovableDialog.handleKey,
              cursor: SystemMouseCursors.move,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) => setState(() {
                  _offset = Offset(
                    (_offset.dx + details.delta.dx).clamp(-limitX, limitX),
                    (_offset.dy + details.delta.dy).clamp(-limitY, limitY),
                  );
                }),
                child: Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
