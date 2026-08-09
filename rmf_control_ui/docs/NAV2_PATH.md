# Gazebo에서 실물 핑키까지 — Nav2 길

관련 문서: [좌표계](COORDINATE_FRAMES.md) ·
[한 월드에 로봇 여러 대](MULTI_ROBOT_NAMESPACES.md) ·
[관제 노드별 하는 일](RMF_NODES.md)

---

## 1. 왜 이 길인가

최종이 실물 핑키라면 **slotcar를 쓰면 안 됩니다.** RMF 표준 시뮬레이션 로봇인
slotcar는 `robot_path_requests`를 받아 모델을 nav graph 위로 그냥 끌고 갑니다.
라이다도 지도도 안 씁니다. 지금 당장은 제일 빠르지만 실물로 갈 때 통째로
버립니다.

Nav2 길로 가면 Gazebo에서 만든 것이 실물에 **그대로** 갑니다. 바뀌는 것은 맨
아래 한 겹뿐입니다.

```
   RMF 관제 · 배차 · 교통정리          ← 그대로
   EasyFullControl 어댑터              ← 그대로
   Nav2 · AMCL · costmap               ← 그대로
   점유격자 지도                        ← 그대로 (원점만 맞으면)
 ─────────────────────────────────
   /cmd_vel  /odom  /scan
   Gazebo diff_drive    →    진짜 핑키 모터·라이다     ← 여기만 바뀜
```

---

## 2. 지금 어디까지 왔나

| 단계 | 상태 |
|------|------|
| ① 점유격자 지도 | **끝** — 앱이 도면에서 만듭니다 |
| ② Nav2 네임스페이스 정리 | 아직 |
| ③ EasyFullControl 어댑터 | 아직 |
| ④ 실물 핑키 | 아직 |

### 지금 끊겨 있는 곳

```
/robot_state          Publisher 0   Subscription 1   ← RMF가 듣는데 아무도 말 안 함
/robot_path_requests  Publisher 1   Subscription 0   ← RMF가 말하는데 아무도 안 들음
```

`rmf_demos_fleet_adapter`는 이 두 토픽으로 로봇을 몹니다. 양쪽 다 상대가
없습니다. **RMF가 허공에 배차하고 있습니다.** 화면에서 로봇이 움직이는 것은
앱이 계산한 값입니다. ③에서 이 고리를 잇습니다.

---

## 3. ① 점유격자 지도 — 끝

앱이 프로젝트를 내보낼 때마다 **도면에서** 만듭니다.

```
rmf_maps/<맵>/nav2_map/
  <맵>.pgm       그림
  <맵>.yaml      map_server 가 읽는 설명
  README.md      이게 뭐고 SLAM 과 어떻게 비교하는지
```

### 왜 시뮬레이터에서 SLAM을 안 도나

**정확한 도면이 이미 있고, 그 도면이 Gazebo 월드를 만든 바로 그 원본이기
때문입니다.** 도면에서 바로 만들면

- **원점이 RMF 월드에 계산으로 정확히 맞습니다.** 맞추는 작업 자체가 없습니다
- 표류가 없습니다
- 맵을 고치면 다시 만들어집니다

SLAM은 나중에 **진짜 건물**에서 뜹니다. 그때는 원점을 손으로 맞춰야 합니다(§6).

### 시뮬레이터와 같은 것을 그린다

격자가 Gazebo와 다르면 AMCL이 라이다와 지도를 못 맞춥니다. 그래서
`building.yaml`에 나가는 것과 **같은 원본**을 씁니다.

| 격자 | 원본 | Gazebo |
|------|------|--------|
| 다닐 수 있음 | 바닥 다각형 | `floor_1.obj` |
| 벽 | 벽 선분 + 두께 **0.1 m** | `wall_1.obj` |
| 모름 | 바닥 바깥 | — |

벽 두께 0.1 m는 RMF가 정한 값입니다 —
`rmf_building_map_tools/building_map/wall.py`의 `wall_thickness = 0.1`. 생성된
`wall_1.obj`를 재 봐도 정확히 0.1 m입니다.

### 한 칸을 몇 미터로

두 가지를 함께 봅니다.

- **로봇 몸이 여섯 칸은** 되게 — 한 칸이 로봇만 하면 좁은 통로가 통째로 막힌
  것으로 보입니다
- **바닥 짧은 쪽이 120칸은** 되게 — 작은 아레나에서 0.05 m를 쓰면 방 전체가
  쉰 칸밖에 안 되어 AMCL이 맞출 무늬가 없습니다

0.05 m(ROS 관례, `pinky_navigation`의 기존 지도와 같은 값)와 0.01 m 사이로
묶습니다. gwanghee는 짧은 쪽이 2.557 m라 **0.0213 m**가 나옵니다.

### 맞는지 확인한 방법

`map_server`로 띄워서 RMF 좌표 그대로 찍어 봤습니다.

| 지점 | RMF 좌표 | 격자 |
|------|----------|------|
| 홈1 | (1.7607, −0.6376) | 다닐 수 있음 |
| 픽업1 | (0.3176, −0.9018) | 다닐 수 있음 |
| 드랍오프1 | (1.9607, −0.3027) | 다닐 수 있음 |
| 예전 잘못된 자리 | (1.642, **+**1.595) | 격자 밖 |
| 건물 밖 | (−0.40, −1.5) | 모름 |

**맞추는 작업 없이 계산만으로** 전부 제자리에 떨어집니다.

```bash
cd rmf_maps/<맵>/nav2_map
ros2 run nav2_map_server map_server --ros-args -p yaml_filename:=$PWD/<맵>.yaml
ros2 lifecycle set /map_server configure
ros2 lifecycle set /map_server activate
```

---

## 4. ② Nav2 네임스페이스 — 다음

`pinky_navigation/params/nav2_params.yaml`이 네임스페이스를 모릅니다.

```yaml
scan_topic: scan            global_frame_id: "map"
topic: /scan                odom_frame_id: "odom"
                            robot_base_frame: base_footprint
```

핑키 두 대를 올리면 **서로의 라이다를 보고** `map`·`odom` TF가 충돌합니다.
벤더 bridge yaml이 상대 이름을 써서 로봇들이 서로 부딪혔던 것과 같은
문제입니다 — [한 월드에 로봇 여러 대](MULTI_ROBOT_NAMESPACES.md)를 보세요.

로봇마다 갈라야 할 것:

- 토픽 — `/pinky_01/scan`, `/pinky_01/cmd_vel`, `/pinky_01/odom`
- TF 프레임 — `pinky_01/base_footprint`, `pinky_01/odom`
- `map`은 **함께 씁니다.** 같은 건물이니까요

---

## 5. ③ EasyFullControl 어댑터 — 그다음

`rmf_demos_fleet_adapter`(slotcar 전용)를 걷어내고, RMF와 Nav2를 잇는 노드를
둡니다. `rmf_adapter.EasyFullControl`이 Python으로 열려 있습니다.

```python
from rmf_adapter import EasyFullControl
from rmf_adapter.easy_full_control import (
    RobotCallbacks, Destination, RobotState, FleetConfiguration,
)
```

이을 것 둘:

| 방향 | RMF | 로봇 |
|------|-----|------|
| 명령 | `Destination` (nav graph waypoint) | Nav2 `NavigateToPose` |
| 보고 | `RobotState` (위치·배터리·상태) | `/amcl_pose`, 배터리 토픽 |

**이 노드가 실물에서도 그대로 돕니다.** Nav2가 아래에서 Gazebo를 몰든 진짜
모터를 몰든 위쪽은 같기 때문입니다.

---

## 6. ④ 실물 핑키 — 마지막

바뀌는 것은 맨 아래 한 겹입니다.

1. Gazebo 대신 `pinky_bringup`으로 진짜 모터·라이다를 띄웁니다
2. **진짜 건물을 SLAM으로 뜹니다**

```bash
ros2 launch pinky_navigation map_building.launch.xml
ros2 run nav2_map_server map_saver_cli -f rmf_maps/<맵>/nav2_map/<맵>_slam
```

3. **원점을 맞춥니다.** 여기가 유일하게 손이 가는 곳입니다

SLAM 지도의 원점은 **로봇이 SLAM을 시작한 자리**이고, RMF의 원점은 **도면 그림의
왼쪽 위**입니다. `<맵>_slam.yaml`의 `origin:` 세 숫자를 고쳐서 도면에서 만든
`<맵>.yaml`과 같은 자리를 가리키게 합니다.

맞았는지는 **두 그림을 겹쳐 보면** 압니다. 벽이 어긋나면 아직 안 맞은
것입니다. 도면에서 만든 지도가 그대로 기준자 노릇을 합니다 — 이것이 둘 다
만들어 두는 이유입니다.

> 도면이 실제 건물과 충분히 같다면 SLAM 지도 없이 도면 지도를 그대로 써도
> 됩니다. 많은 현장이 그렇게 합니다. 겹쳐 보고 정하면 됩니다.
