# RMF Control UI

창고 도면을 불러와 Open-RMF용 Floor, Wall, Lane, Waypoint를 작성하고 실제
프로젝트 맵 디렉터리로 배포하는 Flutter 관리 화면입니다.

상세 사용법과 배포 동작은 다음 문서를 참고하세요.

- [맵 작성 및 배포 가이드](docs/MAP_AUTHORING_AND_DEPLOYMENT.md)
- [앱 전용 Mock 로봇 가이드](docs/APP_MOCK_ROBOTS.md)
- [Mock 로봇 작업 관리 가이드](docs/MOCK_TASKS.md)

## 실행

실제 Open-RMF 배포 기능은 Linux 데스크톱 앱에서 지원합니다.

```bash
cd /home/gyi/robosapiens/rmf_control_ui
flutter run -d linux
```

웹 빌드에서는 맵 편집과 YAML 내보내기는 가능하지만 운영체제 프로세스를
실행할 수 없으므로 실제 배포는 지원하지 않습니다.
