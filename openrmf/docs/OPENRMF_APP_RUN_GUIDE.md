# openrmf_app 실행 가이드

이 문서는 Open-RMF 기본 office 시뮬레이션의 로봇 상태를 `rmf-web` API를
거쳐 Flutter 관제 화면에서 확인하는 순서를 설명합니다.

```text
Open-RMF office
  -> rmf-web 내부 WebSocket (ws://127.0.0.1:8000/_internal)
  -> rmf-web REST API (http://127.0.0.1:8000)
  -> openrmf_app
```

## 1. 사전 준비 확인

필요한 구성은 다음과 같습니다.

- Ubuntu 24.04
- ROS 2 Jazzy
- 빌드된 Open-RMF workspace: 기본값 `$HOME/rmf_ws`
- Docker
- Flutter Linux desktop

설치 상태를 확인합니다.

```bash
source /opt/ros/jazzy/setup.bash
source "$HOME/rmf_ws/install/setup.bash"

ros2 pkg prefix rmf_demos_gz
ros2 pkg prefix rmf_demos_fleet_adapter
docker info
flutter doctor
```

`docker info`가 권한 오류를 출력하면 현재 사용자를 Docker 그룹에 추가한 후
로그아웃하고 다시 로그인합니다.

```bash
sudo usermod -aG docker "$USER"
```

Flutter에서 Linux desktop이 비활성화되어 있다면 활성화합니다.

```bash
flutter config --enable-linux-desktop
flutter doctor
```

## 2. 자동 실행

가장 간단한 실행 방법입니다.

```bash
cd /home/gyi/robosapiens
./openrmf/scripts/run_office_flutter.sh
```

스크립트는 다음 작업을 순서대로 수행합니다.

1. `$HOME/rmf_ws/install/setup.bash` 존재 여부 확인
2. `rmf-web` API가 이미 실행 중인지 확인
3. API가 없으면 공식 `api-server:jazzy` Docker 컨테이너 실행
4. API의 `/time` 응답 대기
5. ROS 2 Jazzy와 Open-RMF workspace 환경 적용
6. office 시뮬레이션 실행
7. building map이 API에 등록될 때까지 대기
8. Flutter 의존성 확인 후 Linux 앱 실행

정상적으로 연결되면 Flutter 상단에 `API ONLINE`이 표시되고 office 지도 위에
`tinyRobot1`, `tinyRobot2`가 나타납니다.

## 3. 수동 실행

구성요소별 로그를 따로 확인하려면 세 개의 터미널을 사용합니다.

### 터미널 1: rmf-web API

```bash
docker run --rm \
  --name robosapiens-rmf-api \
  --network host \
  --ipc host \
  -e ROS_DOMAIN_ID=0 \
  -e RMW_IMPLEMENTATION=rmw_fastrtps_cpp \
  -e FASTDDS_BUILTIN_TRANSPORTS=UDPv4 \
  -e RMF_SERVER_USE_SIM_TIME=true \
  ghcr.io/open-rmf/rmf-web/api-server:jazzy
```

API 응답과 문서를 확인합니다.

```bash
curl http://127.0.0.1:8000/time
```

브라우저 API 문서:

```text
http://127.0.0.1:8000/docs
```

### 터미널 2: Open-RMF office

```bash
cd /home/gyi/robosapiens

source /opt/ros/jazzy/setup.bash
source "$HOME/rmf_ws/install/setup.bash"

ros2 launch openrmf/launch/office_web.launch.xml \
  server_uri:=ws://127.0.0.1:8000/_internal
```

이 launch 파일은 dispatcher와 `tinyRobot` fleet adapter 양쪽에 rmf-web 주소를
전달합니다.

### 터미널 3: Flutter 관제 앱

```bash
cd /home/gyi/robosapiens/openrmf_app
flutter pub get
flutter run -d linux \
  --dart-define=RMF_API_URL=http://127.0.0.1:8000
```

로컬 개발 환경에서는 rmf-web 공식 개발용 관리자 토큰이 기본 적용됩니다.
인증 서버를 사용하는 환경에서는 발급받은 토큰을 지정합니다.

```bash
flutter run -d linux \
  --dart-define=RMF_API_URL=https://rmf.example.com \
  --dart-define=RMF_API_TOKEN="$ACCESS_TOKEN"
```

## 4. 정상 작동 확인

다음 항목을 순서대로 확인합니다.

1. Gazebo에 office 공간과 `tinyRobot1`, `tinyRobot2`가 표시되는지 확인
2. Flutter 상단 연결 상태가 `API ONLINE`인지 확인
3. 왼쪽 로봇 목록에 두 로봇이 표시되는지 확인
4. 지도 위 로봇 마커가 Gazebo 로봇 이동에 맞춰 갱신되는지 확인
5. 오른쪽 `TASK ACTIVITY`에 RMF 태스크가 표시되는지 확인

로봇 이동을 확인하려면 별도 터미널에서 patrol 태스크를 요청합니다.

```bash
source /opt/ros/jazzy/setup.bash
source "$HOME/rmf_ws/install/setup.bash"

ros2 run rmf_demos_tasks dispatch_patrol \
  -p coe lounge \
  -n 3 \
  --use_sim_time
```

태스크가 배정되면 Flutter에서 로봇 상태가 `작업 중`으로 바뀌고, 지도 마커가
이동하며 오른쪽 태스크 목록에 진행 상태가 표시됩니다.

## 5. 종료

자동 실행 중에는 Flutter 터미널에서 `q`를 누르거나 `Ctrl+C`를 입력합니다.
통합 스크립트가 자신이 실행한 ROS 프로세스와 API 컨테이너를 함께 종료합니다.

수동 실행한 경우 다음 순서로 종료합니다.

1. Flutter 터미널에서 `q` 또는 `Ctrl+C`
2. office launch 터미널에서 `Ctrl+C`
3. API 터미널에서 `Ctrl+C`

백그라운드 API 컨테이너가 남아 있다면 다음 명령으로 종료합니다.

```bash
docker stop robosapiens-rmf-api
```

## 6. 문제 해결

### `Docker daemon is not accessible`

```bash
docker info
groups
```

현재 사용자가 Docker 그룹에 포함되어 있는지 확인합니다. 그룹을 변경한 직후에는
로그아웃과 재로그인이 필요합니다.

### Flutter에 `API OFFLINE` 표시

```bash
curl http://127.0.0.1:8000/time
docker logs robosapiens-rmf-api
```

API 주소가 다른 경우 `RMF_API_URL`을 실제 주소로 지정합니다.

### API는 연결됐지만 로봇이 표시되지 않음

office launch가 API 내부 WebSocket 주소를 받았는지 확인합니다.

```bash
ros2 topic echo /fleet_states
```

`/fleet_states`에 데이터가 있지만 Flutter가 비어 있다면 API 컨테이너와 ROS의
`ROS_DOMAIN_ID`, `RMW_IMPLEMENTATION` 값이 같은지 확인합니다.

현재 설치된 RMW 구현은 다음 명령으로 확인할 수 있습니다.

```bash
ros2 doctor --report | grep -A2 "RMW MIDDLEWARE"
```

이 시스템의 기본 구현은 `rmw_fastrtps_cpp`입니다. 통합 실행 스크립트는 설치된
Fast DDS 또는 CycloneDDS 라이브러리를 자동으로 찾아 선택합니다.

Fast DDS 사용 시 스크립트는 `FASTDDS_BUILTIN_TRANSPORTS=UDPv4`를 ROS와 API
컨테이너에 함께 설정합니다. 호스트와 컨테이너가 서로 다른 공유 메모리를 사용해
building map이나 fleet state를 발견하지 못하는 문제를 방지하기 위한 설정입니다.

### building map이 표시되지 않음

```bash
ros2 topic echo /map --once
```

Flutter 앱을 먼저 실행했다면 office launch가 완전히 올라온 뒤 새로고침 버튼을
누릅니다. 앱은 기본적으로 1초마다 자동 갱신합니다.

### Open-RMF workspace가 다른 위치에 있음

자동 실행 전에 `RMF_WS`를 지정합니다.

```bash
RMF_WS=/path/to/rmf_ws ./openrmf/scripts/run_office_flutter.sh
```

### API 또는 ROS가 다른 장비에서 실행됨

```bash
RMF_API_URL=http://192.168.0.20:8000 \
RMF_SERVER_URI=ws://192.168.0.20:8000/_internal \
./openrmf/scripts/run_office_flutter.sh
```

방화벽에서 TCP `8000` 포트와 ROS 2 DDS 통신이 허용되어야 합니다.
