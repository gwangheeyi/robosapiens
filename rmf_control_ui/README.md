# RMF Control UI

창고 도면을 불러와 Open-RMF용 Floor, Wall, Lane, Waypoint를 작성하고 실제
프로젝트 맵 디렉터리로 배포하는 Flutter 관리 화면입니다.

상세 사용법과 배포 동작은 다음 문서를 참고하세요.

- [맵 작성 및 배포 가이드](docs/MAP_AUTHORING_AND_DEPLOYMENT.md)
- [앱 전용 Mock 로봇 가이드](docs/APP_MOCK_ROBOTS.md)
- [Mock 로봇 작업 관리 가이드](docs/MOCK_TASKS.md)
- [식품 주문 · Pinky · OMX-AI 연동 설계](docs/FOOD_ORDER_PINKY_OMX_WORKFLOW.md)
- [ROS 관제 시스템 Waypoint 아키텍처 매핑](docs/ROS_CONTROL_WAYPOINT_ARCHITECTURE.md)
- [Waypoint·Lane 혼합형 자동 경로 지정 가이드](docs/HYBRID_ROUTE_AUTO_PLANNING.md)
- [Pinky 가상 로봇 · Fleet Adapter 연동](docs/PINKY_FLEET_INTEGRATION.md)

## 실행

실제 Open-RMF 배포 기능은 Linux 데스크톱 앱에서 지원합니다.

```bash
cd /home/gyi/robosapiens/rmf_control_ui
flutter run -d linux
```

창고 맵은 **지도 이름으로 구분되는 프로젝트 단위**로 MySQL `robosapiens`
데이터베이스에 저장됩니다(`map_projects`, `map_project_waypoints`,
`map_project_lanes`). 프로젝트가 다르면 Waypoint·Lane·축척이 전부 별개이며,
같은 이름으로 저장하려 하면 덮어쓸지 다른 이름을 쓸지 먼저 확인합니다.
자세한 내용은 [맵 작성 및 배포 가이드](docs/MAP_AUTHORING_AND_DEPLOYMENT.md)의
`맵 프로젝트 저장` 절을 참고하세요.

작업 목록과 작업 변경 이력(`rmf_ui_tasks`, `rmf_ui_task_history`)도 **맵
프로젝트에 속합니다.** 작업 단계가 그 맵의 Waypoint 좌표와 이름을 그대로 담기
때문에, 다른 맵에서 꺼내면 목적지가 아무 데도 가리키지 않습니다. 그래서 열린
프로젝트가 없으면 대시보드에 작업이 표시되지 않고 주문 자동 분류도 돌지
않습니다. 프로젝트를 지우면 그 맵의 작업도 함께 사라집니다.

주문·재고(`orders`, `lots`)는 창고 공통 원장이라 프로젝트로 나누지 않습니다. 접속값은
`ROBOSAPIENS_DB_HOST`(기본 `127.0.0.1`), `ROBOSAPIENS_DB_PORT`(기본 `3306`),
`ROBOSAPIENS_DB_USER`(기본 `root`), `ROBOSAPIENS_DB_NAME`(기본 `robosapiens`)으로
변경할 수 있습니다. 팀 개발용 기본 비밀번호는 `robosapiens`로 설정되어 있으며,
운영 환경에서는 `ROBOSAPIENS_DB_PASSWORD` 환경 변수를 지정하면 기본값보다 우선합니다.

웹 빌드에서는 맵 편집과 YAML 내보내기는 가능하지만 운영체제 프로세스를
실행할 수 없으므로 실제 배포는 지원하지 않습니다.

## 팝업

모든 팝업은 위쪽 손잡이를 끌어 옮길 수 있습니다. 팝업이 화면 가운데 고정되면
그 아래의 지도나 목록을 보면서 고칠 수 없기 때문입니다.

오류 팝업은 본문을 끌어 선택하거나 `복사`로 전문을 가져갈 수 있고, 오른쪽 아래
모서리를 끌어 크기를 바꿀 수 있습니다. 진단 문구에 좌표·거리·축척 같은 수치가
들어가 길어지기 때문입니다.

새 팝업은 `lib/movable_dialog.dart`의 `showMovableDialog`로 엽니다. `showDialog`와
인자가 같습니다.
