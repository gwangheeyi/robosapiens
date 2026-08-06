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
DEPLOY_LOG="$ROOT_DIR/map-deploy-${DEPLOY_TIMESTAMP}.log"
RMF_WS_DIR="${RMF_WS:-$HOME/rmf_ws}"
TARGET_DIR="$ROOT_DIR/rmf_maps/$MAP_NAME"
STAGING_DIR="$(mktemp -d "$ROOT_DIR/rmf_maps/.${MAP_NAME}.deploy.XXXXXX")"
RUNTIME_DIR="$ROOT_DIR/openrmf/.runtime"
BACKUP_DIR="$ROOT_DIR/rmf_maps/.backups"
IMAGE_NAME="$(basename "$INPUT_IMAGE")"
SERVER_URI="${RMF_SERVER_URI:-ws://127.0.0.1:8000/_internal}"

touch "$DEPLOY_LOG"
exec > >(tee -a "$DEPLOY_LOG") 2>&1
echo "배포 로그: $DEPLOY_LOG"
echo "배포 시작: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "맵 이름: $MAP_NAME"

cleanup() {
  local status=$?
  rm -rf "$STAGING_DIR" || true
  echo "배포 종료: $(date '+%Y-%m-%d %H:%M:%S %Z') (exit=$status)"
  return "$status"
}
trap cleanup EXIT

log_step() { echo "[$1/7] $2"; }
fail() { echo "ERROR: $1" >&2; exit 1; }

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

log_step 4 "RMF 맵 디렉터리에 설치"
if [[ -d "$TARGET_DIR" ]]; then
  BACKUP_PATH="$BACKUP_DIR/${MAP_NAME}-$(date +%Y%m%d-%H%M%S)"
  mv "$TARGET_DIR" "$BACKUP_PATH"
  echo "기존 맵 백업: $BACKUP_PATH"
fi
mv "$STAGING_DIR" "$TARGET_DIR"
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

log_step 6 "Fleet Adapter 재시작"
FLEET_CONFIG="${RMF_FLEET_CONFIG:-$RMF_WS_DIR/install/rmf_demos/share/rmf_demos/config/office/tinyRobot_config.yaml}"
[[ -f "$FLEET_CONFIG" ]] || fail "Fleet 설정 파일을 찾을 수 없습니다: $FLEET_CONFIG"
stop_pid_file "$RUNTIME_DIR/fleet_adapter.pid"
stop_matching_processes '/rmf_demos_fleet_adapter/fleet_manager'
stop_matching_processes '/rmf_demos_fleet_adapter/fleet_adapter'
nohup ros2 launch rmf_demos_fleet_adapter fleet_adapter.launch.xml \
  use_sim_time:="${RMF_USE_SIM_TIME:-true}" \
  nav_graph_file:="$TARGET_DIR/nav_graphs/0.yaml" \
  config_file:="$FLEET_CONFIG" server_uri:="$SERVER_URI" \
  >"$RUNTIME_DIR/fleet_adapter.log" 2>&1 &
echo $! >"$RUNTIME_DIR/fleet_adapter.pid"

log_step 7 "새 지도 수신 확인"
for _ in {1..30}; do
  if ros2 service list 2>/dev/null | grep -qx '/get_building_map'; then
    MAP_SERVER_PID="$(cat "$RUNTIME_DIR/building_map_server.pid")"
    FLEET_ADAPTER_PID="$(cat "$RUNTIME_DIR/fleet_adapter.pid")"
    kill -0 "$MAP_SERVER_PID" 2>/dev/null || fail "Building Map Server가 종료되었습니다."
    kill -0 "$FLEET_ADAPTER_PID" 2>/dev/null || {
      tail -n 30 "$RUNTIME_DIR/fleet_adapter.log" >&2 || true
      fail "Fleet Adapter가 종료되었습니다."
    }
    echo "DEPLOYED_MAP_DIR=$TARGET_DIR"
    echo "BUILDING_MAP_SERVER_LOG=$RUNTIME_DIR/building_map_server.log"
    echo "FLEET_ADAPTER_LOG=$RUNTIME_DIR/fleet_adapter.log"
    echo "DEPLOY_LOG=$DEPLOY_LOG"
    echo "배포가 완료되었습니다: $MAP_NAME"
    exit 0
  fi
  sleep 0.5
done

tail -n 30 "$RUNTIME_DIR/building_map_server.log" >&2 || true
fail "새 Building Map Server의 /get_building_map 서비스를 확인하지 못했습니다."
