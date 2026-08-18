# 실제 Pinky ROS 2 namespace 분리 운용

이 문서는 기존 단일 로봇 bringup을 보존하면서 실제 Pinky를 `pinky_01`,
`pinky_02` 같은 namespace로 실행하는 절차다.

예시 환경:

- ROS 2 Jazzy
- ROS domain ID: `52`
- Pinky workspace: `/home/pinky/pinky_pro`

> **로봇 workspace 를 아직 못 고친다면**, 그동안은 `domain_bridge` 로 관제
> 쪽에서만 이름을 가를 수 있다. 로봇은 `ROS_DOMAIN_ID` 만 바꾼다.
> `rmf_control_ui/docs/PINKY_DOMAIN_BRIDGE.md` 를 보라. 다만 그 방법으로는
> `/tf` 안의 프레임 이름이 안 갈려서 **Nav2 자율주행은 안 된다.** 자율주행이
> 필요하면 이 문서의 이관을 끝내야 한다.

## 1. 왜 실행 파일을 분리하는가

기존 `bringup_robot.launch.xml`에 namespace 처리를 직접 넣으면 기존 하드웨어
시험과 RMF용 다중 로봇 실행을 구분하기 어렵다. 문제가 생겼을 때 원인이 원본
bringup인지 namespace 변경인지도 확인하기 어렵다.

따라서 두 실행 경로를 함께 둔다.

| 용도 | 실행 명령 | 사용하는 구현 |
|---|---|---|
| 기존 단일 로봇 | `bringup_robot.launch.xml` | `bringup.py`, `pinky_params.yaml` |
| namespace 로봇 | `bringup_robot_namespaced.launch.xml` | `bringup_namespaced.py`, `pinky_namespaced_params.yaml` |

기존 세 파일은 수정하지 않는다.

```text
pinky_bringup/launch/bringup_robot.launch.xml
pinky_bringup/pinky_bringup/bringup.py
pinky_bringup/config/pinky_params.yaml
```

namespace용으로 다음 세 파일과 별도 실행 진입점을 추가한다.

```text
pinky_bringup/launch/bringup_robot_namespaced.launch.xml
pinky_bringup/pinky_bringup/bringup_namespaced.py
pinky_bringup/config/pinky_namespaced_params.yaml
pinky_bringup/setup.py의 bringup_namespaced 진입점
```

`install/` 아래 파일은 빌드 결과이므로 직접 수정하지 않는다.

## 2. 새 bringup이 분리하는 항목

`namespace:=pinky_01`로 실행하면 다음처럼 구성된다.

```text
/pinky_01/pinky_bringup
/pinky_01/battery_publisher
/pinky_01/robot_state_publisher
/pinky_01/joint_state_publisher
/pinky_01/sllidar_node

/pinky_01/cmd_vel
/pinky_01/odom
/pinky_01/scan
/pinky_01/joint_states
/pinky_01/battery/voltage
/pinky_01/battery/percent
```

`/tf`와 `/tf_static`은 모든 로봇이 공유하는 토픽이므로 루트에 있는 것이 정상이다.
대신 메시지 내부 frame ID가 다음처럼 구분되어야 한다.

```text
pinky_01/odom -> pinky_01/base_footprint -> pinky_01/base_link -> ...
```

LiDAR frame은 `pinky_01/rplidar_link`가 된다.

## 3. 구현 위치

이 저장소의 구현은 다음 경로에 있다.

```text
robot_model/pinky_pro/pinky_bringup/launch/bringup_robot_namespaced.launch.xml
robot_model/pinky_pro/pinky_bringup/pinky_bringup/bringup_namespaced.py
robot_model/pinky_pro/pinky_bringup/config/pinky_namespaced_params.yaml
robot_model/pinky_pro/pinky_bringup/setup.py
```

실제 Pinky 컴퓨터의 같은 source package에 이 파일들을 반영한다. 기존
`bringup_robot.launch.xml`, `bringup.py`, `pinky_params.yaml`을 덮어쓰지 않는다.

`setup.py`에는 다음 진입점이 있어야 한다.

```python
'bringup_namespaced=pinky_bringup.bringup_namespaced:main',
```

## 4. 빌드와 설치 확인

Pinky 컴퓨터에서 실행한다.

```bash
source /opt/ros/jazzy/setup.bash
cd /home/pinky/pinky_pro
colcon build --packages-select pinky_bringup
source install/setup.bash
```

새 파일이 설치됐는지 확인한다.

```bash
test -x install/pinky_bringup/lib/pinky_bringup/bringup_namespaced
test -f install/pinky_bringup/share/pinky_bringup/launch/bringup_robot_namespaced.launch.xml
test -f install/pinky_bringup/share/pinky_bringup/config/pinky_namespaced_params.yaml
ros2 launch pinky_bringup bringup_robot_namespaced.launch.xml --show-args
```

`--show-args` 결과에 `namespace`가 있고 기본값이 `pinky_01`이어야 한다.

## 5. 실행

기존 bringup 프로세스를 먼저 정상 종료한다. 같은 로봇에서 기존 bringup과 새
bringup을 동시에 실행하면 두 노드가 같은 모터와 시리얼 포트를 사용하므로 안 된다.

```bash
ps -ef | grep -E '[p]inky_bringup|[s]llidar_node'
```

첫 번째 Pinky:

```bash
source /opt/ros/jazzy/setup.bash
source /home/pinky/pinky_pro/install/setup.bash
export ROS_DOMAIN_ID=52
ros2 launch pinky_bringup bringup_robot_namespaced.launch.xml namespace:=pinky_01
```

두 번째 Pinky:

```bash
source /opt/ros/jazzy/setup.bash
source /home/pinky/pinky_pro/install/setup.bash
export ROS_DOMAIN_ID=52
ros2 launch pinky_bringup bringup_robot_namespaced.launch.xml namespace:=pinky_02
```

로봇마다 서로 다른 namespace를 사용한다. ROS domain ID는 같은 플릿끼리 같아야
한다.

## 6. 구현 자체 검사

실행 전에 namespace 전용 구현이 기존 구현과 실제로 분리되어 있는지 확인한다.

```bash
grep -n "bringup_namespaced" pinky_bringup/setup.py
grep -n "exec=\"bringup_namespaced\"" \
  pinky_bringup/launch/bringup_robot_namespaced.launch.xml
grep -n "header.frame_id\|child_frame_id" \
  pinky_bringup/pinky_bringup/bringup_namespaced.py
```

`bringup_namespaced.py`는 ROS namespace를 읽어 Odometry와 `/tf` 메시지 내부의
프레임 이름에도 접두어를 붙여야 한다. 노드 namespace만 설정하고 기존
`bringup.py`를 실행하면 토픽은 `/pinky_01/odom`이어도 프레임은 여전히
`odom -> base_footprint`이므로 Nav2가 활성화되지 않는다.

## 7. 빌드 결과 확인

소스 파일이 있는 것만으로는 충분하지 않다. `ros2 launch`는 `src/`가 아니라
`install/`에 설치된 결과를 실행하므로 빌드 후 다음 파일을 확인한다.

```bash
test -x install/pinky_bringup/lib/pinky_bringup/bringup_namespaced
test -f install/pinky_bringup/share/pinky_bringup/launch/bringup_robot_namespaced.launch.xml
test -f install/pinky_bringup/share/pinky_bringup/config/pinky_namespaced_params.yaml
```

하나라도 없으면 빌드 또는 source가 잘못된 것이다. 다시 빌드하고 현재 셸에
설치 공간을 적용한다.

```bash
colcon build --packages-select pinky_bringup
source install/setup.bash
```

## 8. 기존 프로세스 종료 후 실행

기존 bringup과 namespace bringup을 동시에 실행하면 두 프로세스가 같은 모터
시리얼 포트를 사용한다. 새 launch를 실행하기 전에 기존 프로세스가 없는지
확인한다.

```bash
ps -ef | grep -E '[p]inky_bringup|[s]llidar_node'
```

남은 프로세스를 정상 종료한 다음 5절의 namespace 전용 launch를 실행한다.

## 9. Pinky 컴퓨터에서 검증

### 9.1 ROS 환경

새 터미널에서 환경을 다시 source한 뒤 확인한다.

```bash
source /opt/ros/jazzy/setup.bash
source /home/pinky/pinky_pro/install/setup.bash
export ROS_DOMAIN_ID=52

echo "$ROS_DOMAIN_ID"
ros2 pkg prefix pinky_bringup
```

domain ID는 관제 PC와 같아야 하며, `ros2 pkg prefix`는 방금 빌드한
`/home/pinky/pinky_pro/install/pinky_bringup`을 가리켜야 한다.

### 9.2 노드와 토픽

```bash
ros2 node list
ros2 topic list -t
```

다음 노드와 토픽이 보여야 한다.

```text
/pinky_01/pinky_bringup
/pinky_01/robot_state_publisher
/pinky_01/sllidar_node
/pinky_01/odom
/pinky_01/scan
/pinky_01/battery/voltage
/pinky_01/battery/percent
```

### 9.3 Odometry와 TF

```bash
ros2 topic echo /pinky_01/odom --once
ros2 topic echo /tf --once
```

Odometry와 `/tf` 변환에 다음 프레임이 있어야 한다.

```text
frame_id: pinky_01/odom
child_frame_id: pinky_01/base_footprint
```

토픽 이름은 `/pinky_01/odom`인데 메시지 내부가 `odom`과 `base_footprint`라면
기존 `bringup.py`가 실행 중인 것이다. 해당 프로세스를 종료하고
`bringup_robot_namespaced.launch.xml`로 다시 실행한다.

TF 연결을 직접 검사할 수도 있다.

```bash
ros2 run tf2_ros tf2_echo pinky_01/odom pinky_01/base_footprint
```

변환 값이 계속 출력되어야 한다.

### 9.4 LiDAR

```bash
ros2 topic echo /pinky_01/scan --field header --once
```

정상 프레임:

```text
frame_id: pinky_01/rplidar_link
```

`rplidar_link`만 나오면 namespace용 launch가 아니거나 LiDAR launch의
`frame_id` 전달이 누락된 것이다.

### 9.5 배터리

```bash
ros2 topic echo /pinky_01/battery/voltage --once
ros2 topic echo /pinky_01/battery/percent --once
```

두 토픽 모두 한 번 이상 값을 내야 한다. 저전압 경고가 나오면 이동 시험 전에
충전한다.

### 9.6 루트 토픽 누수 확인

```bash
ros2 topic list | grep -E '^/(cmd_vel|odom|scan|joint_states)$'
```

아무것도 출력되지 않아야 한다. 아래 루트 토픽이 남아 있으면 이전 bringup이
살아 있거나 다른 launch를 실행한 것이다.

```text
/cmd_vel
/odom
/scan
/joint_states
```

## 10. 로컬 관제 PC에서 검증

Pinky 컴퓨터 안에서만 통과하면 namespace 구현만 확인한 것이다. 실제 운용 전에
관제 PC가 같은 ROS 그래프를 발견하고 TF를 재구성할 수 있는지도 검사한다.

```bash
source /opt/ros/jazzy/setup.bash
export ROS_DOMAIN_ID=52

ros2 node list
ros2 topic echo /pinky_01/odom --once
ros2 topic echo /pinky_01/scan --field header --once
ros2 run tf2_ros tf2_echo pinky_01/odom pinky_01/base_footprint
```

관제 PC에서 토픽 이름만 보이고 `echo`가 멈춘다면 ROS discovery, 방화벽 또는
네트워크 인터페이스 문제다. `odom`과 `scan`은 수신되지만 `tf2_echo`가 실패하면
메시지 내부 frame ID가 잘못됐거나 `/tf`가 관제 PC까지 전달되지 않은 것이다.

Nav2를 실행한 뒤에는 주요 lifecycle 노드가 모두 `active`인지 확인한다.

```bash
for node in amcl controller_server planner_server bt_navigator velocity_smoother; do
  ros2 lifecycle get /pinky_01/$node
done
```

목표를 보내기 전에 `/pinky_01/cmd_vel` 연결도 확인한다.

```bash
ros2 topic info -v /pinky_01/cmd_vel
ros2 action info /pinky_01/navigate_to_pose
```

정상 상태에서는 `navigate_to_pose` action server가 있고, Nav2가 이동 중일 때
`/pinky_01/cmd_vel`에 0이 아닌 속도 명령이 발행된다.

## 11. 앱 등록

하드웨어 검증을 통과한 뒤 Workcell 앱에서 등록한다.

```text
종류: 이동 로봇
값의 출처: 실제 로봇
로봇 ID: pinky_01
표시 이름: PK-01
ROS domain ID: 52
충전 자리: 실제 시작 Waypoint
```

등록 후 디스크로 내보내고 RMF/Nav2를 실행한다. 실제 로봇은 Gazebo bringup에
포함하지 않는다.

## 12. 기존 방식으로 되돌리기

namespace 전용 실행을 종료한 뒤 기존 명령을 사용한다. 원본 파일을 수정하지
않았으므로 복구용 파일 복사는 필요 없다.

```bash
ros2 launch pinky_bringup bringup_robot.launch.xml
```

되돌릴 때도 기존 프로세스가 완전히 종료됐는지 먼저 확인한다. 두 bringup을 동시에
실행하지 않는다.
