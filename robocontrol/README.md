# RoboControl

기존 RoboSapiens 관제 화면과 지도·로봇·주행기록 DB를 그대로 사용하면서,
Open-RMF와 Gazebo 없이 실물 Pinky를 가볍게 운용하는 Flutter 데스크톱 앱입니다.

## 운용 구성

```text
기존 지도/Waypoint → map_server + AMCL + Nav2 → NavigateToPose → Pinky
                                                ↘ 수동 미세조종
                                                ↘ ArUco 정밀접근(확장 지점)
```

- 기존 `rmf_maps/<프로젝트>`의 Nav2 점유격자와 waypoint 좌표를 사용합니다.
- `Waypoint로 보내기`는 RMF 작업 요청 대신 로봇의
  `/<namespace>/navigate_to_pose` action을 직접 호출합니다.
- waypoint에 도킹 방향이 있으면 최종 목표 각도로 사용합니다.
- 정적 DDS peer나 상대 IP를 설정하지 않고 UDP 멀티캐스트 SUBNET 탐색을 씁니다.
- 프로젝트 실행은 RMF core, fleet adapter, Gazebo를 실행하지 않습니다.
- RMF 노드/서비스 readiness 검사와 `/fleet_states`·RMF 작업 진행 구독을
  시작하지 않습니다. 로봇 위치는 각 로봇의 odom에서 직접 읽습니다.
- 수동 미세조종, 센서 확인, 주행학습 기록 등 기존 기능을 복제했습니다.
- Policy 관리의 `외부 Python 실행`에서 임의의 `.py` 파일, 인자와 제한 시간을
  지정해 실행하고 stdout/stderr 및 종료 코드를 확인할 수 있습니다.
- 등록된 Policy는 `로봇팔 Policy 실행`으로 시험할 수 있습니다. Pinky를 고르면
  먼저 cmd_vel 0을 보낸 뒤 `<맵>_policy_runner.py`로 LeRobot 추론을 실행합니다.
- Nav2 직접주행 목적지에 로봇팔과 Policy가 연결되어 있으면 도착 후 같은 안전
  정지·Policy 실행 흐름을 자동으로 이어갑니다.
- ArUco 자동 정밀접근은 카메라 및 마커 ID/크기가 정해진 뒤 연결할 확장 지점입니다.

여러 로봇의 교통 조정 기능은 없습니다. 안전을 위해 같은 통로에는 한 번에 한 대만
보내고, 특수 구간은 수동 또는 향후 ArUco 정밀접근을 사용하십시오.

## 실행

```bash
cd /home/gyi/robosapiens/robocontrol
flutter pub get
flutter run -d linux
```

기존 DB와 `/home/gyi/robosapiens/rmf_maps`를 공유하므로 PinkyTest 지도를 새로
작성할 필요가 없습니다. 원본 `rmf_control_ui`는 별도 프로그램으로 그대로 남습니다.
