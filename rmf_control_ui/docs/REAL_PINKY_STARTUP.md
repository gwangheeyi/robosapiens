# 실제 Pinky 를 Open-RMF 백엔드에 붙이는 절차

재부팅 뒤부터 로봇이 실제로 움직이는 것까지의 순서다. 2026-08-17 에
`project1-ver2` 로 실제 Pinky 한 대를 붙이면서 막혔던 자리를 그대로 적었다.

예시는 다음 환경을 기준으로 한다.

- ROS 2 Jazzy
- ROS domain ID: `52`
- 맵 프로젝트: `project1-ver2`
- 로봇 namespace: `pinky_01` (앱 등록의 `gz_name` 과 같아야 한다)
- 시뮬레이션 백엔드: `none` (Gazebo 없이 실물만)

namespace 통일이 아직이면 [PINKY_NAMESPACE_MIGRATION.md](PINKY_NAMESPACE_MIGRATION.md)
를 먼저 끝낸다. 그것이 안 되어 있으면 아래 3절에서 반드시 걸린다.

## 0. 순서가 중요한 까닭

**로봇이 먼저, 백엔드가 나중이다.** 반대로 하면 다음이 일어난다.

Nav2 의 `local_costmap` 은 활성화할 때 `<로봇>/base_footprint → <로봇>/odom`
TF 를 **15초만** 기다린다. 로봇이 없으면 그 시간이 지나고 이렇게 끝난다.

```text
Failed to activate local_costmap because transform from pinky_01/base_footprint
  to pinky_01/odom did not become available before timeout
Failed to change state for node: controller_server
Failed to bring up all requested nodes. Aborting bringup.
```

**관리자는 여기서 멈추고 다시 시도하지 않는다.** 뒤늦게 로봇을 켜도 스스로
살아나지 않는다. `amcl` 만 `active` 로 남고 `controller_server` ·
`planner_server` · `bt_navigator` 는 `inactive` 에 머문다. 그 상태에서는 목표를
보내도 로봇이 안 움직이는데, 화면에는 `실행 상태에 도달하지 못했습니다` 로만
보인다.

되살리는 방법은 7절에 있다.

## 1. 앱 다시 빌드

소스를 고쳤으면 반드시 다시 빌드한다. 앱 바이너리가 낡으면 도메인 고정 같은
수정이 안 들어간다.

```bash
cd /home/gyi/robosapiens/rmf_control_ui
flutter build linux --release
```

빌드 시각과 소스 시각을 견줘 확인한다.

```bash
stat -c '%y  %n' build/linux/x64/release/bundle/rmf_control_ui lib/rmf_project_runner_io.dart
```

## 2. ROS 도메인

**프로젝트 도메인과 로봇 도메인이 같아야 한다.** 어긋나면 아무 오류도 안
나면서 아무것도 안 통한다.

```text
로봇  ROS_DOMAIN_ID=52
PC    프로젝트 설정 = 52   (앱: 맵 관리 → ROS 도메인)
```

로봇별 `ros_domain_id` 는 **비워 둔다.** 거기에 값을 넣으면 그 로봇의 Nav2 만
다른 도메인으로 가고 `map_server` 와 어댑터는 프로젝트 도메인에 남아, 지도도
액션도 서로 못 찾는다.

### 2.1 `~/.bashrc` 에 박아 두지 않는다

실행 스크립트는 `${ROS_DOMAIN_ID:-52}` 로 되어 있다. 터미널에서 한 번만 다른
망에 띄워 보는 길을 열어 둔 것인데, `~/.bashrc` 에 `export ROS_DOMAIN_ID=22` 가
있으면 **늘** 이긴다.

실제로 그래서 막혔다. 도메인을 52 로 고치고 몇 번을 다시 배포해도 백엔드는 계속
22 에서 돌았다. 로봇은 52 에 있으니 `/tf` 가 하나도 안 왔고, 화면에는
`Invalid frame ID "pinky_01/odom" ... frame does not exist` 로만 보였다 —
프레임 이름이 틀린 줄 알고 한참을 뒤졌다.

`~/.bashrc` 의 `export ROS_DOMAIN_ID=...` 줄은 지운다. 그러면 터미널은 기본 0 이
되므로, 로봇을 다룰 때마다 직접 넣는다.

```bash
export ROS_DOMAIN_ID=52
```

앱에서 띄우는 백엔드는 프로젝트 값을 못 박으므로 이 영향을 안 받는다.

## 3. 로봇 (bringup 전에 자리를 잡는다)

### 3.1 놓기

전원을 켠 상태로 옮겨도 된다. 기준은 전원이 아니라 **bringup 실행 시점**이다 —
그 순간의 자리가 `pinky_01/odom` 의 원점 `(0, 0)` 이 된다.

```text
전원 켜기  →  충전 자리에 놓기  →  bringup 실행
```

`project1-ver2` 의 충전2 는 이렇다.

| 항목 | 값 |
|---|---|
| 좌표 (RMF 월드) | `x = 1.613`, `y = -1.088` |
| 방향 | `-3.133 rad` = `-179.5°` (도면 −x, 대기3 을 바라보는 쪽) |

등록된 방향대로 놓으면 로봇 코가 이미 갈 방향을 향한다. **180° 틀리지 않게
한다.** 이 건물은 4.8m × 3.7m 라 초기 자세가 반대면 AMCL 이 되돌아오지 못한다.

### 3.2 띄우기

```bash
# pinky 터미널
source /opt/ros/jazzy/setup.bash
source /home/pinky/pinky_pro/install/setup.bash
export ROS_DOMAIN_ID=52
ros2 launch pinky_bringup bringup_robot.launch.xml namespace:=pinky_01
```

namespace 는 앱 등록의 `gz_name` 과 **글자까지 같아야 한다.** 다르면 생성된
`nav2_params.yaml` 의 프레임·토픽이 전부 어긋난다.

## 4. 로봇이 보이는지 확인 — 백엔드 띄우기 전에

이 절을 건너뛰지 않는다. 여기서 막히면 백엔드를 띄워 봐야 0절의 15초 실패를
반복한다.

```bash
# PC 터미널
export ROS_DOMAIN_ID=52
ros2 topic info /pinky_01/odom     # Publisher count: 1
ros2 topic info /pinky_01/scan     # Publisher count: 1
```

둘 다 `1` 이어야 한다. `0` 이면 로봇 쪽 문제다 — 도메인, 네트워크, bringup 이
정말 살아 있는지 순서로 본다.

TF 프레임에 접두사가 붙었는지도 본다.

```bash
ros2 topic echo /tf --once | grep frame
```

```text
frame_id: pinky_01/odom
child_frame_id: pinky_01/base_footprint
```

접두사 없이 `odom` · `base_footprint` 로 나오면
[PINKY_NAMESPACE_MIGRATION.md](PINKY_NAMESPACE_MIGRATION.md) 5절의 프레임 수정이
그 로봇에 안 들어간 것이다. 도메인이 맞아도 같은 오류가 난다.

## 5. 백엔드

앱의 `백엔드 실행` 을 쓰거나 터미널에서 돌린다.

```bash
cd /home/gyi/robosapiens/rmf_maps/project1-ver2
SIM_BACKEND=none RVIZ=true ./run_project1-ver2.sh
```

로그 첫 줄을 확인한다.

```bash
head -3 /home/gyi/robosapiens/rmf_maps/project1-ver2/project1-ver2.log
```

```text
=== 2026-08-17 17:55:24 project1-ver2 실행 ===
Gazebo 창: false · RViz: true · ROS_DOMAIN_ID: 52 (프로젝트 설정)
시뮬레이션 백엔드: none · 시뮬레이터 창: false
```

`(환경 변수 — 프로젝트 설정 52 을 덮었습니다)` 로 나오면 2.1 로 돌아간다.

## 6. 무엇이 떠야 하나

```bash
export ROS_DOMAIN_ID=52
ros2 node list
```

로봇 쪽 (bringup 이 띄운 것):

```text
/pinky_01/pinky_bringup
/pinky_01/robot_state_publisher
/pinky_01/joint_state_publisher
/pinky_01/sllidar_node
/pinky_01/battery_publisher
/pinky_01/pinky_imu_bno055
```

PC 쪽 (백엔드가 띄운 것):

```text
/map_server                     /lifecycle_manager_map
/pinky_01/amcl                  /pinky_01/lifecycle_manager_navigation
/pinky_01/controller_server     /pinky_01/planner_server
/pinky_01/bt_navigator          /pinky_01/behavior_server
/pinky_01/smoother_server       /pinky_01/velocity_smoother
/pinky_01/waypoint_follower
/project1_pinky_nav2_adapter    ← RMF ↔ Nav2
/project1_pinky_fleet_adapter
/project1_ver2_workcell         ← 픽업 자리 응답
/project1_ver2_sensor_relay
/rmf_traffic_schedule_primary   /rmf_dispatcher_node  …
```

`nav2_adapter` · `workcell` · `sensor_relay` 셋은 **한 묶음**이다. 하나가 없으면
셋 다 없다 — 생성기에서 같은 조건 안에 들어 있다.

## 7. Nav2 가 정말 켜졌는지

노드가 있는 것과 `active` 인 것은 다르다.

```bash
export ROS_DOMAIN_ID=52
for n in amcl controller_server planner_server bt_navigator behavior_server; do
  printf "%-18s " $n
  ros2 service call /pinky_01/$n/get_state lifecycle_msgs/srv/GetState \
    | grep -o "label='[a-z]*'" | tail -1
done
```

전부 `active` 여야 한다. 하나라도 `inactive` 면 0절의 실패를 겪은 것이다.

### 7.1 되살리기 — RESET 먼저

**STARTUP 만 부르면 실패한다.** 이미 `active` 인 노드에 `configure` 를 걸어서
첫 노드부터 걸리고, 나머지는 시도조차 안 한다.

```text
Configuring amcl
Failed to change state for node: amcl        ← 이미 active 라 전이가 없다
Failed to bring up all requested nodes. Aborting bringup.
```

한 번 내렸다가 올린다.

```bash
ros2 service call /pinky_01/lifecycle_manager_navigation/manage_nodes \
  nav2_msgs/srv/ManageLifecycleNodes "{command: 1}"   # RESET

ros2 service call /pinky_01/lifecycle_manager_navigation/manage_nodes \
  nav2_msgs/srv/ManageLifecycleNodes "{command: 0}"   # STARTUP
```

`command` 는 `0=STARTUP · 1=RESET · 2=PAUSE · 3=RESUME` 이다.

둘 다 `success=True` 여야 한다. 안 되면 백엔드를 통째로 다시 띄우는 쪽이 빠르다
— **로봇은 켜 둔 채로** 한다.

```bash
cd /home/gyi/robosapiens/rmf_maps/project1-ver2
./stop_project1-ver2.sh
SIM_BACKEND=none RVIZ=true ./run_project1-ver2.sh
```

## 8. 로봇이 제 자리를 아는지 — 목표를 보내기 전에

TF 사슬이 지도부터 로봇까지 이어졌는지 본다.

```bash
ros2 run tf2_ros tf2_echo map pinky_01/base_footprint
```

```text
- Translation: [1.613, -1.088, 0.000]
- Rotation: in RPY (degree) [0.000, -0.000, -179.500]
```

놓아 둔 자리와 맞아야 한다.

**그리고 RViz 에서 라이다를 본다.** 이것이 자리가 맞는지 아는 유일하게 확실한
방법이다. `/pinky_01/scan` 점들이 지도 벽선 **위에** 얹혀야 한다. 나란히
어긋나 있으면 그만큼 틀린 것이고, **목표를 보내면 안 된다.**

### 8.1 겹치지 않으면

`nav2_map/` 의 지도는 **도면에서 만든 것**이다(`useSlamMap: false`). 시뮬레이터
에서는 도면이 곧 월드라 정확하지만, 실제 방이 도면과 다르면 라이다가 벽선에
절대 안 겹친다. 이때 고칠 것은 로봇 자리가 아니라 **지도**다 — 실물 건물에서
SLAM 으로 다시 떠서 `<맵>_slam.yaml` 로 올린다.

## 9. 짧게 한 번 — RMF 없이 Nav2 로만

변수를 줄이려고 먼저 Nav2 에 직접 보낸다. RMF 배차는 그다음이다.

`project1-ver2` 의 자리들:

| 자리 | x | y | 비고 |
|---|---|---|---|
| 충전2 | 1.613 | -1.088 | 시작 자리 |
| 대기3 | 1.185 | -1.091 | 충전2 에서 0.43m |
| 대기4 | 1.185 | -1.602 | |
| 픽업3 | 1.187 | -1.940 | 대기3 에서 0.85m (대기4 경유) |

충전2 → 대기3:

```bash
ros2 action send_goal /pinky_01/navigate_to_pose nav2_msgs/action/NavigateToPose \
"{pose: {header: {frame_id: map}, pose: {position: {x: 1.185, y: -1.091, z: 0.0},
 orientation: {z: -0.7071, w: 0.7071}}}}"
```

대기3 → 픽업3:

```bash
ros2 action send_goal /pinky_01/navigate_to_pose nav2_msgs/action/NavigateToPose \
"{pose: {header: {frame_id: map}, pose: {position: {x: 1.187, y: -1.940, z: 0.0},
 orientation: {z: -0.7071, w: 0.7071}}}}"
```

`orientation` 의 `z: -0.7071, w: 0.7071` 은 `-90°` 다(도면 아래쪽을 봄).

**멈추는 법을 먼저 띄워 둔다.**

```bash
ros2 topic pub --once /pinky_01/cmd_vel geometry_msgs/Twist "{}"
```

이 단계에서 Nav2 는 nav graph 를 모른다. Lane 을 따라가지 않고 costmap 위로
자유롭게 계획한다 — 정상이다. Lane 을 강제하는 것은 RMF 다.

## 10. 아직 남은 문제

### 10.1 `/fleet_states` 의 좌표가 어긋난다

TF 는 정확한데 `/fleet_states` 에 실리는 값이 한 칸씩 밀려 있다.

```text
TF                     (1.613, -1.088, -3.133)
/fleet_states   x: 7.9e+25   y: 1.3e-34   yaw: 1.613   approach_speed_limit: -3.133
                                            ↑ x 값이 yaw 에    ↑ yaw 값이 여기에
```

나머지는 초기화 안 된 메모리 패턴이다(`battery_percent: 1.4e-45`). 전형적인
**메시지 정의 불일치**로, `rmf_fleet_msgs` 를 발행하는 쪽(`rmf_ws`)과 읽는
쪽이 서로 다른 버전으로 빌드됐을 때 이렇게 된다.

Nav2 직접 주행(9절)에는 지장이 없다. RMF 배차로 넘어갈 때 파헤친다.

### 10.2 픽업3 에 적재 방향이 없다

`building.yaml` 의 픽업3 줄에 `robosapiens_dock_heading` 이 없다. 로봇이 그
자리에서 들어온 길 방향 그대로 선다. 주행 시험만이면 상관없지만, 팔이 물건을
집는 단계까지 가면 매번 다른 쪽을 보고 서게 된다.

앱의 Waypoint 수정에서 `적재 방향 (도)` 을 넣고 다시 배포한다. 배포 전 점검이
이제 이것을 물어본다.

### 10.3 `SIM_BACKEND=none` 이면 omx_04 가 없다

픽업3 을 맡는 설비는 `omx_04` 이고 그 출처는 Gazebo 다. 시뮬레이터를 안 띄우면
그 팔은 존재하지 않는다. RMF 로 픽업 작업을 보내면 워크셀이 답할 상대가 없어
작업이 그 자리에서 멈춘다 — **오류는 안 난다.**

팔까지 시험하려면 `SIM_BACKEND=gazebo` 로 띄운다. 그래도 Nav2 와 RMF 는 실물
Pinky 가 있으므로 벽시계로 돈다(`use_sim_time=false`). Gazebo 는 제 안에서만
sim 시계를 쓴다.

## 11. 내리기

```bash
cd /home/gyi/robosapiens/rmf_maps/project1-ver2
./stop_project1-ver2.sh
```

로봇 쪽은 bringup 터미널에서 `Ctrl+C` **한 번**만 누르고 기다린다. 연타하면
정리 중에 끊겨 좀비가 남는다. 그다음 확인한다.

```bash
ps -ef | grep -E '[p]inky_bringup|[s]llidar_node|[p]inky_imu_bno055'
```

아무것도 안 나와야 한다. 남아 있으면 지운다.

```bash
pkill -f pinky_bringup
pkill -f sllidar_node
pkill -f pinky_imu_bno055
```

남은 노드를 안 지우고 다시 띄우면 같은 이름의 노드가 둘이 되어
`/pinky_01/cmd_vel` 을 둘이 구독한다. 로봇이 떨거나 반응이 오락가락하는데
**오류는 한 줄도 안 난다.**

## 12. 한눈에

```text
① flutter build linux --release          앱이 낡았으면
② ~/.bashrc 에 ROS_DOMAIN_ID export 없음  확인
③ 로봇: 충전2 에 놓기 → bringup (52)
④ PC: odom·scan Publisher count = 1       ← 여기 막히면 멈춘다
⑤ 백엔드 실행 → 로그 첫 줄 "52 (프로젝트 설정)"
⑥ Nav2 5개 전부 active                    아니면 RESET → STARTUP
⑦ RViz 에서 라이다가 벽선에 겹침           안 겹치면 목표 금지
⑧ navigate_to_pose 로 짧게 한 번
```
