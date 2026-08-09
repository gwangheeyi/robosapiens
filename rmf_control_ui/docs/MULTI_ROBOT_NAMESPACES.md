# 한 월드에 로봇 여러 대 — 네임스페이스가 닿아야 하는 곳

## 1. 짧은 답

**네임스페이스는 필요조건이지 충분조건이 아닙니다.**

로봇 두 대를 같은 월드에 올리면 이름이 겹칩니다. 그것을 가르는 수단은
네임스페이스가 맞습니다. 그런데 **어디에 거느냐**와 **몇 번 거느냐**를 틀리면,
안 걸었을 때보다 나쁜 증상이 나옵니다 — 조용히 멈추거나, 상관없는 로봇까지
같이 죽습니다.

이 문서는 이번에 실제로 밟은 함정 넷을 증거와 함께 정리합니다.

| # | 함정 | 증상 |
|---|---|---|
| 1 | 네임스페이스를 두 번 걸었다 | 로봇이 스폰되지 않고 조용히 멈춤 |
| 2 | 토픽 다리 이름이 상대 경로였다 | 두 로봇이 같은 토픽을 씀 |
| 3 | **URDF 안의 플러그인에 안 닿았다** | **시뮬레이션 전체가 멈춤** |
| 4 | 정리할 때 네임스페이스를 안 봤다 | 프로세스가 살아남음 |

관련 문서: [로봇 등록과 디렉터리 구조](ROBOT_REGISTRATION.md) ·
[관제 노드별 하는 일](RMF_NODES.md) ·
[Pinky 연동](PINKY_FLEET_INTEGRATION.md) ·
[좌표계](COORDINATE_FRAMES.md)

## 2. 네임스페이스가 닿아야 하는 네 곳

로봇 한 대에 이름 하나(`gz_name`)를 정하면, 그 이름이 **서로 다른 네 층**에
닿아야 합니다. 한 층이라도 빠지면 그 층에서 겹칩니다.

```
① ROS 노드 이름       /pinky_01/robot_state_publisher
② URDF 링크·프레임    pinky_01/base_link
③ Gazebo 플러그인 토픽 /pinky_01/odom      ← URDF 안에서 정해진다
④ 토픽 다리 설정      ros_topic_name: "/pinky_01/odom"
```

①②③은 Pinky의 경우 `upload_robot.launch.py` 의 **`namespace` 인자 하나**가
함께 정합니다. ④는 우리가 만드는 `<맵이름>_gz_bridge.yaml` 입니다.

**③이 이번 사고의 핵심입니다.** 플러그인은 URDF 안에 적혀 있어서, launch 에
네임스페이스를 걸어도 닿지 않을 수 있습니다.

## 3. 함정 1 — 두 번 걸기

```xml
<group>
  <push-ros-namespace namespace="pinky_01"/>          <!-- 여기서 한 번 -->
  <include file=".../upload_robot.launch.py">
    <arg name="namespace" value="pinky_01"/>          <!-- 여기서 또 한 번 -->
  </include>
  <node pkg="ros_gz_sim" exec="create"
        args="-name pinky_01 -topic robot_description"/>
</group>
```

`push-ros-namespace` 는 그룹 안 노드의 네임스페이스 **앞에 덧붙입니다.**
`upload_robot.launch.py` 는 이미 노드에 `namespace` 를 걸므로 두 겹이 됩니다.

실제로 띄워 확인했습니다.

```
=== 노드 ===
/pinky_01/pinky_01/rsp          ← 두 겹
=== 토픽 ===
/pinky_01/pinky_01/chatter
```

그런데 ②③은 두 배가 되지 않습니다. `namespace` 인자가 정하는 것이라 한 겹
그대로입니다. **①만 어긋납니다.**

결과: `robot_state_publisher` 는 `/pinky_01/pinky_01/robot_description` 에
내보내는데 `create` 는 `/pinky_01/robot_description` 을 기다립니다. 오지 않을
것을 영영 기다리며 **로봇이 스폰되지 않습니다.** 오류도 안 납니다.

### 고침

**인자로만 겁니다.** `push-ros-namespace` 는 쓰지 않습니다.

```xml
<group>
  <include file=".../upload_robot.launch.py">
    <arg name="namespace" value="pinky_01"/>
  </include>
  <node pkg="ros_gz_sim" exec="create"
        args="-name pinky_01 -topic /pinky_01/robot_description"/>
</group>
```

`create` 의 `-topic` 도 **절대 이름**으로 적습니다. 상대 이름이면 그룹 밖의
루트 `/robot_description` 을 기다립니다.

### 예외 — 설치 로봇

OMX 쪽은 `push-ros-namespace` 를 **씁니다.** 그 그룹 안의 노드에는
네임스페이스를 따로 걸지 않으므로 두 겹이 되지 않습니다.

**규칙은 하나입니다: 한 번만 건다.** 어느 쪽으로 거는지는 include 하는 launch
가 네임스페이스 인자를 받느냐에 달렸습니다.

| include 하는 launch | 거는 법 |
|---|---|
| `namespace` 인자를 받음 (Pinky) | 인자로만 |
| 인자가 없음 (OMX 는 우리가 직접 노드를 씀) | `push-ros-namespace` 로만 |

## 4. 함정 2 — 토픽 다리 이름이 상대 경로

벤더의 `pinky_gz_sim/params/pinky_bridge.yaml` 은 이렇게 생겼습니다.

```yaml
- ros_topic_name: "odom"       # 상대 이름
  gz_topic_name: "odom"
```

로봇이 하나일 때는 맞습니다. **여러 대면 전부 같은 `/odom` 으로 겹칩니다.**

### 고침

프로젝트마다 **양쪽 다 절대 이름**으로 새로 만듭니다. 네임스페이스 해석 규칙에
기대지 않으므로 어긋날 여지가 없습니다.

```yaml
- ros_topic_name: "/pinky_01/odom"
  gz_topic_name: "/pinky_01/odom"
  ros_type_name: "nav_msgs/msg/Odometry"
  gz_type_name: "gz.msgs.Odometry"
  direction: GZ_TO_ROS
```

두 대를 붙여 확인했습니다. `pinky_01` 에만 `cmd_vel` 을 주면:

```
pinky_01   0.0284 -> 0.0545   이동 0.0261 m
pinky_02  -0.0000 -> -0.0000  이동 -0.0000 m
```

**한 대만 움직입니다.**

### 다리 노드는 하나만

`parameter_bridge` 는 설정 파일 하나만 받습니다. 로봇마다 띄우면 같은 토픽에
다리를 여러 번 놓게 됩니다. 프로젝트 전체를 묶은 파일 하나로 노드 하나만
띄웁니다.

## 5. 함정 3 — URDF 안의 플러그인 (이번 문제)

**증상**: Pinky 가 계속 앱 Mock 값을 보여 줬습니다. 확인해 보니
`/pinky_01/odom` 에 발행자는 있는데 **값이 하나도 없었습니다.**

```
/clock   발행자 1개 · 구독자 19개 · 데이터 0
```

관제 노드 19개가 전부 sim 시간을 기다리며 굳어 있었습니다.

### 가려낸 과정

| 실험 | 결과 | 뜻 |
|---|---|---|
| 월드만 단독 실행 | RTF **0.9997** | 월드는 멀쩡 |
| Pinky 만 띄움 | `/clock` **100Hz**, odom 정상 | 로봇도 멀쩡 |
| OMX 를 넣음 | **멈춤** | OMX 가 원인 |

로그에 답이 있었습니다.

```
[gazebo-1] [WARN] [controller_manager]: Waiting for data on 'robot_description' topic
[gazebo-1] [WARN] [gz_ros_control]: Waiting RM to load and initialize hardware...
```

### 원인

OpenMANIPULATOR 의 xacro 에는 `gz_ros2_control` 플러그인이 **네임스페이스 없이**
박혀 있습니다.

```xml
<plugin filename="gz_ros2_control-system"
        name="gz_ros2_control::GazeboSimROS2ControlPlugin">
  <parameters>$(find open_manipulator_bringup)/config/.../hardware_controller_manager.yaml</parameters>
</plugin>
<!-- <ros><namespace> 가 없다 -->
```

이 플러그인은 **Gazebo 서버 안에서** 돕니다. launch 에 건 네임스페이스는 여기
닿지 않습니다. 그래서 루트 `/robot_description` 을 기다리는데, 우리는 로봇마다
네임스페이스를 나누므로 그 토픽이 영영 오지 않습니다.

**그냥 OMX 만 못 뜨고 마는 것이 아닙니다.** 그 기다림이 Gazebo 갱신 루프 안에서
일어나 **시뮬레이션 전체가 멈춥니다.** 같은 월드의 Pinky 까지 값을 못 냅니다.

```
로봇 A 의 플러그인이 기다림
        ↓
Gazebo 갱신 루프가 멈춤
        ↓
/clock 이 안 나옴
        ↓
로봇 B 도, 관제 노드 19개도 전부 굳음
```

### 고침

펼친 URDF 에 네임스페이스를 **끼워 넣습니다.** 벤더 파일은 건드리지 않습니다.

설치 로봇마다 `robots/<로봇 ID>/robot_description.sh` 를 만듭니다.

```bash
xacro "$XACRO" use_sim:=true | python3 -c '
...
urdf = re.sub(
    r"(<plugin[^>]*gz_ros2_control[^>]*>)",
    r"\1<ros><namespace>/" + namespace + r"</namespace></ros>"
    r"<robot_param_node>robot_state_publisher</robot_param_node>",
    urdf, count=1)
' "$NAMESPACE"
```

`spawn.launch.xml` 이 벤더 xacro 대신 이 스크립트를 부릅니다.

```xml
<param name="robot_description"
       value="$(command '$(var robot_dir)/robot_description.sh')"/>
```

- `<ros><namespace>` — 플러그인이 만드는 `controller_manager` 를 그 아래에 둔다
- `<robot_param_node>` — URDF 를 어느 노드에서 받아올지 알려 준다

### 확인

Pinky 와 OMX 를 함께 띄웠습니다.

```
/clock                100.012 Hz              ← 돈다
/pinky_01/odom        x: -4.42e-38            ← 값이 온다
/omx_01/joint_states  100.020 Hz              ← 팔도 산다
controller_manager    /omx_01/controller_manager   ← 네임스페이스가 붙었다
```

> 확인은 Pinky 1대 + OMX 1대로 했습니다. OMX 두 대를 함께 올리는 것은 같은
> 규칙을 따르지만 아직 돌려보지 않았습니다.

### 일반 규칙

**Gazebo 서버 안에서 도는 플러그인은 launch 네임스페이스가 닿지 않습니다.**
플러그인이 ROS 토픽을 쓰면, 그 이름은 URDF·SDF 안에서 정해져야 합니다.

| 플러그인 | 이름을 어디서 받나 |
|---|---|
| `gz-sim-diff-drive-system` (Pinky) | xacro 의 `${namespace}` 인자 — **닿는다** |
| `gz-sim-joint-state-publisher-system` | 같음 — 닿는다 |
| `gpu_lidar` · `camera` 센서 | 같음 — 닿는다 |
| `gz_ros2_control` (OMX) | 하드코딩 — **안 닿는다** |

Pinky 쪽이 괜찮았던 것은 벤더 xacro 가 `namespace` 를 인자로 받아 모든 토픽에
붙여 주기 때문입니다. OMX 쪽은 그런 인자가 없습니다.

## 6. 나누면 안 되는 것

전부 나누면 되는 것이 아닙니다. **월드에 하나뿐인 것은 나누면 안 됩니다.**

| 토픽 | 나누나 | 왜 |
|---|---|---|
| `/clock` | **안 나눔** | 월드의 시간은 하나다 |
| `/tf` | **안 나눔** | 프레임 이름이 `frame_prefix` 로 이미 갈린다 |
| `/odom` `/scan` `/cmd_vel` | 나눔 | 로봇마다 다르다 |
| `/joint_states` | 나눔 | 로봇마다 다르다 |
| `controller_manager` | 나눔 | 로봇마다 컨트롤러가 다르다 |

로봇별 `bridge.yaml` 에 `clock` 과 `tf` 를 넣지 않은 것도 이 때문입니다. 넣어
두면 그 파일만 보고 돌렸을 때 같은 토픽에 다리를 두 번 놓게 됩니다.

## 7. 정리할 때도 네임스페이스가 손잡이

`ros2 launch` 가 죽으면 자식이 init 으로 재부모화됩니다. 프로세스 그룹도 잃고
`ros2 launch <경로>` 라는 이름도 잃습니다.

맵 디렉터리 경로로 찾는 방법도 통하지 않습니다. `robot_state_publisher` 는
인자에 URDF 만 들고 있어 맵 경로가 없습니다.

```
/opt/ros/jazzy/lib/robot_state_publisher/robot_state_publisher
  --ros-args -r __node:=robot_state_publisher -r __ns:=/pinky_01
                                                 ↑ 이것이 손잡이
```

ROS 가 넣어 준 `__ns:=/<gz 이름>` 은 cmdline 에 남습니다. 중지 스크립트가 이
이름으로도 쓸어냅니다. 실제로 남아 있던 9개를 이 방법으로 정리했습니다.

```
로봇 네임스페이스 (gwanghee) 중지: 666083 666084 680443 680444 666087 ...
```

## 8. 확인하는 법

```bash
source /opt/ros/jazzy/setup.bash

# ① 노드가 두 겹인가
ros2 node list | grep pinky
#   /pinky_01/robot_state_publisher              ← 맞다
#   /pinky_01/pinky_01/robot_state_publisher     ← 두 겹

# ② 토픽이 갈렸는가
ros2 topic list | grep -E "pinky_0|omx_0"

# ③ 값이 실제로 오는가 — 이름만 있고 값이 없을 수 있다
ros2 topic hz /pinky_01/odom
ros2 topic info /clock            # 발행자·구독자 수

# ④ 시뮬레이션이 도는가
ros2 topic hz /clock              # 안 나오면 Gazebo 가 멈춘 것

# ⑤ controller_manager 가 로봇마다 있는가
ros2 service list | grep controller_manager/list_controllers

# ⑥ 한 대만 따로 띄워 보기
ros2 launch rmf_maps/<맵>/robots/PK-01/spawn.launch.xml
```

**③이 중요합니다.** 토픽 이름이 목록에 있다고 값이 오는 것은 아닙니다. 다리가
광고만 하고 Gazebo 가 아무것도 안 보내는 상태가 실제로 있었습니다.

## 9. 점검표

로봇을 여러 대 올릴 때 확인할 것.

- [ ] 네임스페이스를 **한 번만** 걸었는가 (`push-ros-namespace` 와 인자를 겹치지 않았는가)
- [ ] `create` 의 `-topic` 이 절대 이름인가
- [ ] 토픽 다리 설정이 양쪽 다 절대 이름인가
- [ ] 다리 노드가 **하나만** 뜨는가
- [ ] `clock` 과 `tf` 를 로봇별로 나누지 않았는가
- [ ] **Gazebo 안에서 도는 플러그인에 네임스페이스가 닿는가**
- [ ] 각 로봇이 제 `controller_manager` 를 갖는가 (설치 로봇)
- [ ] `is_sim:=True` 가 들어갔는가 (안 그러면 껍데기만 뜬다)

## 10. 이번에 함께 드러난 것 — 네임스페이스와 무관한 함정

원인을 찾는 과정에서 별개 문제 둘이 함께 나왔습니다. 같이 적어 둡니다.

### 파이프 교착

앱이 실행 스크립트를 `detachedWithStdio` 로 띄우면 파이프가 생기는데, 앱은 그
파이프를 읽지 않습니다. **64KB 가 차는 순간 Gazebo 가 `write` 에서 영원히
멈춥니다.**

```
gz sim   stat=Sl   wchan=anon_pipe_write
```

증상이 5절과 똑같습니다 — 물리가 안 돌고 `/clock` 이 안 나옵니다. 실행
스크립트가 제 로그 파일로 출력을 보내고 앱은 `detached` 로 띄우도록 고쳤습니다.

이 로그가 결국 5절의 원인을 찾아 줬습니다.

### 유령 노드

강제 종료된 노드는 DDS 에 떠난다고 알리지 못해 `ros2 node list` 에 남습니다.
실측 **약 16초**. 그 사이에 목록을 읽으면 방금 내린 것이 그대로 나옵니다.

정리 여부의 판정은 **프로세스 목록으로** 합니다. 그것이 진실입니다.
