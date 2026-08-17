#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: deploy_map.sh BUILDING_YAML DRAWING_IMAGE MAP_NAME" >&2
  exit 2
fi

INPUT_YAML="$1"
INPUT_IMAGE="$2"
MAP_NAME="$3"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPLOY_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
# 배포마다 파일이 하나 생긴다. 뿌리에 흘리면 저장소 목록이 로그로 덮여 정작
# 패키지 디렉터리가 안 보인다. 한 곳에 모은다.
LOG_DIR="$ROOT_DIR/log"
DEPLOY_LOG="$LOG_DIR/map-deploy-${DEPLOY_TIMESTAMP}.log"
source "$ROOT_DIR/openrmf/scripts/validate_layout.sh"
validate_robosapiens_layout "$ROOT_DIR"
RMF_WS_DIR="$RMF_WS"
TARGET_DIR="$ROOT_DIR/rmf_maps/$MAP_NAME"
STAGING_DIR="$(mktemp -d "$ROOT_DIR/rmf_maps/.${MAP_NAME}.deploy.XXXXXX")"
RUNTIME_DIR="$ROOT_DIR/openrmf/.runtime"
BACKUP_DIR="$ROOT_DIR/rmf_maps/.backups"
IMAGE_NAME="$(basename "$INPUT_IMAGE")"

# 오래된 배포 로그를 지운다.
#
# 최근 KEEP_LOGS개는 언제나 남긴다. 어제 배포가 왜 틀어졌는지 보려면 실패한 그
# 로그가 남아 있어야 하고, 며칠 만에 한 번 배포하는 날도 있어서 날짜만으로
# 자르면 마지막 기록까지 사라진다. 그 밖의 로그는 하루가 지나면 지운다.
#
# 파일 이름이 곧 시각이라(map-deploy-YYYYMMDD-HHMMSS.log) 이름순 정렬이
# 시간순 정렬이다.
KEEP_LOGS=3
prune_deploy_logs() {
  local paths=() path
  mapfile -t paths < <(
    ls -1 "$LOG_DIR"/map-deploy-*.log 2>/dev/null | sort -r | tail -n +$((KEEP_LOGS + 1))
  )
  for path in "${paths[@]:-}"; do
    [[ -n "$path" && -f "$path" ]] || continue
    # 하루가 지난 것만 지운다. 오늘 여러 번 배포한 기록은 남겨 둔다.
    if [[ -n "$(find "$path" -maxdepth 0 -mmin +1440 2>/dev/null)" ]]; then
      rm -f -- "$path" && echo "오래된 배포 로그 삭제: $(basename "$path")"
    fi
  done
}

mkdir -p "$LOG_DIR"
touch "$DEPLOY_LOG"
exec > >(tee -a "$DEPLOY_LOG") 2>&1
echo "배포 로그: $DEPLOY_LOG"
echo "배포 시작: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "맵 이름: $MAP_NAME"
# 어느 망에 띄우는지 남긴다. 이것이 어긋나면 오류 없이 아무것도 안 통하므로,
# 나중에 로그만 보고도 짚을 수 있어야 한다. 앱이 맵 프로젝트의 값을 넘긴다.
echo "ROS_DOMAIN_ID: ${ROS_DOMAIN_ID:-0}"
# 새 로그를 만든 뒤에 지운다 — 방금 만든 이것이 `최근 3개`의 첫 자리다.
prune_deploy_logs

# 배포가 띄운 Building Map Server 를 내린다.
#
# 지도를 제대로 읽혔는지 확인하려면(6단계) 서버가 떠 있어야 한다. 그래서
# 띄우기는 하는데, **확인이 끝나면 우리 일은 끝난 것이다.** 예전에는 띄운 채로
# 나갔고, 그것이 두 가지를 망가뜨렸다 —
#
#   ① 앱은 맵 디렉터리를 물고 있는 프로세스를 세어 백엔드가 도는지 본다.
#      이 서버의 명령줄에 `<맵 디렉터리>/<맵>.building.yaml` 이 들어 있어서,
#      배포만 하고 아무것도 안 띄웠는데 `백엔드 실행 중` 이 되었다. 그 상태로는
#      확인표가 뒤 단계를 `막힘` 으로 매기고, 백엔드를 띄우려 해도 거절한다.
#
#   ② 백엔드 launch 가 같은 파일로 제 것을 하나 더 띄운다.
#      `/building_map_server` 라는 **같은 이름의 노드가 둘**이 되고
#      `/get_building_map` 을 두 곳이 답한다.
#
# 배포한 지도는 파일로 깔려 있고, 앱은 그 파일을 직접 읽는다. 내려도 잃는 것이
# 없다.
#
# **자식을 먼저 죽인다.** `ros2 run` 은 껍데기이고 실제 노드는 그 자식이다.
# 껍데기만 죽이면 노드가 고아로 살아남는다 — 실측으로 확인했다.
#
# 우리가 띄운 그 pid 만 건드린다. 이름으로 훑으면 백엔드가 돌고 있을 때 그쪽
# 서버까지 죽인다(배포 중에 백엔드가 떠 있을 수 있고, 6단계가 그 경우를 따로
# 알려 준다).
stop_deploy_map_server() {
  local pid_file="$RUNTIME_DIR/building_map_server.pid"
  [[ -f "$pid_file" ]] || return 0
  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
    # 실제로 내려갔는지 본다. 안 죽으면 남은 채로 나가는 것과 같다.
    local waited=0
    while ((waited < 30)) && kill -0 "$pid" 2>/dev/null; do
      sleep 0.1
      waited=$((waited + 1))
    done
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$pid_file"
}

cleanup() {
  local status=$?
  stop_deploy_map_server
  rm -rf "$STAGING_DIR" || true
  echo "배포 종료: $(date '+%Y-%m-%d %H:%M:%S %Z') (exit=$status)"
  return "$status"
}
trap cleanup EXIT

log_step() { echo "[$1/6] $2"; }
fail() { echo "ERROR: $1" >&2; exit 1; }

# 벽을 building.yaml 이 말한 높이로 세운다.
#
# `building_map_generator gazebo` 는 벽을 **늘 2.5m** 로 세운다. 높이가
# `building_map/wall.py` 에 박혀 있고(`h = self.wall_height  # todo: allow
# per-segment height?`), yaml 의 `texture_height` 는 텍스처를 입히는 높이일 뿐
# 기하에는 안 들어간다. 그래서 도면에 0.3m 라고 적어도 Gazebo 에는 사람 키보다
# 높은 벽이 선다.
#
# 생성된 벽 메시(.obj)의 윗면을 우리가 내린다. 시각과 충돌이 같은 메시라
# 라이다가 보는 벽도 같이 낮아진다 — 그림만 낮아지면 아무 소용이 없다.
# 세로 텍스처 좌표도 같은 비로 줄여, 벽 한 장에 무늬가 한 번 입혀지게 한다.
#
# 벽마다 높이가 다르면 어느 메시가 어느 벽인지 알 수 없으므로 건드리지 않는다.
# 앱은 맵 하나에 한 높이만 쓴다.
apply_wall_height() {
  local yaml="$1" models_dir="$2"
  local heights=() height obj current

  mapfile -t heights < <(
    grep -o 'texture_height: \[3, [0-9.]\+\]' "$yaml" |
      sed 's/.*\[3, \([0-9.]\+\)\]/\1/' | sort -u
  )
  if ((${#heights[@]} == 0)); then
    echo "벽 높이: 벽이 없어 건너뜁니다."
    return 0
  fi
  if ((${#heights[@]} > 1)); then
    echo "경고: 벽 높이가 여럿입니다(${heights[*]}). 생성기 기본값 2.5m 로 둡니다." >&2
    return 0
  fi
  height="${heights[0]}"

  local patched=0
  while IFS= read -r -d '' obj; do
    # 지금 몇 미터로 서 있는지 메시에서 직접 읽는다. 생성기의 기본값이 바뀌어도
    # 따라간다. 벽 메시의 z 는 바닥(0)과 윗면 둘뿐이다.
    current="$(LC_ALL=C awk '$1=="v" && $4+0>0 {if ($4+0>m) m=$4+0} END {printf "%.6f", m+0}' "$obj")"
    [[ "$current" == "0.000000" ]] && continue
    LC_ALL=C awk -v h="$height" -v c="$current" '
      $1=="v"  { printf "v %s %s %.4f\n", $2, $3, ($4+0>0 ? h : 0); next }
      $1=="vt" { printf "vt %s %.4f\n", $2, $3*h/c; next }
      { print }
    ' "$obj" >"$obj.tmp" && mv "$obj.tmp" "$obj"
    patched=$((patched + 1))
  done < <(find "$models_dir" -name 'wall_*.obj' -print0)

  if ((patched == 0)); then
    echo "경고: 벽 메시를 찾지 못해 높이를 적용하지 못했습니다: $models_dir" >&2
    return 0
  fi
  echo "벽 높이: ${height}m 로 세웠습니다(메시 ${patched}개)."
}

[[ -f "$INPUT_YAML" ]] || fail "building.yaml 파일을 찾을 수 없습니다: $INPUT_YAML"
[[ -f "$INPUT_IMAGE" ]] || fail "도면 이미지를 찾을 수 없습니다: $INPUT_IMAGE"
[[ -f /opt/ros/jazzy/setup.bash ]] || fail "ROS 2 Jazzy가 설치되어 있지 않습니다."
[[ -f "$RMF_WS_DIR/install/setup.bash" ]] || fail "RMF workspace를 찾을 수 없습니다: $RMF_WS_DIR"

mkdir -p "$RUNTIME_DIR" "$BACKUP_DIR"

log_step 1 "오류 검증 완료"
grep -q '^levels:' "$INPUT_YAML" || fail "YAML에 levels 항목이 없습니다."
grep -q '^name:' "$INPUT_YAML" || fail "YAML에 name 항목이 없습니다."

log_step 2 "building.yaml 및 이미지 준비"
cp "$INPUT_YAML" "$STAGING_DIR/$MAP_NAME.building.yaml"
cp "$INPUT_IMAGE" "$STAGING_DIR/$IMAGE_NAME"

set +u
source /opt/ros/jazzy/setup.bash
source "$RMF_WS_DIR/install/setup.bash"
set -u

log_step 3 "nav graph 및 world 생성"
mkdir -p "$STAGING_DIR/nav_graphs" "$STAGING_DIR/generated_models"
ros2 run rmf_building_map_tools building_map_generator nav \
  "$STAGING_DIR/$MAP_NAME.building.yaml" "$STAGING_DIR/nav_graphs"
ros2 run rmf_building_map_tools building_map_generator gazebo \
  "$STAGING_DIR/$MAP_NAME.building.yaml" \
  "$STAGING_DIR/$MAP_NAME.world" "$STAGING_DIR/generated_models"
[[ -f "$STAGING_DIR/nav_graphs/0.yaml" ]] || fail "nav_graphs/0.yaml이 생성되지 않았습니다."
[[ -f "$STAGING_DIR/$MAP_NAME.world" ]] || fail "world 파일이 생성되지 않았습니다."

apply_wall_height "$STAGING_DIR/$MAP_NAME.building.yaml" "$STAGING_DIR/generated_models"

log_step 4 "RMF 맵 디렉터리에 설치"
if [[ -d "$TARGET_DIR" ]]; then
  BACKUP_PATH="$BACKUP_DIR/${MAP_NAME}-$(date +%Y%m%d-%H%M%S)"
  mv "$TARGET_DIR" "$BACKUP_PATH"
  echo "기존 맵 백업: $BACKUP_PATH"
fi
mv "$STAGING_DIR" "$TARGET_DIR"
# WorkCell policy는 지도 생성물이 아니라 사용자가 등록한 운영 자산이다.
# 맵 재배포 때 staging 디렉터리로 통째로 교체하더라도 함께 보존한다.
if [[ -n "${BACKUP_PATH:-}" && -d "$BACKUP_PATH/policies" ]]; then
  cp -a "$BACKUP_PATH/policies" "$TARGET_DIR/policies"
  echo "WorkCell policy 보존: $TARGET_DIR/policies"
fi
if [[ -n "${BACKUP_PATH:-}" && -f "$BACKUP_PATH/policy_bindings.json" ]]; then
  cp -a "$BACKUP_PATH/policy_bindings.json" "$TARGET_DIR/policy_bindings.json"
  echo "WorkCell policy 연결 보존: $TARGET_DIR/policy_bindings.json"
fi
STAGING_DIR="$(mktemp -d "$ROOT_DIR/rmf_maps/.${MAP_NAME}.cleanup.XXXXXX")"

stop_pid_file() {
  local pid_file="$1"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file")"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      for _ in {1..20}; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
      done
    fi
    rm -f "$pid_file"
  fi
}

stop_matching_processes() {
  local pattern="$1"
  mapfile -t pids < <(pgrep -u "$(id -u)" -f "$pattern" 2>/dev/null || true)
  if ((${#pids[@]} > 0)); then
    kill -TERM "${pids[@]}" 2>/dev/null || true
    for _ in {1..30}; do
      local running=0
      for pid in "${pids[@]}"; do
        kill -0 "$pid" 2>/dev/null && running=1
      done
      [[ "$running" == "0" ]] && break
      sleep 0.1
    done
  fi
}

log_step 5 "Building Map Server 재시작"
stop_pid_file "$RUNTIME_DIR/building_map_server.pid"
stop_matching_processes '/rmf_building_map_tools/building_map_server'
nohup ros2 run rmf_building_map_tools building_map_server \
  "$TARGET_DIR/$MAP_NAME.building.yaml" \
  >"$RUNTIME_DIR/building_map_server.log" 2>&1 &
echo $! >"$RUNTIME_DIR/building_map_server.pid"

# 플릿은 여기서 띄우지 않는다.
#
# 예전에는 이 자리에서 `rmf_demos_fleet_adapter` 를 rmf_demos 의 **office 데모
# 설정**(tinyRobot_config.yaml)으로 띄웠다. 이 프로젝트의 로봇도, 이 맵의
# 설정도 아니다. 그리고 매번 죽었다 —
#
#   AssertionError: Failed to parse config file [.../office/tinyRobot_config.yaml]
#
# 그 위에 이 어댑터는 slotcar 전용이다. 토픽으로 도는 핑키에게는 상대가 없어서,
# 설령 떴어도 배차만 받고 로봇은 가만히 있는다.
#
# 플릿을 띄우는 것은 실행 스크립트(run_<맵>.sh)의 일이다. 배포는 지도를 만들어
# 깔고 map server 에 물리는 데까지다. 둘을 한 곳에서 하려다 남의 데모를 띄웠다.

log_step 6 "새 지도 수신 확인"
# 시계로 자른다. 예전에는 `30번 × sleep 0.5` 로 15초를 기다린다고 여겼는데,
# 노드가 수백 개인 그래프에서는 `ros2 service list` 한 번이 3~5초라 실제로는
# 100초가 넘게 걸렸다. "배포가 오래 걸린다" 가 그것이었다.
#
# 한 번에 3초를 쓰므로(아래 `--spin-time`) 25초로는 서너 번밖에 못 돈다.
WAIT_SECS="${MAP_READY_WAIT:-40}"
DEADLINE=$((SECONDS + WAIT_SECS))
while ((SECONDS < DEADLINE)); do
  # 앱에서 ROS_DOMAIN_ID를 바꿔도 기존 ros2 daemon은 먼저 시작된 도메인의
  # 그래프를 계속 들고 있을 수 있다. 방금 같은 셸에서 띄운 서버를 확인하는
  # 단계이므로 daemon 캐시를 우회하고 현재 도메인을 직접 탐색한다.
  #
  # 탐색에 3초를 준다. `--no-daemon` 은 캐시가 없어 그때그때 DDS 를 훑는데,
  # 1초로는 **멀쩡히 떠 있는 서버를 절반쯤 놓친다** — 실측(2026-08-15, 서버가
  # `ready to serve map` 을 찍은 뒤): spin-time 1 → 5번 중 2번, 3 → 5번 중
  # 5번, 5 → 5번 중 5번. 그래서 지도는 다 올라갔는데 배포만 실패로 끝났다.
  if ros2 service list --no-daemon --spin-time 3 2>/dev/null | grep -qx '/get_building_map'; then
    MAP_SERVER_PID="$(cat "$RUNTIME_DIR/building_map_server.pid")"
    kill -0 "$MAP_SERVER_PID" 2>/dev/null || fail "Building Map Server가 종료되었습니다."
    echo "DEPLOYED_MAP_DIR=$TARGET_DIR"
    echo "BUILDING_MAP_SERVER_LOG=$RUNTIME_DIR/building_map_server.log"
    echo "DEPLOY_LOG=$DEPLOY_LOG"
    # 이미 떠 있는 것은 뜰 때 읽은 nav graph 를 그대로 들고 있다. 지도만
    # 바꾸면 로봇은 옛 지도로 다닌다 — 오류는 안 난다.
    if pgrep -u "$(id -u)" -f "gz sim.*$MAP_NAME.world" >/dev/null 2>&1; then
      echo ""
      echo "이 맵으로 이미 떠 있는 것이 있습니다. 새 지도로 다니게 하려면"
      echo "stop_$MAP_NAME.sh 로 내리고 run_$MAP_NAME.sh 로 다시 띄우세요."
      echo "지금 도는 것은 뜰 때 읽은 nav graph 를 그대로 씁니다."
    fi
    # 확인이 끝났으니 우리가 띄운 지도 서버는 내린다. 나가면서 trap 이
    # 부르지만, 왜 없어졌는지는 여기서 밝혀 둔다 — 배포 직후에 그 서버를
    # 찾다가 "왜 없지" 하지 않도록.
    echo ""
    echo "배포용 Building Map Server 를 내립니다. 지도는 파일로 깔려 있고,"
    echo "백엔드를 띄우면 run_$MAP_NAME.sh 가 제 것을 다시 띄웁니다."
    echo "배포가 완료되었습니다: $MAP_NAME"
    exit 0
  fi
  sleep 0.5
done

# 도메인이 어긋난 것을 먼저 짚는다.
#
# 서로 다른 도메인은 **아무 오류도 안 내면서** 서로를 못 본다. 그래서 증상이
# "지도가 안 올라간다" 로만 보인다. 실제로 앱은 비대화형 셸로 이 스크립트를
# 돌려 ~/.bashrc 의 export 를 못 읽었고, 터미널의 시스템이 22번에 있는 동안
# 이 스크립트만 0번에서 혼자 돌았다. 방금 우리가 띄운 노드조차 안 보이면
# 그 경우다.
# 여기도 3초를 준다. 1초로 훑고 "노드가 없다" 고 하면, 멀쩡한 도메인을 두고
# 도메인이 어긋났다고 엉뚱한 곳을 짚게 된다.
if ! ros2 node list --no-daemon --spin-time 3 2>/dev/null | grep -q .; then
  echo "" >&2
  echo "ROS 도메인 ${ROS_DOMAIN_ID:-0} 에 노드가 하나도 없습니다." >&2
  echo "방금 띄운 building_map_server 조차 안 보인다면 도메인이 어긋난 것입니다." >&2
  echo "" >&2
  echo "터미널에서 확인:  echo \$ROS_DOMAIN_ID" >&2
  echo "맞추는 곳:        앱 · 맵 관리 · [ROS 도메인] 단추" >&2
  echo "" >&2
fi
tail -n 30 "$RUNTIME_DIR/building_map_server.log" >&2 || true
fail "새 Building Map Server의 /get_building_map 서비스를 ${WAIT_SECS}초 안에 확인하지 못했습니다."
