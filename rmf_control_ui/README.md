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

## 실행

실제 Open-RMF 배포 기능은 Linux 데스크톱 앱에서 지원합니다.

```bash
cd /home/gyi/robosapiens/rmf_control_ui
flutter run -d linux
```

작업 목록과 작업 변경 이력은 MySQL `robosapiens` 데이터베이스의
`rmf_ui_tasks`, `rmf_ui_task_history` 테이블에 저장됩니다. 접속값은
`ROBOSAPIENS_DB_HOST`(기본 `127.0.0.1`), `ROBOSAPIENS_DB_PORT`(기본 `3306`),
`ROBOSAPIENS_DB_USER`(기본 `root`), `ROBOSAPIENS_DB_NAME`(기본 `robosapiens`)으로
변경할 수 있습니다. 팀 개발용 기본 비밀번호는 `robosapiens`로 설정되어 있으며,
운영 환경에서는 `ROBOSAPIENS_DB_PASSWORD` 환경 변수를 지정하면 기본값보다 우선합니다.

웹 빌드에서는 맵 편집과 YAML 내보내기는 가능하지만 운영체제 프로세스를
실행할 수 없으므로 실제 배포는 지원하지 않습니다.
