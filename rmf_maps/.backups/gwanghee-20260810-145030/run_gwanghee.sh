#!/usr/bin/env bash
# gwanghee 프로젝트 실행.
# rmf_control_ui 가 맵 프로젝트에서 생성했다. 손으로 고치면 다음 저장 때
# 덮어써진다.
#
# 순서가 중요하다. Gazebo 가 먼저 떠야 /clock 이 나오고, 그래야 use_sim_time 을
# 쓰는 RMF 노드가 시간을 맞춘다. 반대로 하면 RMF 가 시간이 멈춘 줄 알고 멈춰
# 있는다.
set -euo pipefail

MAP_DIR="${MAP_DIR:-/home/gyi/robosapiens/rmf_maps/gwanghee}"
ROS_SETUP="${ROS_SETUP:-/opt/ros/jazzy/setup.bash}"
RMF_WS="${RMF_WS:-$HOME/rmf_ws}"
PINKY_WS="${PINKY_WS:-$HOME/robosapiens/pinky_pro}"
OMX_WS="${OMX_WS:-$HOME/robosapiens/open_manipulator}"

# 이 프로젝트의 로봇이 실제로 쓰는 패키지. 등록된 로봇에서 뽑았다.
REQUIRED_PACKAGES="rmf_demos rmf_demos_fleet_adapter rmf_building_map_tools ros_gz_sim pinky_description robot_state_publisher joint_state_publisher open_manipulator_description"
HEADLESS="${HEADLESS:-true}"

BUILDING_YAML="$MAP_DIR/gwanghee.building.yaml"
NAV_GRAPH="$MAP_DIR/nav_graphs/0.yaml"

if [[ ! -f "$BUILDING_YAML" ]]; then
  echo "없는 파일: $BUILDING_YAML" >&2
  echo "앱의 맵 관리에서 배포하기와 RMF 설정 내보내기를 먼저 하세요." >&2
  exit 1
fi

set +u
# shellcheck disable=SC1090
source "$ROS_SETUP"
[[ -f "$RMF_WS/install/setup.bash" ]] && source "$RMF_WS/install/setup.bash"
[[ -f "$PINKY_WS/install/setup.bash" ]] && source "$PINKY_WS/install/setup.bash"
[[ -f "$OMX_WS/install/setup.bash" ]] && source "$OMX_WS/install/setup.bash"
set -u

# nav_graphs/0.yaml 은 building.yaml 에서 파생된다. 맵에서 Waypoint 나 Lane 을
# 고쳐도 이 파일이 그대로면 RMF 는 옛날 지도를 본다. 없는 것이 아니라 낡은
# 것이라 오류가 나지 않는다 — 충전 Waypoint 를 방금 이었는데도 RMF 가 "충전
# 지점을 못 찾겠다"고 하는 것이 이 경우다. 그래서 매번 다시 만든다.
if [[ ! -f "$NAV_GRAPH" || "$BUILDING_YAML" -nt "$NAV_GRAPH" ]]; then
  echo "nav_graphs/0.yaml 을 building.yaml 에서 다시 만든다."
  mkdir -p "$MAP_DIR/nav_graphs"
  if ! ros2 run rmf_building_map_tools building_map_generator nav \
      "$BUILDING_YAML" "$MAP_DIR/nav_graphs"; then
    echo "nav graph 생성 실패. rmf_building_map_tools 가 있는지 보세요." >&2
    exit 1
  fi
fi

if [[ ! -f "$NAV_GRAPH" ]]; then
  echo "없는 파일: $NAV_GRAPH" >&2
  exit 1
fi

# 모든 출력을 로그 파일로 보낸다.
#
# 앱이 이 스크립트를 파이프에 물려 띄우면, 그 파이프를 읽는 쪽이 없을 때
# 64KB 가 차는 순간 Gazebo 가 write 에서 영원히 멈춘다. 물리가 돌지 않아
# 모델도 안 올라오고 토픽에 값도 오지 않는다. 파일로 보내면 막힐 일이 없고,
# 무슨 일이 있었는지 나중에 볼 수도 있다.
#
# 다만 그대로 두면 감당이 안 된다. Gazebo 의 ODE 가 메시끼리 닿을 때마다
# 같은 경고 한 줄을 물리 스텝마다 찍어, 시간당 1.8GB 씩 찼다. 그래서 거른다.
#
#   1. launch 접두사만 있고 내용이 없는 줄은 버린다.
#   2. 바로 앞과 똑같은 줄은 세기만 하고, 다른 줄이 오면 "몇 번 더" 로 접는다.
#   3. 그래도 넘치면 한 번 밀어 두고 새로 쓴다 (최대 2 배까지만 남는다).
#
# 에러만 남기지는 않는다. 지금까지 원인을 알려 준 것은 대부분 ERROR 가 아니라
# 뜨는 순서였다 — Gazebo 가 먼저인지, /clock 이 나왔는지, 다리가 어느 토픽을
# 걸었는지. 대신 ERROR·경고·역추적만 따로 모은 파일을 하나 더 쓴다.
LOG_FILE="$MAP_DIR/gwanghee.log"
ERR_FILE="$MAP_DIR/gwanghee.err.log"
LOG_MAX_MB="${LOG_MAX_MB:-200}"
: > "$ERR_FILE"

# 이 awk 는 파이프를 쉬지 않고 읽는다. 읽는 쪽이 있어야 위의 교착이 안 난다.
exec > >(exec awk -v out="$LOG_FILE" -v err="$ERR_FILE" -v maxmb="$LOG_MAX_MB" '
function put(text) {
  print text > out
  fflush(out)
  bytes += length(text) + 1
  if (bytes > maxmb * 1048576) {
    close(out)
    system("mv -f \"" out "\" \"" out ".1\" 2>/dev/null")
    bytes = 0
    print "=== 로그가 " maxmb "MB 를 넘어 " out ".1 로 밀었다 ===" > out
    fflush(out)
  }
}
function fold() {
  if (dup > 0) { put("  ↑ 같은 줄 " dup "번 더") ; dup = 0 }
}
{
  if ($0 ~ /^\[[^]]+\] *$/) next
  if ($0 == last) {
    dup++
    # 오래 접혀 있으면 로그가 멎은 것처럼 보인다. 가끔 살아 있다고 알린다.
    if (dup % 100000 == 0) put("  ↑ 같은 줄 " dup "번째, 계속 접는 중")
    next
  }
  fold()
  put($0)
  last = $0
  if ($0 ~ /ERROR|error:|Error|Traceback|Warning|WARN|없는 파일|실패/) {
    print $0 > err
    fflush(err)
  }
}
END { fold() }
') 2>&1
echo "=== $(date '+%Y-%m-%d %H:%M:%S') gwanghee 실행 ==="

# 자기 프로세스 그룹 번호를 남긴다. 중지 스크립트가 이 그룹을 통째로 끊는다.
# 앱이 detached 로 띄우면 이 셸의 PID 는 그룹 리더가 아니므로, PID 가 아니라
# 실제 PGID 를 적어야 한다.
PGID_FILE="$MAP_DIR/.gwanghee.pgid"
ps -o pgid= -p $$ | tr -d ' ' > "$PGID_FILE"

cleanup() {
  echo "정리 중..."
  kill $(jobs -p) 2>/dev/null || true
  # PGID 파일은 지우지 않는다.
  #
  # 이 셸이 먼저 끝나고 자식이 살아남는 일이 있다. 그때 파일까지 지우면
  # 그 그룹을 끊을 손잡이가 사라져, 중지 스크립트도 다음 실행의 남은 항목
  # 검사도 그 프로세스를 영영 못 찾는다. 파일은 중지 스크립트가 지운다.
}
trap cleanup EXIT INT TERM

# 필요한 패키지가 없으면 launch 가 통째로 예외를 내며 멈춘다. 그러면 다른
# 로봇까지 안 뜨는데, 화면에는 찾아본 경로 목록만 잔뜩 나와 원인을 알기 어렵다.
missing=()
for pkg in $REQUIRED_PACKAGES; do
  ros2 pkg prefix "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done
if ((${#missing[@]} > 0)); then
  echo "없는 ROS 패키지: ${missing[*]}" >&2
  echo "" >&2
  echo "이 프로젝트의 로봇을 띄우려면 아래를 빌드하고 다시 실행하세요." >&2
  for pkg in "${missing[@]}"; do
    case "$pkg" in
      pinky_*) echo "  $pkg  ->  cd $PINKY_WS && colcon build" >&2 ;;
      open_manipulator_*) echo "  $pkg  ->  cd $OMX_WS && colcon build" >&2 ;;
      *) echo "  $pkg" >&2 ;;
    esac
  done
  exit 1
fi

# 월드에 센서 시스템을 채운다.
#
# 월드는 rmf_building_map_tools 가 제 템플릿(gz_world.sdf)에서 만드는데, 거기에는
# Physics · UserCommands · SceneBroadcaster 셋뿐이다. RMF 의 시범 로봇(slotcar)은
# 라이다를 안 쓰므로 필요가 없었다.
#
# 우리 핑키는 gpu_lidar · camera · imu 를 단다. 센서 시스템이 없으면 이 센서들이
# **하나도 발행하지 않는다.** 토픽 이름은 보이는데 데이터가 영영 안 온다. 라이다가
# 없으면 AMCL 도 Nav2 도 불가능하다.
#
# 배포할 때마다 월드가 다시 만들어지므로 여기서 매번 채운다. 이미 있으면 넘어간다.
ensure_world_sensors() {
  local world="$1"
  [ -f "$world" ] || return 0
  python3 - "$world" <<'PYTHON'
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as handle:
    world = handle.read()

# 이름으로 찾는다. filename 은 앞에 lib 이 붙기도 하고 안 붙기도 한다.
wanted = [
    ('gz::sim::systems::Sensors',
     '    <plugin filename="gz-sim-sensors-system"\n'
     '            name="gz::sim::systems::Sensors">\n'
     '      <render_engine>ogre2</render_engine>\n'
     '    </plugin>\n'),
    ('gz::sim::systems::Imu',
     '    <plugin filename="gz-sim-imu-system"\n'
     '            name="gz::sim::systems::Imu">\n'
     '    </plugin>\n'),
]
added = [name for name, _ in wanted if name not in world]
if not added:
    print('월드에 센서 시스템이 이미 있습니다.')
    sys.exit(0)

block = ''.join(snippet for name, snippet in wanted if name not in world)
# <world ...> 바로 다음에 넣는다. 시스템 플러그인은 월드의 자식이어야 한다.
marker = world.index('>', world.index('<world')) + 1
with open(path, 'w', encoding='utf-8') as handle:
    handle.write(world[:marker] + '\n' + block + world[marker:])
print('월드에 센서 시스템을 넣었습니다: ' + ', '.join(added))
PYTHON
}
ensure_world_sensors "$MAP_DIR/gwanghee.world"

echo "[1/3] Gazebo bringup"
ros2 launch "$MAP_DIR/gwanghee_bringup.launch.xml" headless:="$HEADLESS" &
sleep 12

echo "[2/3] Open-RMF"
ros2 launch "$MAP_DIR/gwanghee.launch.xml" headless:="$HEADLESS" &
sleep 12

# Nav2 와 RMF↔Nav2 어댑터. 이것이 없으면 RMF 가 배차해도 로봇이 안 움직인다 —
# /<로봇>/cmd_vel 에 발행하는 것이 아무것도 없기 때문이다.
#
# RMF core 다음이라야 한다. 어댑터는 뜨자마자 schedule node 를 찾는다.
echo "[3/3] Nav2 와 RMF 어댑터"
ros2 launch "$MAP_DIR/gwanghee_nav2.launch.xml"
