# 앱에서 로봇 브링업 띄우기 (SSH · 자동 실행)

실물 Pinky 는 앱이 도는 PC 가 아니라 **제 안에서** 하드웨어를 연다 — 라이다는
`/dev/ttyAMA0`, 모터는 `/dev/ttyAMA4` 다. 그래서 지금까지는 사람이 로봇에
들어가 손으로 launch 를 쳤고, 그 자리에서 자주 어긋났다.

**어긋나도 오류가 안 난다.** 이것이 이 문서가 있는 까닭이다.

## 0. 무엇이 문제였나

2026-08-19 에 실제로 겪은 일이다. 라이다가 10Hz 로 멀쩡히 돌고 있는데 지도에는
아무것도 안 그려졌다. 원인을 라이다와 AMCL 에서 찾느라 한참을 썼는데, 정작
원인은 브링업을 **namespace 없이** 띄운 것이었다.

```text
로봇이 발행:   /scan          ← 루트
Nav2 가 구독:  /pinky_03/scan ← namespace
```

이름이 어긋나면 토픽 목록에는 둘 다 보이고, 퍼블리셔 수만 0 이다. 오류는
어디에도 안 난다.

같은 날 도메인으로도 한 번 더 겪었다. 백엔드는 `ROS_DOMAIN_ID=12` 에서 도는데
확인은 도메인 0 에서 해서, 노드가 하나도 없는 것처럼 보였다.

두 값 모두 **로봇 등록에 이미 있다.** 사람이 다시 칠 이유가 없다.

## 1. 준비 — SSH 키 (한 번만)

앱에는 비밀번호를 칠 자리가 없다. `ssh` 는 비밀번호를 터미널에서만 읽는데,
앱이 프로세스로 띄우면 입력할 화면이 없어 **물어보는 순간 영영 멈춘다.**
그래서 앱은 `BatchMode=yes` 로 붙는다 — 물어봐야 하는 상황이면 빨리 실패하고
무엇을 하라고 알려 준다.

키가 없으면 만든다.

```bash
ls ~/.ssh/id_ed25519.pub 2>/dev/null || ssh-keygen -t ed25519
```

세 번 묻는 것을 **전부 Enter** 로 넘긴다.

- 저장 위치 → 기본값(`~/.ssh/id_ed25519`)
- passphrase → **비워 둔다**
- 확인 → 비워 둔다

> **passphrase 를 넣으면 앱에서 못 쓴다.** 키를 쓸 때마다 그 암호를 묻는데,
> 그것이 비밀번호와 똑같은 문제가 된다.

`No identities found` 는 키가 아직 없다는 뜻이다. 위 `ssh-keygen` 을 먼저 한다.

로봇에 키를 올린다. **여기서만** 로봇 비밀번호를 한 번 묻는다.

```bash
ssh-copy-id pinky@192.168.0.22
```

확인한다.

```bash
ssh -o BatchMode=yes pinky@192.168.0.22 echo OK
```

`OK` 만 나오면 앱에서도 된다. 비밀번호를 다시 묻거나 `Permission denied` 가
나오면 아직이다.

## 2. 준비 — sudo 비밀번호 면제 (자동 실행을 쓸 때만)

`켤 때 자동 실행` 은 systemd 유닛을 `/etc/systemd/system/` 에 넣으므로 `sudo`
가 필요하다. 이것도 같은 이유로 비밀번호를 못 받는다.

로봇에서 한 번만 한다.

```bash
echo "pinky ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/bin/install, /bin/rm" \
  | sudo tee /etc/sudoers.d/robosapiens
```

`브링업 띄우기` 만 쓸 것이면 이 절은 건너뛴다.

## 3. 로봇 등록에 주소 넣기

앱 → 로봇 관리 → 로봇 등록. **실물 이동 로봇일 때만** SSH 칸이 보인다.

| 칸 | 예시 | 설명 |
|---|---|---|
| 로봇 주소 (SSH) | `192.168.0.22` | 비우면 SSH 를 안 쓴다 |
| 계정 | `pinky` | 비우면 PC 의 계정으로 붙는다 |
| 로봇 안의 워크스페이스 | `~/pinky_pro` | `install/setup.bash` 가 그 아래 있어야 한다 |

## 4. 띄우기

로봇 상세 → **로봇 브링업** → `브링업 띄우기`.

앱이 로봇에서 이 명령을 돌린다. **namespace 와 도메인은 등록값에서 나온다.**

```bash
export ROS_DOMAIN_ID=12                                   # 등록된 도메인
source /opt/ros/jazzy/setup.bash
source ~/pinky_pro/install/setup.bash
pkill -f 'bringup_robot_namespaced.*pinky_03' || true     # 이미 떠 있으면 내리고
sleep 2                                                    # 시리얼이 풀리기를 기다림
setsid nohup ros2 launch pinky_bringup \
  bringup_robot_namespaced.launch.xml \
  namespace:=pinky_03 > /tmp/pinky_03_bringup.log 2>&1 &
```

몇 가지가 일부러 들어 있다.

- **`pkill` + `sleep 2`** — 같은 시리얼 포트를 두 프로세스가 잡을 수 없다.
  이미 떠 있는데 또 띄우면 나중 것이 조용히 실패하고 토픽만 남는다.
- **`setsid nohup`** — SSH 가 끊겨도 브링업은 계속 돈다. 앱을 닫았다고 로봇이
  멈추면 안 된다.
- **로그를 파일로** — 실패하면 앱이 `/tmp/<로봇>_bringup.log` 를 읽어와 오류
  창에 함께 보여 준다. 로봇에 다시 들어갈 일이 없다.

`내리기` 는 이 로봇의 브링업만 골라 내린다.

## 5. 켤 때 자동 실행

로봇 상세 → **로봇 브링업** → `켤 때 자동 실행`.

유닛은 **앱이 만든다.** 사람이 로봇 안에서 손으로 쓰면 `namespace` 와 도메인을
거기에 또 적게 되고, 앱에서 값을 바꿔도 그 파일은 그대로 남아 조용히 어긋난다.

```ini
[Unit]
Description=Robosapiens bringup for pinky_03
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pinky
Environment=ROS_DOMAIN_ID=12
ExecStart=/bin/bash -lc 'source /opt/ros/jazzy/setup.bash; ... namespace:=pinky_03'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

- **`Restart=on-failure`** — 부팅 직후에는 시리얼 장치가 아직 안 올라와 있을 수
  있다. 한 번 죽고 끝나면 로봇은 켜졌는데 토픽은 안 오는 상태로 남는다.
- **`After=network-online.target`** — 망 없이 뜨면 DDS 가 같은 도메인의 다른
  노드를 못 보고, 나중에 망이 붙어도 그 상태가 그대로 간다.

같은 파일이 배포 산출물로도 나간다 — `robots/<로봇>/bringup.service`. SSH 를
안 쓰는 로봇에는 이 파일을 손으로 올리면 된다.

> **등록에서 namespace 나 도메인을 바꾸면 로봇의 유닛은 옛날 것이다.**
> `자동 실행 다시 설치` 를 눌러 새 값으로 갈아 끼운다.

## 6. 순서 — 로봇이 먼저, 백엔드가 나중

```text
① 로봇 브링업 (또는 자동 실행)
② /scan · /odom 이 나오는지 확인
③ 백엔드 시작
④ 작업 실행
```

**이 순서가 중요하다.** 반대로 하면 Nav2 의 `local_costmap` 이 활성화할 때
`<로봇>/odom` TF 를 못 찾아 실패하고, `lifecycle_manager` 는 거기서 멈춰
**뒤의 노드를 시도조차 하지 않는다.**

```text
Failed to activate local_costmap because transform from
  pinky_03/base_footprint to pinky_03/odom did not become available
Failed to change state for node: controller_server
Failed to bring up all requested nodes. Aborting bringup.
```

그러면 `amcl` 만 `active` 고 나머지는 `inactive` 로 남는다. 작업을 넣으면
어댑터가 `Nav2 가 거절했습니다` 한 줄만 남기고 끝난다 — `bt_navigator` 가
inactive 라 `navigate_to_pose` action 자체가 없기 때문이다.

앱이 백엔드를 띄운 뒤 이것을 스스로 확인하고 안 켜졌으면 되살린다
([nav2_lifecycle.dart](../lib/nav2_lifecycle.dart)). 그래도 **순서를 지키면
애초에 그럴 일이 없다.**

자세한 것은 [REAL_PINKY_STARTUP.md](REAL_PINKY_STARTUP.md) 0절과 7절에 있다.

## 7. 스폰은 안 한다

실물 로봇에는 "스폰" 이 없다. 스폰은 Gazebo 에 모델을 올리는 일이고, 실물은
이미 그 자리에 있다.

앱은 로봇이 토픽을 내기 시작하면 **지금 있는 자리**에 지도에 올린다. `Spawn`
을 누르면 오히려 충전 자리에 놓여 실제와 어긋난다.

로봇을 손으로 옮겨 위치를 잃었을 때는 로봇 상세의
`이 자리를 초기 위치로 보내기` 를 쓴다. 그것도 **로봇을 그 자리에 놓은 뒤에**
누른다 — 보내는 것은 좌표뿐이고 로봇은 안 움직인다.

## 8. 안 될 때

| 증상 | 볼 곳 |
|---|---|
| `No identities found` | 키가 없다. 1절의 `ssh-keygen` |
| 비밀번호를 묻는다 | `ssh-copy-id` 를 아직 안 했다 |
| `Permission denied` | 계정 이름이 틀렸거나 키가 안 올라갔다 |
| 붙었는데 브링업 실패 | 워크스페이스 경로, `pinky_bringup` 빌드 여부. 오류 창의 로봇 로그를 본다 |
| 자동 실행 설치 실패 | 2절의 sudo 면제 |
| 토픽이 루트(`/scan`)로 나온다 | `namespace:=` 없이 손으로 띄운 것이다 |
| 토픽이 아무것도 안 보인다 | `ROS_DOMAIN_ID` 가 등록값과 같은지 |
| `scan`·`odom` 이 안 나온다 | 시리얼 포트를 다른 프로세스가 잡고 있다 |

로봇에서 직접 볼 때는 도메인을 맞춰야 한다.

```bash
export ROS_DOMAIN_ID=12
ros2 topic echo /pinky_03/scan --once | head -5
ros2 topic echo /pinky_03/odom --once | head -5
```

> `ros2 topic hz` 는 기본 QoS 가 RELIABLE 이라 라이다(BEST_EFFORT)에는 값이 안
> 온다. 토픽 이름만 있고 `hz` 가 침묵하는 것이 **정상일 수 있다** — `echo` 로
> 확인한다.

## 9. 보안

앱은 비밀번호를 저장하지 않는다. DB 나 설정 파일에 평문으로 남고 로봇이 여러
대면 그만큼 늘어나기 때문이다. SSH 키가 표준이고 더 안전하다.

`StrictHostKeyChecking=accept-new` 를 쓴다 — 처음 보는 로봇의 키를 묻지 않고
받는다. 묻는 순간 역시 멈추기 때문이고, 사내망의 로봇을 전제로 한 선택이다.
