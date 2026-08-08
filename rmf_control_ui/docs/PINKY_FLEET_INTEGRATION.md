# Pinky 가상 로봇 · Fleet Adapter 연동

## 1. 문서 목적

`rmf_control_ui`의 로봇을 앱 안에서 계산하는 **Mock 주행**에서, 실제 ROS 토픽을
주고받는 **Gazebo 가상 Pinky**로 옮기고 Open-RMF Fleet Adapter로 관제하는
과정을 기록합니다.

작업이 여러 날에 걸치고 PC를 옮겨 가며 이어지므로, 어디까지 됐고 무엇이
남았는지 이 문서만 보면 알 수 있어야 합니다.

## 2. 전체 그림

```text
Gazebo Pinky ──odom/scan──▶ [Nav2] ──▶ [RMF Fleet Adapter] ──▶ RMF core
   ▲                                          │              (schedule/traffic)
   └──────────cmd_vel─────────────────────────┘                     │
                                                            rmf-web ──▶ rmf_control_ui
```

## 3. 진행 상황

| 단계 | 내용 | 상태 |
|---|---|---|
| 1 | `pinky_pro` 빌드 · Gazebo 가상 Pinky 기동 · `/odom` `/cmd_vel` 확인 | **완료** |
| 2 | RMF core(schedule node, building map server)를 gwanghee 맵으로 기동 | 예정 |
| 3 | Pinky용 Fleet Adapter 설정 작성 · gwanghee 통합 launch | **설정 생성·저장 완료**, launch 남음 |
| 4 | `rmf_control_ui`를 rmf-web에 연결해 `실제 로봇` 모드에서 fleet state 표시 | 예정 |

## 4. 사전 준비

### 4.1 저장소에 없는 것

다음 두 디렉터리는 **벤더 패키지라 이 저장소에 포함하지 않습니다.** 각 상위
저장소에서 받아 프로젝트 루트에 둡니다.

| 디렉터리 | 내용 |
|---|---|
| `pinky_pro/` | Pinky 로봇 ROS 2 패키지 (bringup, description, gz_sim, navigation, 센서·LED) |
| `open_manipulator/` | ROBOTIS OpenMANIPULATOR 패키지 (bringup, description, moveit_config, 컨트롤러) |

`rmf_maps/<맵이름>/` 아래의 배포 산출물(`building.yaml`, `nav_graphs/0.yaml`,
`*.world`, `generated_models/`)도 저장소에 넣지 않습니다. 앱의 `맵 관리`에서
`배포하기`를 눌러 다시 만듭니다. **`nav_graphs/0.yaml`은 Fleet Adapter에
반드시 필요하므로, 새 PC에서는 배포를 먼저 한 번 돌려야 합니다.**

### 4.2 환경

- Ubuntu 24.04 · ROS 2 Jazzy
- 빌드된 Open-RMF workspace: 기본값 `$HOME/rmf_ws`

확인:

```bash
source /opt/ros/jazzy/setup.bash
source "$HOME/rmf_ws/install/setup.bash"
ros2 pkg prefix rmf_fleet_adapter
ros2 pkg prefix ros_gz_sim
```

### 4.3 추가로 설치해야 하는 패키지

`pinky_pro` 빌드와 Nav2 연동에 필요합니다. 기본 ROS 설치에는 없습니다.

```bash
sudo apt-get install -y \
  ros-jazzy-gz-ros2-control \
  ros-jazzy-joint-state-publisher \
  ros-jazzy-navigation2 \
  ros-jazzy-nav2-bringup
```

`gz_ros2_control`은 `pinky_gz_sim`의 **빌드 필수 의존**입니다. 없으면
`Could not find a package configuration file provided by "gz_ros2_control"`로
빌드가 멈춥니다.

확인된 버전(2026-08 기준):

```text
ros-jazzy-gz-ros2-control        1.2.19-1noble
ros-jazzy-joint-state-publisher  2.4.1-1noble
ros-jazzy-navigation2            1.3.12-1noble
ros-jazzy-nav2-bringup           1.3.12-1noble
```

## 5. 1단계 — 가상 Pinky 기동과 토픽 확인

### 5.1 빌드

```bash
cd ~/robosapiens/pinky_pro
source /opt/ros/jazzy/setup.bash
colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release
```

10개 패키지가 모두 빌드되어야 합니다. `pinky_gz_sim`에서 `parameter_traits`
관련 경고가 나오지만 빌드는 성공합니다.

### 5.2 실행

화면으로 보려면 원래 launch를 씁니다.

```bash
cd ~/robosapiens/pinky_pro
source /opt/ros/jazzy/setup.bash && source install/setup.bash
ros2 launch pinky_gz_sim launch_sim.launch.xml
```

화면이 없는 환경(SSH, 원격 세션)에서는 GUI를 뺀 launch를 씁니다. 토픽 확인에는
서버만으로 충분합니다.

```bash
ros2 launch pinky_gz_sim launch_sim_headless.launch.xml
```

`launch_sim_headless.launch.xml`은 원본에서 `gz_args='-g'`로 GUI를 띄우는
include와 카메라 image_bridge만 뺀 것입니다.

### 5.3 검증

토픽이 올라왔는지:

```bash
ros2 topic list
```

`/odom` `/scan` `/cmd_vel` `/joint_states` `/tf` `/clock` `/camera/*`가 보여야
합니다.

위치가 실제로 나오는지:

```bash
ros2 topic hz /odom          # 약 50Hz
ros2 topic echo /odom --once
```

명령으로 움직이는지:

```bash
ros2 topic echo /odom --once --field pose.pose.position.x
ros2 topic pub -r 10 /cmd_vel geometry_msgs/msg/Twist \
  '{linear: {x: 0.25}, angular: {z: 0.0}}'   # 3초쯤 뒤 Ctrl-C
ros2 topic echo /odom --once --field pose.pose.position.x
```

### 5.4 확인된 결과

```text
빌드      10개 패키지 성공
/odom     50Hz 발행 (min 0.020s, max 0.026s)
/cmd_vel  전진 3초 → x: 0.000 → 1.287 m 이동
```

토픽은 `pinky_gz_sim/params/pinky_bridge.yaml`이 Gazebo와 ROS 사이를 잇습니다.
로봇 URDF(`pinky_description/urdf/robot.urdf.xacro`)에 들어 있는
`gz-sim-diff-drive-system` 플러그인이 `cmd_vel`을 받아 `odom`을 냅니다.

### 5.5 남은 차이

- 기본 월드가 `pinky_factory.world`입니다. 최종적으로는 배포한
  `rmf_maps/<맵이름>/<맵이름>.world`를 써야 합니다.
- 로봇이 1대입니다. `robo_pinky/src/robo_pinky_sim/config/fleet.yaml`에 정의된
  PK-01, PK-02, PK-03을 각각 네임스페이스로 띄워야 합니다.

두 가지 모두 3단계에서 통합 launch를 만들며 함께 처리합니다.

## 6. RMF 설정은 프로젝트마다 만들어진다

맵이 다르면 Waypoint 이름도 충전소 위치도 다릅니다. 전역 `fleet.yaml` 하나를
돌려 쓰면 프로젝트를 바꾸는 순간 spawn 좌표와 charger 이름이 어긋납니다.
그래서 플릿 설정과 생성된 설정 파일을 **맵 프로젝트에 묶어 MySQL에 보관**합니다.

### 6.1 저장 구조 (schema v6)

| 표 | 내용 |
|---|---|
| `map_project_fleets` | 프로젝트당 1행. 플릿 이름과 `rmf_fleet` 블록에 대응하는 설정(JSON) |
| `map_project_robots` | 프로젝트별 로봇. id, 표시 이름, 모델, `gz_name`, 구획, charger Waypoint, spawn 좌표 |
| `map_project_files` | 그 프로젝트에서 만들어진 설정 파일 전부 |

`map_project_files`가 핵심입니다. `building.yaml`, fleet adapter 설정, Gazebo
spawn 목록, launch를 한자리에 모아 두므로 **프로젝트 하나만 열면 배포와 실행에
필요한 것이 전부 보입니다.** 파일이 디스크 여기저기 흩어져 있으면 어느 것이 이
맵의 것인지 알 수 없습니다.

저장할 때마다 다시 만들어 넣으므로 맵과 어긋나지 않고, 지운 파일이 남아 도는
일도 없습니다. 프로젝트를 지우면 설정도 함께 사라집니다(외래 키 CASCADE).

### 6.2 프로필 반경은 로봇 안전 기준에서 가져온다

fleet adapter의 `profile.footprint`와 `vicinity`는 맵 관리에서 이미 입력한
로봇 안전 기준으로 계산합니다.

```text
footprint = 로봇 폭 / 2
vicinity  = 로봇 폭 / 2 + 위치 오차 여유
```

같은 값을 두 곳에 따로 적으면 어긋납니다. 폭 0.2m · 여유 0.05m인 작은 로봇이면
`footprint: 0.100`, `vicinity: 0.150`이 됩니다.

### 6.3 만들어지는 파일

| 파일 | kind | 용도 |
|---|---|---|
| `<맵이름>.building.yaml` | `building` | Open-RMF 건물 맵 |
| `<플릿이름>_config.yaml` | `fleet_adapter` | fleet adapter 설정. `robots[].charger`에 충전 Waypoint 이름이 들어감 |
| `fleet.yaml` | `fleet_sim` | Gazebo에 띄울 로봇 목록. spawn 좌표는 맵 Waypoint에서 가져옴 |

`nav_graphs/0.yaml`은 배포 스크립트가 `building.yaml`에서 만듭니다.

### 6.4 앱에서 설정하기

맵 관리 상단 `RMF 설정`에서 두 가지를 봅니다.

**로봇 탭** — 이 프로젝트의 로봇 목록입니다. `충전 Waypoint에서 만들기`를 누르면
맵의 충전 카테고리 Waypoint마다 로봇 한 대를 만들고, spawn 좌표와 charger를
한꺼번에 채웁니다. 로봇을 손으로 하나씩 넣는 대신 맵에서 끌어옵니다.

개별 추가·수정도 됩니다. 충전 Waypoint는 맵에 있는 것 중에서 고르므로 이름을
잘못 적을 일이 없습니다. 구획(ambient/chilled/frozen)은 관제 배차의 입찰
자격이 됩니다.

**설정 파일 탭** — 만들어진 파일을 펼쳐 내용을 보고 복사합니다.

`프로젝트 저장`을 누르면 이 로봇 목록으로 설정 파일이 다시 만들어집니다. 로봇을
고쳤으면 저장해야 반영됩니다.

### 6.5 SQL로 직접 보기

```sql
-- 프로젝트의 설정 파일 목록
SELECT f.file_name, f.kind, LENGTH(f.content) AS 크기, f.generated_at
FROM map_project_files f
JOIN map_projects p ON p.id = f.project_id
WHERE p.map_name = 'gwanghee';

-- fleet adapter 설정 내용
SELECT f.content FROM map_project_files f
JOIN map_projects p ON p.id = f.project_id
WHERE p.map_name = 'gwanghee' AND f.kind = 'fleet_adapter';

-- 프로젝트의 로봇
SELECT r.robot_id, r.gz_name, r.zones, r.charger_waypoint, r.spawn_x, r.spawn_y
FROM map_project_robots r
JOIN map_projects p ON p.id = r.project_id
WHERE p.map_name = 'gwanghee' ORDER BY r.seq;
```

v5 데이터베이스는 `db/migrate_v5_to_v6.sql`을 적용합니다. 기존에 보관하던
`building.yaml`은 설정 파일 목록으로 함께 옮겨집니다.

## 7. 떠 있는 백엔드 정리

새 백엔드를 띄우기 전에 이전 세션의 노드가 남아 있는지 확인해야 합니다. 남은
schedule node나 fleet adapter가 새로 뜨는 것과 부딪히면, 실제 원인과 무관한
오류로 나타납니다.

실제로 겪은 예 — `openrmf/.runtime/fleet_adapter.log`:

```text
AssertionError: Unable to initialize fleet adapter.
Please ensure RMF Schedule Node is running
```

앱의 **로봇 운영** 화면 상단에 현황이 표시됩니다.

- 떠 있는 RMF 노드 목록
- `다시 확인` — `ros2 node list`로 다시 조회
- `백엔드 중지` — `openrmf/scripts/stop_office.sh` 실행 후 출력을 그대로 표시

앱은 보통 ROS를 source하지 않은 셸에서 실행되므로, 조회 전에 `setup.bash`를
읽습니다. 경로가 다르면 환경 변수로 지정합니다.

```bash
export ROS_SETUP=/opt/ros/jazzy/setup.bash
export RMF_WS=$HOME/rmf_ws
export RMF_ROOT=$HOME/robosapiens     # stop_office.sh 를 찾는 기준
```

명령으로 직접 확인·중지할 수도 있습니다.

```bash
ros2 node list
./openrmf/scripts/stop_office.sh
```

## 8. 다음 단계에서 만들어야 하는 것

### 8.1 Pinky용 Fleet Adapter 설정 — 완료

지난 시도는 office 데모의 `tinyRobot_config.yaml`에 gwanghee nav graph를 물려
실행했습니다. 로봇 이름·속도·회전 반경·배터리 파라미터가 모두 tinyRobot 값이라
그대로는 맞지 않았습니다.

이제 **맵 프로젝트마다** 설정을 만들어 MySQL에 보관합니다. 6절을 참고하세요.
남은 것은 이 설정을 물려 실제로 fleet adapter를 띄우는 launch입니다.

### 8.2 gwanghee용 통합 launch (없음)

`openrmf/launch/office_web.launch.xml`은 office 데모 전용입니다. 다음을 한 번에
띄우는 launch가 필요합니다.

- RMF schedule node · traffic 관련 노드
- building map server (배포한 `building.yaml`)
- Pinky fleet adapter (7.1의 설정 + `nav_graphs/0.yaml`)
- Gazebo (배포한 `*.world`, 로봇 3대)

### 8.3 앱과 rmf-web 연결 (없음)

`rmf_control_ui`에는 ROS·rmf-web 연결이 없습니다. 로봇은 앱 안에서 계산하는
Mock입니다(`docs/APP_MOCK_ROBOTS.md`).

`openrmf_app/lib/src/rmf_api.dart`(REST)와 `trajectory_client.dart`(WebSocket)에
이미 rmf-web 클라이언트가 있으므로 가져다 쓸 수 있습니다. 연결 대상은
`OPENRMF_APP_RUN_GUIDE.md`에 적힌 것과 같습니다.

```text
rmf-web REST      http://127.0.0.1:8000
rmf-web WebSocket ws://127.0.0.1:8000/_internal
```

이 작업은 1~3단계와 독립적입니다. office 데모만으로도 검증할 수 있어 ROS 쪽
진행과 무관하게 먼저 해도 됩니다.

## 9. 관련 문서

- [맵 작성 및 배포 가이드](MAP_AUTHORING_AND_DEPLOYMENT.md) — 맵을 만들고
  `nav_graphs/0.yaml`을 얻는 과정
- [앱 전용 Mock 로봇 가이드](APP_MOCK_ROBOTS.md) — 지금의 Mock 주행 범위
- [ROS 관제 시스템 Waypoint 아키텍처 매핑](ROS_CONTROL_WAYPOINT_ARCHITECTURE.md)
- [openrmf_app 실행 가이드](../../openrmf/docs/OPENRMF_APP_RUN_GUIDE.md) —
  rmf-web을 거쳐 관제 화면에 붙이는 기존 경로
