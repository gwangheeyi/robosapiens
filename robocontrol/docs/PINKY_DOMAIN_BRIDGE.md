# 도메인 다리 — namespace 이관 전에 두 대를 가르는 법

실제 Pinky 두 대가 아직 루트 토픽(`/cmd_vel` · `/odom` · `/scan`)을 쓰는 동안,
**로봇을 안 고치고** 관제에서만 이름을 가르는 방법이다.

[PINKY_NAMESPACE_MIGRATION.md](PINKY_NAMESPACE_MIGRATION.md) 를 끝낼 수 있으면
그쪽이 맞다. 이 문서는 로봇 workspace 를 아직 못 고칠 때의 **중간 다리**다.

## 1. 무엇이 문제인가

`bringup_robot.launch.xml` 로 띄운 Pinky 는 이름을 루트에 낸다.

```text
pinky1  →  /cmd_vel  /odom  /scan
pinky2  →  /cmd_vel  /odom  /scan     ← 같다
```

같은 도메인에 두 대를 켜면 **둘이 같은 토픽을 쓴다.** `/cmd_vel` 하나에 두 대가
모두 구독하고 있어서, 한 대에게 보낸 명령으로 **두 대가 같이 움직인다.**
`/odom` 은 두 대가 번갈아 발행해 위치가 튄다.

**오류가 안 난다.** 토픽 목록도 정상으로 보이고 `ros2 topic echo` 도 값을 낸다.

## 2. 다리가 하는 일

`domain_bridge` 는 **도메인을 경계**로 쓴다. 로봇마다 다른 도메인에 그대로 두고
(도메인이 다르니 루트 이름을 써도 안 겹친다), 다리가 관제 도메인으로 옮기면서
이름 앞에 namespace 를 붙인다.

```text
도메인 61   /cmd_vel  /odom  /scan        (pinky_01 — 로봇은 그대로)
도메인 62   /cmd_vel  /odom  /scan        (pinky_02 — 로봇은 그대로)
                   ↓  domain_bridge  ↓
도메인 52   /pinky_01/odom   /pinky_02/odom
            /pinky_01/scan   /pinky_02/scan     (관제가 보는 것)
```

로봇에서 바꾸는 것은 **`ROS_DOMAIN_ID` 하나뿐**이다. 펌웨어도 workspace 도 안
고친다.

## 3. 이 다리로 되는 것과 안 되는 것

| | 되나 |
|---|---|
| 토픽 이름 분리 (`/pinky_01/odom`) | **된다** |
| 명령이 한 대에만 가기 (`cmd_vel`) | **된다** |
| 앱에서 두 대 상태를 따로 보기 | **된다** |
| 원격 조종 | **된다** |
| 메시지 안 프레임 이름 분리 | **안 된다** |
| **Nav2 자율주행** | **안 된다** |

### 왜 Nav2 는 안 되나

`domain_bridge` 는 **토픽 이름만 바꾸고 메시지 안은 못 고친다.**

루트 이름을 쓰는 Pinky 는 `/tf` 안의 프레임 이름도 두 대가 똑같다.

```text
pinky1 의 /tf:   odom → base_footprint
pinky2 의 /tf:   odom → base_footprint     ← 같다
```

이것을 관제 도메인으로 옮기면 **두 대의 TF 나무가 한 이름으로 겹쳐** TF 가 두
로봇 사이를 오가며 튄다. 그래서 이 다리는 **`/tf` 를 아예 안 옮긴다.**

Nav2 는 `<로봇>/base_footprint → <로봇>/odom` TF 가 있어야 `local_costmap` 이
활성화된다([REAL_PINKY_STARTUP.md](REAL_PINKY_STARTUP.md) 0절). TF 가 안 오면
15초 뒤에 이렇게 끝난다.

```text
Failed to activate local_costmap because transform from pinky_01/base_footprint
  to pinky_01/odom did not become available before timeout
```

**프레임 이름을 가르는 것은 로봇 쪽 `bringup_namespaced.py` 뿐이다.** 자율주행이
필요하면 namespace 이관을 끝내야 한다.

## 4. 로봇마다 파일이 따로인 까닭

`domain_bridge` 설정의 `topics:` 는 **토픽 이름이 열쇠(key)** 인 맵이다. 이관 전
로봇은 두 대 모두 `/odom` 을 쓰므로, 한 파일에 모으면 열쇠가 겹친다.

```yaml
topics:
  "/odom": { from_domain: 61 }   # pinky_01 — 사라진다
  "/odom": { from_domain: 62 }   # pinky_02 만 남는다
```

YAML 은 뒤엣것이 앞엣것을 덮어쓴다. **오류가 안 나고 한 대가 조용히 빠진다.**

그래서 앱은 로봇마다 파일과 프로세스를 따로 만든다 — 겹칠 열쇠가 애초에 없다.

```text
<맵>_domain_bridge_pinky_01.yaml
<맵>_domain_bridge_pinky_02.yaml
<맵>_domain_bridge.sh              ← 둘을 한꺼번에 띄운다
```

## 5. 준비

### 5.1 다리 패키지

관제 PC 에만 있으면 된다. 로봇에는 필요 없다.

```bash
sudo apt install ros-jazzy-domain-bridge
```

### 5.2 로봇마다 다른 도메인을 정한다

앱의 **로봇 등록**에서 로봇마다 `ROS domain ID` 를 정한다.

```text
프로젝트(관제) 도메인    52
PK-01  pinky_01         61
PK-02  pinky_02         62
```

> [REAL_PINKY_STARTUP.md](REAL_PINKY_STARTUP.md) 2절은 로봇별 도메인을 **비워
> 두라**고 한다. 그것은 namespace 이관이 끝난 뒤의 이야기다. 다리를 쓰는 동안은
> 반대로 **로봇마다 달라야** 한다. 이관이 끝나면 다시 비우고 다리를 내린다.

비워 두거나 관제와 같은 값을 넣으면 그 로봇은 다리에서 빠지고, 생성된 파일에
까닭이 적힌다.

### 5.3 로봇에서 도메인만 바꿔 띄운다

기존 launch 그대로다. `export` 값만 다르다.

```bash
# pinky1
export ROS_DOMAIN_ID=61
ros2 launch pinky_bringup bringup_robot.launch.xml

# pinky2
export ROS_DOMAIN_ID=62
ros2 launch pinky_bringup bringup_robot.launch.xml
```

## 6. 띄우기

앱에서 배포하면 맵 디렉터리에 파일이 생긴다.

```bash
cd <맵 디렉터리>
./<맵>_domain_bridge.sh          # 띄운다
./<맵>_domain_bridge.sh stop     # 내린다
```

로봇 수만큼 프로세스가 뜬다. 하나가 죽어도 나머지는 살아 있다.

## 7. 확인

관제 PC 에서, 관제 도메인으로.

```bash
export ROS_DOMAIN_ID=52
ros2 topic list | grep pinky
```

이렇게 보여야 한다.

```text
/pinky_01/odom
/pinky_01/scan
/pinky_02/odom
/pinky_02/scan
```

**이름만 보고 끝내지 않는다.** 값이 실제로 오는지 본다 — 다리가 광고만 하고
아무것도 안 옮기는 상태가 실제로 있었다
([MULTI_ROBOT_NAMESPACES.md](MULTI_ROBOT_NAMESPACES.md) 8절).

```bash
ros2 topic hz /pinky_01/odom
ros2 topic hz /pinky_02/odom
```

### 한 대만 움직이는지

가장 중요한 확인이다. 이것이 애초에 고치려던 문제다.

```bash
export ROS_DOMAIN_ID=52
ros2 topic pub /pinky_01/cmd_vel geometry_msgs/msg/Twist \
  '{linear: {x: 0.1}}' --rate 10
```

**pinky1 만 움직여야 한다.** 둘 다 움직이면 두 로봇이 아직 같은 도메인에 있는
것이다. 로봇에서 `echo $ROS_DOMAIN_ID` 를 확인한다.

### 루트 토픽이 관제에 새지 않는지

```bash
export ROS_DOMAIN_ID=52
ros2 topic list | grep -E '^/(cmd_vel|odom|scan)$'
```

아무것도 안 나와야 한다. 나오면 로봇 한 대가 관제 도메인(52)에 그대로 있는
것이다.

## 8. 이관이 끝나면

`bringup_robot_namespaced.launch.xml` 이 로봇마다 설치·빌드되면 이 다리는
필요 없다.

1. `./<맵>_domain_bridge.sh stop`
2. 앱 로봇 등록에서 로봇별 `ROS domain ID` 를 **비운다**
3. 로봇도 관제도 같은 도메인(52)을 쓴다
4. 로봇을 `bringup_robot_namespaced.launch.xml namespace:=pinky_01` 로 띄운다

그러면 프레임 이름까지 갈려서 Nav2 가 뜬다.

## 9. 점검표

- [ ] 관제 PC 에 `ros-jazzy-domain-bridge` 가 있는가
- [ ] 로봇마다 **서로 다른** 도메인인가 (관제와도 달라야 한다)
- [ ] 로봇에서 `echo $ROS_DOMAIN_ID` 가 등록값과 같은가
- [ ] 관제 도메인에서 `/pinky_01/odom` 에 **값이 오는가** (`topic hz`)
- [ ] `/pinky_01/cmd_vel` 로 **한 대만** 움직이는가
- [ ] 관제 도메인에 루트 `/odom` `/cmd_vel` 이 안 보이는가
- [ ] Nav2 를 쓰려는 것은 아닌가 (이 다리로는 안 된다 — 3절)
