#!/usr/bin/env bash
# rmf_control_ui 를 릴리스로 띄운다.
#
# 개발 중에는 `flutter run`(디버그)이 필요하다 — hot reload 가 거기에만 있다.
# 그런데 디버그 빌드는 Dart 를 JIT 로 돌리고 `--enable-asserts` 와
# `--track-widget-creation` 을 켠다. 위젯 하나하나에 생성 위치가 달리고
# 프레임마다 검사가 도는 셈이라, 실제로 쓰기에는 눈에 띄게 무겁다.
#
# 실제로 쓸 때는 이 스크립트로 띄운다.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE="$APP_DIR/build/linux/x64/release/bundle/rmf_control_ui"

cd "$APP_DIR"

# 소스가 빌드보다 새로우면 다시 빌드한다. 고쳐 놓고 옛 바이너리를 띄우면
# 왜 안 바뀌는지 한참 찾는다.
needs_build=0
if [[ ! -x "$BUNDLE" ]]; then
  needs_build=1
  echo "릴리스 빌드가 없습니다. 먼저 빌드합니다."
elif [[ -n "$(find lib pubspec.yaml -type f -newer "$BUNDLE" -print -quit 2>/dev/null)" ]]; then
  needs_build=1
  echo "소스가 빌드보다 새롭습니다. 다시 빌드합니다."
fi

if [[ "$needs_build" == "1" ]]; then
  flutter build linux --release
fi

echo "띄웁니다: $BUNDLE"
exec "$BUNDLE" "$@"
