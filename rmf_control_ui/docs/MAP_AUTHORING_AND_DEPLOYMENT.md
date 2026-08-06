# RMF Control UI 맵 작성 및 배포 가이드

## 1. 문서 목적

이 문서는 `rmf_control_ui`에서 창고 맵을 작성하는 순서와 `배포하기` 버튼이
실제로 수행하는 작업을 설명합니다.

맵 작성과 배포는 서로 다른 작업입니다.

- **맵 작성**: 도면 위에 축척, Floor, Wall, Lane, Waypoint를 정의하고
  `building.yaml`을 만드는 과정입니다.
- **배포**: 작성 결과를 Open-RMF가 읽을 수 있는 파일로 생성·설치하고,
  Building Map Server와 Fleet Adapter가 새 파일을 사용하도록 재시작하는
  과정입니다.

따라서 화면에 맵을 모두 그렸더라도 배포하지 않으면 실행 중인 Open-RMF와
로봇은 새 맵을 사용하지 않습니다.

## 2. 사전 준비

실제 배포에는 다음 환경이 필요합니다.

- Linux 데스크톱에서 실행한 `rmf_control_ui`
- ROS 2 Jazzy: `/opt/ros/jazzy/setup.bash`
- 빌드된 Open-RMF workspace: 기본값 `$HOME/rmf_ws`
- `rmf_building_map_tools`
- Fleet Adapter 설정 파일
- 프로젝트 안의 `openrmf/scripts`와 `rmf_maps` 디렉터리

프로젝트 루트는 다음 순서로 찾습니다.

1. `RMF_ROOT` 환경 변수
2. 앱의 현재 실행 디렉터리와 상위 디렉터리

프로젝트를 다른 위치에서 실행한다면 명시적으로 지정하는 편이 안전합니다.

```bash
export RMF_ROOT=/home/gyi/robosapiens
export RMF_WS=$HOME/rmf_ws
cd "$RMF_ROOT/rmf_control_ui"
flutter run -d linux
```

## 3. 맵 작성 단계

### 3.1 도면 업로드

`도면 올리기`를 눌러 PNG 또는 JPG 도면을 선택합니다.

- 이미지 원본은 YAML의 `drawing.filename`에 기록됩니다.
- PDF와 CAD 파일은 선택할 수 있지만 Wall/Floor 자동 처리를 위해서는 PNG 또는
  JPG 변환이 필요합니다.
- 실제 배포에는 이미지 바이트가 포함된 PNG 또는 JPG가 필요합니다.

### 3.2 Measurement 설정

도면에서 실제 길이를 알고 있는 두 점을 선택하고 미터 또는 피트 값을
입력합니다. 이 값으로 픽셀 좌표를 실제 거리로 변환합니다.

축척이 잘못되면 로봇 속도, Lane 거리, 도착 판정이 모두 비정상적으로 보일 수
있으므로 실제 현장 치수와 반드시 비교해야 합니다.

### 3.3 Wall 인식 및 수정

`벽 인식`으로 이미지의 어두운 선을 Wall 후보로 추출합니다.

- 잘못 인식한 Wall은 지우기 도구로 제거합니다.
- 끊어진 Wall은 정점을 연결합니다.
- Wall 끝점은 실제 도면 경계에 맞게 이동합니다.
- 로봇 Lane이 Wall을 통과하지 않는지 확인합니다.

### 3.4 Floor 생성

`Floor 생성`으로 로봇이 운행할 층 영역을 만듭니다. Floor 경계에는 최소 3개의
정점이 필요합니다.

### 3.5 Lane 만들기

Waypoint를 순서대로 선택하여 Lane을 만듭니다.

- `양방향`: 시작점과 끝점 사이를 모두 이동할 수 있습니다.
- `정방향`: 시작점에서 끝점으로만 이동합니다.
- `역방향`: 끝점에서 시작점으로만 이동합니다.
- Lane을 클릭하면 방향 변경 또는 삭제가 가능합니다.
- `Esc`를 누르면 현재 Lane 입력을 종료하고 새 시작점을 선택할 수 있습니다.

모든 Waypoint가 하나의 연결된 Lane 네트워크에 포함되어야 합니다. 예를 들어
`대기17 ↔ 충전1`만 서로 연결되고 다른 Lane과 연결되지 않았다면 두 지점은
작은 섬처럼 고립되어 주 네트워크에서 접근할 수 없습니다.

### 3.6 Waypoint 설정

Waypoint를 클릭해 이름과 카테고리를 설정합니다.

- 일반
- 대기
- 충전
- 픽업
- 드랍오프

Waypoint 이름은 중복되지 않게 작성하는 것을 권장합니다. 화면에서는 이름이
서로 겹치지 않도록 오른쪽, 왼쪽, 위, 아래 순서로 빈 위치를 찾아 표시합니다.

## 4. 검증과 경로 추천

### 4.1 오류 검증

상단의 `오류 검증` 버튼은 현재 편집 상태에서 다음 항목을 검사합니다.

- Measurement 누락
- Floor 정점 부족
- Lane 누락
- 시작점과 끝점이 같은 Lane
- 주 네트워크에서 분리된 Waypoint
- 중복된 Waypoint 이름

검증 결과는 팝업으로 표시되며 `결과 복사`로 전체 내용을 복사할 수 있습니다.
배포를 막는 Warning이 있으면 먼저 맵을 수정해야 합니다.

### 4.2 경로 추천

`경로 추천` 버튼은 다음 후보를 계산합니다.

- 분리된 Lane 구역을 주 네트워크와 연결하는 Lane
- 일반 Waypoint의 막다른 경로에 추가할 우회 Lane

Wall과 교차하는 후보는 추천에서 제외됩니다. 팝업에서 적용할 항목을 선택하고
각 Lane 방향을 수정한 뒤 `선택 적용`을 누릅니다. 추천은 기하학적·연결성
분석이므로 실제 적재물, 안전구역, 로봇 회전반경까지 보장하지 않습니다. 적용
전에 현장 통행 가능 여부를 확인해야 합니다.

## 5. 작업 저장과 YAML 내보내기

### 작업 저장

`작업 저장`은 편집 가능한 `.rmfproject` 파일을 저장합니다. 나중에
`작업 불러오기`로 Wall, Floor, Lane, Waypoint 편집 상태를 복원할 수 있습니다.

### 맵 다운로드

`맵 다운로드`에서는 다음 작업이 가능합니다.

- `.building.yaml` 파일 다운로드
- YAML 전체 내용을 클립보드에 복사

생성되는 Lane에는 Open-RMF nav graph 생성을 위한 속성이 포함됩니다.

```yaml
bidirectional: [4, true]
graph_idx: [2, 0]
```

`graph_idx: [2, 0]`은 해당 Lane을 nav graph `0`에 포함한다는 의미입니다.

## 6. 배포의 의미

이 프로젝트에서 배포는 단순히 `배포 완료` 상태를 화면에 표시하는 작업이
아닙니다. 작성한 맵을 Open-RMF 실행 파일로 변환하고, 실행 중인 RMF 노드가
새 파일을 읽도록 교체하는 작업입니다.

전체 흐름은 다음과 같습니다.

```text
오류 검증
    ↓
building.yaml 및 이미지 준비
    ↓
nav graph 및 Gazebo world/model 생성
    ↓
rmf_maps/<맵 이름>에 설치
    ↓
Building Map Server 재시작
    ↓
Fleet Adapter 재시작
    ↓
/get_building_map 서비스 및 프로세스 확인
```

실제 작업은 다음 스크립트가 담당합니다.

```text
openrmf/scripts/deploy_map.sh
```

## 7. 배포 버튼의 실제 처리 순서

### 7.1 오류 검증

UI 검증을 먼저 실행합니다. Warning이 있으면 배포를 중단하고 화면 하단에 복사
가능한 메시지를 표시합니다.

배포 스크립트도 입력 파일 존재 여부와 YAML의 기본 `levels`, `name` 항목을 다시
검사합니다.

### 7.2 임시 배포 파일 생성

Flutter 앱은 운영체제 임시 디렉터리에 다음 파일을 작성합니다.

```text
<맵 이름>.building.yaml
<원본 이미지 이름>.png
```

임시 파일은 배포 명령 종료 후 삭제됩니다.

### 7.3 nav graph 생성

다음 RMF 도구를 실행합니다.

```bash
ros2 run rmf_building_map_tools building_map_generator nav \
  <맵 이름>.building.yaml nav_graphs
```

정상적으로 생성되면 다음 파일이 있어야 합니다.

```text
nav_graphs/0.yaml
```

Fleet Adapter는 이 파일을 사용해 Waypoint와 Lane 연결 관계를 계산합니다.

### 7.4 Gazebo world 및 모델 생성

다음 명령으로 시뮬레이션용 World와 층 모델을 생성합니다.

```bash
ros2 run rmf_building_map_tools building_map_generator gazebo \
  <맵 이름>.building.yaml \
  <맵 이름>.world \
  generated_models
```

이 단계는 파일을 생성하는 작업입니다. 현재 실행 중인 Gazebo World를 자동으로
교체하거나 Gazebo를 재시작하지는 않습니다.

### 7.5 프로젝트 맵 디렉터리에 설치

새 맵은 다음 위치에 설치됩니다.

```text
<프로젝트 루트>/rmf_maps/<맵 이름>/
├── <맵 이름>.building.yaml
├── <원본 이미지>
├── <맵 이름>.world
├── nav_graphs/
│   └── 0.yaml
└── generated_models/
```

같은 이름의 기존 디렉터리가 있으면 먼저 다음 위치로 이동합니다.

```text
rmf_maps/.backups/<맵 이름>-YYYYMMDD-HHMMSS/
```

따라서 파일 생성이 완료되기 전에 기존 맵을 바로 덮어쓰지 않습니다.

### 7.6 Building Map Server 재시작

현재 사용자 계정으로 실행 중인 `building_map_server`를 종료한 뒤 새
`building.yaml`로 시작합니다.

PID와 로그는 다음 위치에 저장됩니다.

```text
openrmf/.runtime/building_map_server.pid
openrmf/.runtime/building_map_server.log
```

Map Server는 RMF 시스템과 대시보드에 Floor, Wall, Lane, Waypoint 정보를
제공합니다.

### 7.7 Fleet Adapter 재시작

현재 사용자 계정의 RMF demo Fleet Manager와 Fleet Adapter를 종료하고 새
`nav_graphs/0.yaml`로 시작합니다.

기본 Fleet 설정은 다음 파일입니다.

```text
$RMF_WS/install/rmf_demos/share/rmf_demos/config/office/tinyRobot_config.yaml
```

실제 로봇 Fleet 설정을 사용하려면 앱을 시작하기 전에 지정합니다.

```bash
export RMF_FLEET_CONFIG=/절대/경로/my_fleet_config.yaml
```

로그와 PID는 다음 위치에 저장됩니다.

```text
openrmf/.runtime/fleet_adapter.pid
openrmf/.runtime/fleet_adapter.log
```

### 7.8 새 지도 수신 확인

배포 스크립트는 최대 약 15초 동안 다음 조건을 확인합니다.

- `/get_building_map` ROS 2 서비스가 나타나는지
- 새 Building Map Server 프로세스가 살아 있는지
- 새 Fleet Adapter launch 프로세스가 살아 있는지

모두 확인된 경우에만 UI를 `배포 완료` 상태로 변경합니다.

## 8. 환경 변수

| 변수 | 기본값 | 의미 |
| --- | --- | --- |
| `RMF_ROOT` | 현재 디렉터리에서 자동 탐색 | 프로젝트 루트 |
| `RMF_WS` | `$HOME/rmf_ws` | Open-RMF workspace |
| `RMF_FLEET_CONFIG` | Office tinyRobot 설정 | Fleet Adapter 설정 파일 |
| `RMF_SERVER_URI` | `ws://127.0.0.1:8000/_internal` | rmf-web 내부 WebSocket |
| `RMF_USE_SIM_TIME` | `true` | ROS simulation time 사용 여부 |

실제 로봇에서 실행할 때는 일반적으로 다음과 같이 설정합니다.

```bash
export RMF_USE_SIM_TIME=false
export RMF_FLEET_CONFIG=/path/to/production_fleet.yaml
```

## 9. 배포 성공 후 확인할 항목

배포 성공은 파일 생성과 RMF 노드 시작이 확인됐다는 의미입니다. 로봇 운행의
정상 동작까지 자동으로 보장하는 것은 아닙니다.

다음 항목을 추가로 확인해야 합니다.

1. 대시보드에 새 맵 이름과 `L1`이 표시되는지
2. 로봇의 현재 좌표가 맵 위의 실제 위치와 일치하는지
3. 모든 작업 Waypoint로 이동할 수 있는지
4. 충전 Waypoint에 진입하고 빠져나올 수 있는지
5. 단방향 Lane을 반대로 주행하지 않는지
6. Wall이나 안전구역을 통과하는 경로가 없는지
7. 실제 로봇의 footprint와 회전반경에 충분한 공간이 있는지

## 10. 실패 메시지와 로그

배포가 실패하면 결과 팝업과 화면 하단 Warning에 전체 로그가 표시됩니다.
`로그 복사` 또는 Warning의 `복사` 버튼을 이용할 수 있습니다.

배포 버튼을 누를 때마다 성공·실패와 관계없이 프로젝트 메인 디렉터리에 전체
배포 로그를 저장합니다.

```text
<프로젝트 루트>/map-deploy-YYYYMMDD-HHMMSS.log
```

예를 들면 다음과 같습니다.

```text
/home/gyi/robosapiens/map-deploy-20260806-143025.log
```

이 파일에는 배포 시작 시각, 맵 이름, 7단계 실행 내용, RMF 생성 도구 출력과
오류 메시지가 함께 기록됩니다.

터미널에서는 다음 로그를 직접 확인할 수 있습니다.

```bash
tail -n 100 openrmf/.runtime/building_map_server.log
tail -n 100 openrmf/.runtime/fleet_adapter.log
```

자주 발생하는 문제는 다음과 같습니다.

### `nav_graphs/0.yaml이 생성되지 않았습니다`

Lane이 없거나 Lane의 `graph_idx`가 누락된 경우입니다. UI에서 Lane을 만들고
YAML을 다시 생성합니다.

### Fleet 설정 파일을 찾을 수 없음

`RMF_FLEET_CONFIG`가 올바른 절대 경로인지 확인합니다.

### `/get_building_map` 서비스를 확인하지 못함

Building Map Server 로그에서 YAML 파싱 오류, 이미지 경로 오류, ROS domain
설정을 확인합니다.

```bash
ros2 service list | grep get_building_map
```

### 대시보드에는 새 맵이 보이지만 로봇이 움직이지 않음

다음 항목이 서로 일치하는지 확인합니다.

- Fleet Adapter의 nav graph
- Fleet 설정의 로봇 이름과 충전 Waypoint
- 로봇이 보고하는 level 이름
- `RMF_SERVER_URI`
- `ROS_DOMAIN_ID`

## 11. 백업에서 복구

배포 전 맵은 `rmf_maps/.backups`에 보관됩니다. 자동 롤백은 하지 않으므로 복구가
필요하면 RMF 서비스를 중지한 상태에서 현재 맵 디렉터리와 백업 디렉터리를
확인한 뒤 이전 버전을 복원해야 합니다.

백업 경로를 잘못 선택하면 현재 맵을 잃을 수 있으므로 디렉터리 이름과 생성
시각을 확인하고 작업하십시오.

## 12. 현재 배포 범위와 제한

- 실제 배포는 Linux 데스크톱 앱에서만 지원합니다.
- 웹 앱은 보안상 로컬 스크립트와 ROS 2 프로세스를 실행할 수 없습니다.
- World와 모델은 생성하지만 실행 중인 Gazebo를 자동 재시작하지 않습니다.
- 기본 Fleet 설정은 Office `tinyRobot` 데모용입니다. 실제 로봇에는 운영 Fleet
  설정을 반드시 지정해야 합니다.
- `/get_building_map` 확인은 Map Server의 서비스 가용성을 검사합니다. 실제
  로봇의 주행 성공 여부는 별도의 현장 테스트가 필요합니다.
- 배포 중 Map Server와 Fleet Adapter가 재시작되므로 진행 중인 RMF 작업에
  영향을 줄 수 있습니다. 운영 중인 로봇을 안전 상태로 전환한 뒤 배포하십시오.
