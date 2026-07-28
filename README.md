# RoboSapiens 물류 플랫폼

3온도(상온·냉장·냉동) 물류센터의 자율주행 로봇 운영 시스템입니다.

## 구성

| 패키지 | 역할 | 상태 |
|---|---|---|
| [`robo_core/`](robo_core/) | 공용 도메인 모델 + 저장소 계층 (Repository 인터페이스 · SQLite 구현) | 구현 |
| [`robo_control/`](robo_control/) | **관제센터** — 로봇 배차·안전·재고·주문 통제 (Flutter desktop) | 구현 |
| [`roboapp/`](roboapp/) | **소비자 주문 앱** — 3온도 상품 주문 + WebRTC 실시간 화면 (Flutter web·Android) | 구현 |

```
소비자 앱 ─┐
           ├─▶  orders 테이블  ─▶  관제센터  ─▶  로봇
   WMS ────┘        (robo_core)
```

`orders`가 두 앱의 접점입니다. 소비자 앱이 주문을 쓰고, 관제센터가 읽어
FEFO·긴급도·동선 기반으로 로봇 태스크를 전개합니다.

## 시작하기

```bash
# 관제센터
cd robo_control && flutter run -d linux

# 소비자 앱
cd roboapp && flutter run -d chrome
```

문서는 [robo_control/README.md](robo_control/README.md),
[사용 설명서](robo_control/docs/USER_GUIDE.md),
[프로젝트 요약](robo_control/docs/PROJECT_SUMMARY.md)을 참고하세요.

## 저장소

원장은 SQLite (`~/.local/share/robo_control/robo_control.db`, `ROBOAPP_DB_DIR`로 변경 가능).
소비자 앱이 붙는 시점에는 `robo_core`의 `DataStore` 구현만 PostgreSQL·REST로
교체하면 됩니다 — UI와 제어 로직은 그대로입니다.
