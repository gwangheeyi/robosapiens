# OMX Product-Specific Policies and Imitation Learning Data Operations (OMX 물품별 Policy와 모방학습 데이터 운영)

설치·보관·붙이기·고르기·실행을 한 줄기로 본 문서는
[WorkCell Policy 한살이](WORKCELL_POLICY_LIFECYCLE.md)에 있다. 이 문서는 물품별
policy와 모방학습 데이터를 어떻게 나눌지에 집중한다.

## 1. 목적

Pinky가 픽업 위치에 도착했을 때 물품 종류에 맞는 OMX 동작을 선택하는 방법과,
현재 가상 관절 동작을 실제 모방학습 policy로 교체할 때 데이터와 프로그램을
어떻게 나눌지를 정리한다.

핵심 원칙은 다음과 같다.

> RMF는 물품과 작업 순서를 전달하고, 워크셀은 policy를 선택하며, 별도의 skill
> executor가 카메라와 로봇 상태를 보고 실제 동작을 실행한다.

훈련 데이터 전체를 RMF 메시지나 워크셀 스크립트에 넣지 않는다.

## 2. 현재 구현: OMX마다 가상 policy 5개

현재 `omx_01`, `omx_02`, `omx_03`은 공통으로 다음 다섯 policy를 제공한다.

| 물품 선택값 | 실행 policy | 현재 구현 |
|---|---|---|
| 물품 1 | `policy_1` | 정면 물품을 가정한 가상 관절 궤적 |
| 물품 2 | `policy_2` | 오른쪽 물품을 가정한 가상 관절 궤적 |
| 물품 3 | `policy_3` | 왼쪽 물품을 가정한 가상 관절 궤적 |
| 물품 4 | `policy_4` | 오른쪽 가까운 물품을 가정한 가상 관절 궤적 |
| 물품 5 | `policy_5` | 왼쪽 가까운 물품을 가정한 가상 관절 궤적 |

작업 편집기에서 `OMX-AI 픽업` 단계를 선택하면 `픽업 Policy` 목록에서 하나를
선택한다(등록된 Policy가 없으면 `픽업 동작`으로 나오고 기본 `armLoad`를 쓴다).
선택값은 작업 저장·불러오기에도 보존된다.

Policy를 보관하는 곳은 왼쪽 메뉴의 `Policy 관리`이고, 설비에 붙이는 곳은
`로봇 관리`다.

- **보관**: 기본 정보(이름·버전·물품·모델·소속 프로젝트·붙인 설비)는 MySQL
  `workcell_policies` 표에 있고, 학습 결과 ZIP은
  `<작업트리>/workcell_policies/<storage_key>/policy.zip`에 둔다. ZIP은 git에
  올리지 않으므로 다른 자리에서 받은 저장소에는 **목록에는 있으나 파일이 없는**
  policy가 생긴다. 그런 policy에는 `Hugging Face에서 내려받기` 단추가 나오고,
  처음 받을 때 적어 둔 revision 그대로 다시 받는다.
- **소속**: Policy는 프로젝트별로 가진다. 다만 소속은 이름표일 뿐이라
  프로젝트를 지워도 policy는 남으며(외래키를 걸지 않는다), `수정`에서 다른
  프로젝트로 옮기거나 `공용`으로 되돌릴 수 있다. 수정은 이름표만 바꾸고 학습
  결과와 그 파일이 놓인 자리는 건드리지 않는다.
- **배포**: 어느 설비(WorkCell)가 쓸지는 `로봇 관리`에서 설비 로봇의
  `Policy 붙이기·떼기`로 **팔마다 따로** 정한다. 프로젝트에 등록했다고 모든
  팔이 쓰는 것이 아니다 — 팔마다 배운 것이 다르기 때문이다.
- **작업에서 고르기**: 픽업 요청은 자리 이름(`target_guid`)으로 나가고, 그
  자리를 맡는 설비 하나가 답한다(`workcellsByStation`). 그래서 작업 편집기의
  `픽업 Policy` 목록은 **바로 앞 이동 단계의 목적지를 맡는 설비**에 붙인 policy
  만 보여 준다. 그 설비에 붙지 않은 policy가 이미 저장돼 있으면 목록에 남기되
  붉은 글씨로 알린다 — 조용히 바꾸면 어느 팔이 무엇을 하는지 알 수 없게 된다.
  앞에 이동 단계가 없어 자리를 모를 때만 프로젝트에 붙인 것을 모두 보여 준다.

### 무엇으로 움직이는가 — 워크셀 노드의 사다리

`<맵>_workcell.py`가 픽업 요청을 받으면 이 차례로 정한다. 어느 길로 가든
**끝난 것을 확인한 뒤에** RMF에 성공을 알린다 — 그래야 다음 단계로 넘어간다.

| 상태 | 무엇을 하는가 | 로그 |
|---|---|---|
| 붙인 policy + ZIP + 러너가 다 있다 | `<맵>_policy_runner.py`로 **그 policy 추론** | `학습 policy 로 움직입니다` |
| 붙어는 있으나 ZIP이 없다 | 시험 동작 | `[TEST] [id] 학습 결과 파일이 없어` |
| 붙어는 있으나 러너가 없다 | 시험 동작 | `[TEST] [id] 러너(...)가 없어` |
| 가상 policy(`policy_1`…`5`) | `POLICY_MOTIONS`의 궤적 | `가상 policy 실행` |
| **붙인 policy가 없다(`armLoad`)** | **시험 동작** — 관절 몇 개를 움직였다 집으로 | `[TEST] 붙인 policy 가 없어` |
| 이 팔에 붙지 않은 policy | 실패로 답한다(조용히 바꾸지 않는다) | `에 붙지 않은 policy 입니다` |

시험 동작은 학습한 동작이 아니다. 팔·컨트롤러·RMF의 고리가 살아 있는지 보는
것뿐이며, 액션 결과로 끝을 확인하고 성공을 알린다. 아무것도 안 보내고 성공만
돌려주면 팔이 안 떠 있어도 작업이 넘어간다.

### policy 러너 (`<맵>_policy_runner.py`)

**Gazebo와 실물이 같은 러너를 쓴다.** 받는 것은 네임스페이스 하나뿐이고, 그
뒤에 시뮬레이터가 있든 실제 컨트롤러가 있든 토픽은 같다.

```text
/<ns>/joint_states                     관측(관절 위치)
/<ns>/arm_controller/joint_trajectory  명령
/<ns>/camera/image_raw                 policy가 이미지를 요구할 때만
```

policy ZIP은 `~/.cache/robosapiens/policies/<id>/`에 한 번만 풀고 LeRobot로
불러온다. 워크셀 노드는 **종료 코드로만** 판단한다.

| 코드 | 뜻 | 노드가 하는 일 |
|---|---|---|
| 0 | 추론 동작을 끝냈다 | 관절이 멎기를 기다렸다 RMF에 성공 |
| 2 | torch·lerobot이 없거나 policy를 못 읽었다 | 시험 동작으로 대신하고 작업을 이어 간다 |
| 3 | 관절 상태가 안 온다(팔이 없다) | 〃 |
| 4 | policy 압축이 이상하다 | 〃 |

추론기가 없는 자리에서 작업이 멈추지 않게 하려는 것이다. 왜 추론이 안 돌았는지는
`<맵>_policy_runner.log`에 남는다. `POLICY_TIMEOUT`(600초)을 넘기면 러너를 끊고
실패로 답한다.

`POLICY_MOTIONS`의 가상 궤적은 실제 물품 파지를 학습한 결과가 아니다. 정의는
생성된 `<맵>_workcell.py`에 있고 원본 생성 코드는 `lib/rmf_project_config.dart`에
있다. 생성된 Python만 손으로 고치면 다음 프로젝트 저장 때 덮어써진다.

## 3. 작업에서 OMX까지 전달되는 값

작업의 적재 단계는 다음 설명을 가진다.

```json
{
  "category": "armLoad",
  "description": {
    "target_guid": "픽업3",
    "item_type": "policy_3",
    "quantity": 1,
    "seconds": 9.6
  }
}
```

Nav2 adapter는 이를 RMF `DispenserRequest`로 변환한다.

```text
/dispenser_requests
  request_guid: pinky_01-<UUID>
  target_guid: 픽업3
  transporter_type: pinky_01
  items:
    - type_guid: policy_3
      quantity: 1
      compartment_name: pinky_tray
```

각 필드의 책임은 다음과 같다.

| 필드 | 의미 |
|---|---|
| `target_guid` | 어느 픽업 워크셀을 사용할지 결정한다 |
| `transporter_type` | 물품을 받을 Pinky를 나타낸다 |
| `items[].type_guid` | 워크셀이 선택할 물품 종류 또는 policy ID다 |
| `quantity` | 처리할 수량이다 |
| `compartment_name` | Pinky의 적재 위치다 |

`project1_workcell`은 `target_guid`로 담당 OMX를 고르고 `type_guid`로 다섯
policy 중 하나를 고른다. 등록되지 않은 policy가 들어오면 임의 동작으로
대체하지 않고 `DispenserResult.FAILED`를 반환한다.

## 4. 실제 motion 데이터는 어디서 오는가

실제 모방학습용 시연 데이터는 로봇팔과 센서에서 수집한다.

- 카메라 RGB 및 Depth 영상
- 관절 위치, 속도와 명령값
- 그리퍼 열림·닫힘 상태
- 가능하면 힘·토크 또는 모터 전류
- 물품 종류, 배치 조건과 작업 성공 여부
- 모든 데이터의 동기화된 타임스탬프

관절 좌표만 기록해 그대로 재생할 수도 있지만, 이 방식은 물품 위치와 자세가
훈련 때와 거의 같아야 한다. 물품 배치가 변한다면 카메라 영상과 현재 로봇
상태를 입력으로 받아 다음 동작을 계산하는 policy가 필요하다.

## 5. 데이터가 많은가

관절 상태만 저장하면 비교적 작지만 영상이 포함되면 데이터 대부분을 영상이
차지한다. 해상도, 프레임률, 압축 방식, 카메라 수, 에피소드 길이에 따라 실제
용량이 크게 달라진다. 여러 물품과 실패 사례까지 모으면 수십 GB에서 수백 GB
이상으로 커질 수 있다.

그러나 운영할 때 훈련 데이터 전체를 로봇으로 보내지는 않는다.

```text
훈련 환경                         운영 환경
─────────                         ─────────
시연 영상·관절·센서 데이터  → 학습 → model.onnx 또는 model.pt
성공·실패 라벨                         metadata.yaml
여러 에피소드                         정규화 값·입출력 정의
```

RMF 작업에는 `policy_3` 같은 짧은 ID만 들어간다. 학습된 모델은 OMX 제어
컴퓨터나 추론 서버에 미리 배포하고 한 번 로딩한 뒤 반복 사용한다.

## 6. 권장 파일 구조

훈련 원본과 운영 모델을 분리한다.

```text
training_data/                 # 대용량 원본, 운영 배포에 포함하지 않음
├── policy_1/
│   ├── episode_0001/
│   └── episode_0002/
└── policy_5/

policies/                      # 운영에 필요한 학습 결과
├── policy_1/
│   ├── model.onnx
│   └── metadata.yaml
├── policy_2/
├── policy_3/
├── policy_4/
└── policy_5/
```

`metadata.yaml`에는 최소한 다음 내용을 둔다.

```yaml
policy_id: policy_3
item_type: product_c
model_version: 1.0.0
joint_names: [joint1, joint2, joint3, joint4]
camera_topics: [/omx_03/camera/color/image_raw]
control_rate_hz: 20
maximum_duration_seconds: 30
success_detector: gripper_current_and_tray_sensor
```

같은 policy라도 OMX별 카메라 보정값이나 작업대 좌표가 다를 수 있다. 모델을
공유하더라도 로봇별 calibration은 별도 파일로 관리한다.

## 7. 실제 모방학습 연결 구조

학습 모델을 `<맵>_workcell.py` 안에 직접 넣기보다 별도 ROS 2 Action 노드로
분리하는 것을 권장한다.

```text
RMF 작업
  → <맵>_nav2_adapter.py
  → /dispenser_requests(item_type=policy_3)
  → <맵>_workcell.py
  → /omx_03/execute_skill Action
  → omx_skill_executor
      ├─ policy_3 모델
      ├─ 카메라 입력
      ├─ 관절·그리퍼 상태
      └─ arm/gripper controller 명령
  → 성공 검증
  → /dispenser_results SUCCESS 또는 FAILED
  → RMF 다음 단계
```

Action 목표에는 다음 정보가 필요하다.

```text
workcell_id: omx_03
policy_id: policy_3
item_type: product_c
quantity: 1
target_robot: pinky_01
target_compartment: pinky_tray
```

실행 중에는 `LOCATING_OBJECT`, `APPROACHING`, `GRASPING`, `VERIFYING`,
`PLACING` 같은 피드백을 내고 최종 결과는 `SUCCEEDED` 또는 `FAILED`로 반환한다.

## 8. 성공 판정과 안전 조건

시간이 지났다는 이유만으로 성공 처리하면 안 된다. 실제 운영에서는 다음 조건을
모두 확인한 뒤에만 RMF에 `SUCCESS`를 보낸다.

1. policy 실행이 오류 없이 끝났다.
2. 그리퍼 전류, 힘 또는 접촉 정보가 정상 파지를 나타낸다.
3. 카메라나 적재함 센서가 물품이 Pinky에 놓였음을 확인한다.
4. 로봇팔이 안전 복귀 자세에 도달했다.

실패하면 `FAILED`를 보내고 Pinky가 픽업 위치를 떠나지 않게 한다. 재시도를
지원한다면 최대 횟수, 재시도 가능한 오류와 즉시 중단해야 할 오류를 구분한다.
비상정지, 관절 제한 초과, 사람 진입 등의 안전 오류는 자동 재시도하지 않는다.

현재 가상 policy는 지정된 관절 궤적을 보낸 뒤 설정 시간이 지나면 성공으로
응답하므로, 위 성공 검증은 실제 skill executor를 연결할 때 반드시 추가해야 한다.

## 9. 실제 policy로 교체하는 순서

1. 각 물품에 대해 성공·실패 시연 데이터를 수집한다.
2. 데이터셋 버전과 카메라·로봇 calibration을 고정한다.
3. 다섯 policy를 학습하고 재현 가능한 평가 세트로 검증한다.
4. 모델을 ONNX 등의 운영 형식으로 내보낸다.
5. `omx_skill_executor`가 모델을 미리 로딩하도록 한다.
6. Workcell의 `run_policy()` 직접 궤적 발행을 ROS Action 호출로 교체한다.
7. 파지 및 Pinky 적재 성공 검증을 연결한다.
8. Gazebo 또는 디지털 트윈에서 실패·취소·재시도까지 시험한다.
9. 제한된 실물 조건에서 검증한 뒤 운영 범위를 확대한다.

## 10. 점검 방법

요청에 선택한 policy가 실렸는지 확인한다.

```bash
ros2 topic echo /dispenser_requests
```

현재 가상 policy에서는 다음 로그가 나와야 한다.

```text
[omx_03] 픽업3 요청 받음 (...)
[omx_03] 물품 [policy_3] 가상 policy 실행
[omx_03] 픽업3 끝.
```

관절 명령과 컨트롤러도 확인한다.

```bash
ros2 topic echo /omx_03/arm_controller/joint_trajectory
ros2 control list_controllers -c /omx_03/controller_manager
```

Python 생성물을 변경했다면 실행 중 프로세스에는 자동 반영되지 않는다. 프로젝트
설정을 저장하고 디스크로 내보낸 다음 백엔드를 완전히 중지하고 다시 실행한다.

## 관련 문서

- [TASK_TO_RMF.md](TASK_TO_RMF.md) — 작업, Fleet Adapter와 Workcell 연결
- [FOOD_ORDER_PINKY_OMX_WORKFLOW.md](FOOD_ORDER_PINKY_OMX_WORKFLOW.md) — 주문부터 적재까지 전체 흐름
- [MULTI_ROBOT_NAMESPACES.md](MULTI_ROBOT_NAMESPACES.md) — OMX별 네임스페이스 분리
- [ROBOT_REGISTRATION.md](ROBOT_REGISTRATION.md) — Pinky와 설치 로봇 등록
