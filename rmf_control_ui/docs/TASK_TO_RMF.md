# 작업이 RMF까지 가는 길

앱에서 만든 연속 작업이 실제 로봇을 움직이기까지 무엇이 어디서 일어나는지.

---

## 1. 짧은 답

**넷이 나눠 합니다.** RMF 작업 자체는 RMF가 합니다 — Flutter도, Flutter가 만든
Python도 아닙니다.

```
Flutter               무엇을 할지 정한다     rmf_task_request.dart   231줄
  ↓  JSON
<맵>_task_bridge.py   나른다                 90줄 · 판단 안 함
  ↓  task_api_requests
RMF                   어떻게 갈지 정한다     경로 · 순서 · 교통 정리
  ↓  목적지 하나씩
<맵>_nav2_adapter.py  실행하고 되알린다      317줄
  ↓  NavigateToPose
Nav2                  운전한다
```

Flutter가 하는 일은 **번역**입니다. "충전1로 가라"를 RMF가 아는 `go_to_place`로
바꿉니다. 그 앞뒤로 경로를 고르고 다 왔는지 판정하는 것은 전부 RMF입니다.

---

## 2. 왜 Python이 끼는가

**Flutter에 ROS 바인딩이 없습니다.** rclpy도 rclcpp도 못 씁니다.

이 앱이 처음부터 써 온 방식과 같습니다.

| 하고 싶은 일 | 부르는 것 |
|---|---|
| MySQL 읽기 | `mysql` 클라이언트 |
| 로봇 위치 받기 | `ros2 topic echo` |
| 노드 살아 있나 | `ros2 node list` |
| **작업 넣기** | **`<맵>_task_bridge.py`** |

`ros2 topic pub` 한 줄이면 좋겠지만 안 됩니다.

* 요청과 답을 `request_id`로 맞춰야 합니다. 남의 요청에 대한 답도 같은 토픽으로
  옵니다.
* QoS가 `transient_local`이라 실은 뒤 잠깐 살아 있어야 합니다.

그래서 90줄짜리 심부름꾼을 하나 둡니다. **아무것도 판단하지 않습니다** — 받아서
싣고, 답을 찍고, 끝냅니다.

---

## 3. 새 작업은 자동입니다

작업 편집기에서 무엇을 만들든, **실행을 누르는 순간** 변환이 일어납니다.

```dart
_runMockTask(task)
  → _isRmfDriven(robot.id)     // 출처가 Gazebo·실물이면 RMF로
  → convertTaskSteps(...)       // 단계 → activity
  → buildRmfTaskRequest(...)    // JSON
  → RmfTaskBridge.submit(...)   // 보낸다
```

손으로 할 일이 없습니다. 새 Waypoint를 지도에 넣어도, 단계 순서를 바꿔도, 작업을
열 개 더 만들어도 그대로 나갑니다.

**작업 편집기와 저장 형식은 그대로 둡니다.** 변환은 내보낼 때만 지나가는 자리
입니다. 되돌리기 쉬우라고 그렇게 했습니다.

### Mock 로봇은 예전 그대로

| 출처 | 누가 모나 |
|---|---|
| 앱 Mock | 앱이 좌표를 밀고 앱이 단계를 센다 |
| Gazebo · 실물 | RMF가 경로를 정하고 어댑터가 알린다 |

RMF가 모는 로봇은 **앱 타이머가 아예 건드리지 않습니다.** 좌표도 안 밀고 단계도
안 셉니다. 둘 다 하면 로봇이 아직 가는 중인데 화면만 다음 단계로 넘어갑니다 —
그게 원래 증상이었습니다.

---

## 4. 다시 해 줘야 하는 것 둘

### ① 지도나 로봇을 바꾸면 배포

Python 파일은 맵마다 만들어집니다. 로봇을 추가하거나 플릿 이름을 바꾸면 다시
배포해야 스크립트가 따라옵니다.

nav graph는 이제 실행 스크립트가 스스로 다시 만듭니다 —
[MULTI_ROBOT_NAMESPACES.md](MULTI_ROBOT_NAMESPACES.md)의 *낡은 nav graph* 를
보세요.

### ② 새로운 *종류*의 단계를 만들면 코드 한 줄

지금 아는 것은 넷입니다.

| 앱 단계 | RMF activity |
|---|---|
| `navigate` | `go_to_place` (Waypoint 이름) |
| `returnHome` | `go_to_place` (로봇의 충전 자리) |
| `armLoad` | `perform_action` |
| `wait` | `wait_for` |

여기 없는 것이 오면 **조용히 버리지 않고** 이유를 남깁니다.

```
6번째 청소 — RMF 가 모르는 단계입니다
```

조용히 버리면 화면의 10단계와 실제로 도는 9단계가 어긋납니다.

새 종류를 추가하려면 `convertTaskSteps`에 한 줄. 그것이 `perform_action`이면
**플릿 설정 `actions:`에도 같은 이름**을 넣어야 합니다.

---

## 5. 정리 — 무엇이 자동인가

| | 자동인가 |
|---|:---:|
| 새 작업 만들어 실행 | ✅ |
| Waypoint · Lane 추가 | ✅ (배포 후) |
| 로봇 추가 · 플릿 이름 변경 | 배포 필요 |
| 새로운 종류의 단계 | 코드 한 줄 |

일상적으로는 변환을 의식할 일이 없습니다. `armLoad` 말고 다른 동작(문 열기,
저울 재기 같은 것)을 만들 때만 한 번씩 손이 갑니다.

---

## 6. 밟은 함정 셋

### `actions:`에 없는 동작은 작업 전체가 거절된다

단계 하나가 빠지는 것이 아닙니다. **작업이 통째로 안 들어갑니다.**

```json
{"errors": [{"code": 42,
  "detail": "Fleet not configured to perform this action"}],
 "success": false}
```

플릿 설정에 이렇게 있어야 합니다.

```yaml
actions: ["teleop", "armLoad"]
```

이 사유가 화면에 안 닿으면 또 "배차는 됐는데 로봇이 안 움직인다"로만 보입니다.
그래서 거절 사유는 팝업으로 그대로 보여 줍니다.

### 걸리는 시간을 두 군데에 적어야 한다

RMF는 `execute_action`에 **안쪽 `description`만** 넘겨 줍니다. 바깥
`unix_millis_action_duration_estimate`는 어댑터까지 닿지 않습니다.

실측 — 9.6초짜리 `armLoad`가 **1.0초** 만에 끝났습니다.

```python
description = {
    'unix_millis_action_duration_estimate': 9600,  # RMF 가 배차 계산에 쓴다
    'category': 'armLoad',
    'description': {'seconds': 9.6},               # 어댑터가 본다
}
```

### 도착 횟수와 단계 수가 다르다

RMF는 Lane 그래프를 따라 **중간 Waypoint를 스스로 끼워 넣습니다.** 도착할 때마다
단계를 넘기면 화면이 실제보다 앞서갑니다.

그래서 마지막 목적지 좌표가 **우리 단계의 목적지와 같을 때만** 넘깁니다
(오차 0.02m). 중간 Waypoint는 어느 단계와도 안 맞으니 그냥 지나갑니다.

---

## 7. 확인한 것

저장돼 있던 **연속 작업 1**(이동 9 · 적재 1)을 앱 코드가 만든 JSON 그대로
넣었습니다. 버린 단계 0개.

```
충전1 → 홈1 → 대기5 → 대기2 → 픽업1
  ◆ armLoad 9.6초
→ [대기4] → 대기3 → 대기4 → 드랍오프1 → [대기1] [대기5] [홈1] → 충전1
task_id: ''                                              ← 완료
```

대괄호는 **RMF가 스스로 끼워 넣은 경유지**입니다. 단계 10개에 도착 12번.

RMF가 순서를 지키는지는 따로 확인했습니다. `대기3 → 대기4`만 넣어 보니 그 순서
그대로였고, 중간에 낀 대기4는 경유지였습니다.

```
Publisher count: 0 → 6      (/pinky_01/cmd_vel)
```

---

## 8. 아직 안 된 것

**매니퓰레이터를 실제로 부르지 않습니다.** OMX 쪽에 RMF 요청을 받는 노드가
없습니다. 지금은 예상 시간만큼 기다리고 끝났다고 알립니다. 어댑터의
`execute_action`에 그 자리를 뚫어 두고 주석으로 밝혀 놨습니다.

**실물 로봇은 확인하지 못했습니다.** 하드웨어가 없습니다. 설계상 이 문서의 어느
줄도 바뀌지 않지만 — 어댑터는 Nav2와만 이야기하고 Nav2 아래가 Gazebo인지 진짜
모터인지 모릅니다 — 확인하지 않은 것을 확인했다고 적지 않습니다.

---

## 관련 문서

* [THREE_SOURCES.md](THREE_SOURCES.md) — Mock · Gazebo · 실물 세 출처
* [NAV2_PATH.md](NAV2_PATH.md) — Nav2를 붙이기까지
* [MULTI_ROBOT_NAMESPACES.md](MULTI_ROBOT_NAMESPACES.md) — 여러 대를 가르는 법과 함정
* [COORDINATE_FRAMES.md](COORDINATE_FRAMES.md) — 도면 좌표와 RMF 월드 좌표
