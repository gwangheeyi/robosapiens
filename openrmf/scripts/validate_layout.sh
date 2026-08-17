#!/usr/bin/env bash

# source 해서 쓰는 RoboSapiens 고정 디렉터리 검사기.
# 실패하면 호출한 실행 스크립트도 즉시 멈춘다.
validate_robosapiens_layout() {
  local root="$1"
  local home_root="${HOME:?HOME 환경 변수가 필요합니다}/robosapiens"
  local expected_rmf="$home_root/rmf_ws"

  if [[ "$root" != "$home_root" ]]; then
    echo "잘못된 RoboSapiens 루트: $root" >&2
    echo "프로그램 전체를 다음 위치에 두세요: $home_root" >&2
    return 1
  fi
  if [[ "${RMF_WS:-$expected_rmf}" != "$expected_rmf" ]]; then
    echo "외부 RMF workspace는 지원하지 않습니다: ${RMF_WS:-}" >&2
    echo "실제 디렉터리를 다음 위치로 옮기세요: $expected_rmf" >&2
    return 1
  fi

  local path marker
  while IFS='|' read -r path marker; do
    if [[ -L "$path" ]]; then
      echo "심볼릭 링크는 지원하지 않습니다: $path" >&2
      echo "원본 디렉터리를 이 위치로 옮겨주세요." >&2
      return 1
    fi
    if [[ ! -d "$path" ]]; then
      echo "필수 디렉터리가 없습니다: $path" >&2
      return 1
    fi
    if [[ -n "$marker" && ! -f "$path/$marker" ]]; then
      echo "디렉터리 구조가 올바르지 않습니다: $path/$marker 없음" >&2
      return 1
    fi
  done <<EOF
$expected_rmf|install/setup.bash
$home_root/robot_model/pinky_pro|pinky_description/package.xml
$home_root/robot_model/open_manipulator|src/open_manipulator/open_manipulator_description/package.xml
EOF

  RMF_WS="$expected_rmf"
  export RMF_WS
}
