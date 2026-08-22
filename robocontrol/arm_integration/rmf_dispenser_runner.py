#!/usr/bin/env python3
"""RMF dispenser 요청 하나를 Trihouse 팔 코드로 실행한다.

워크셀 노드(`<맵>_workcell.py`)가 이것을 프로세스로 띄우고 **종료 코드만**
본다. 여기서 하는 일은 하나다 — RMF 가 보낸 `type_guid` 를 주문으로 바꿔
`deliver.run_order()` 에 넘기고, 그 판정을 종료 코드로 옮긴다.

    RMF ─▶ workcell.py ─▶ 이 파일 ─▶ deliver.run_order()  (tools/, 손대지 않음)

`job_loop.py` 와 같은 자리에 앉는다. 다르게 하는 것은 앞단뿐이다 —
`job_loop` 는 FMS Gateway 를 HTTP 로 폴링하고, 이쪽은 RMF 가 보낸 요청 하나를
받아 그 자리에서 끝낸다.

**핑키 도착을 여기서 다시 묻지 않는다.** RMF 는 로봇이 픽업 자리에 닿아야
dispenser 요청을 보내고, 워크셀 노드가 그 위에 `/fleet_states` 로 로봇이 제
자세로 **멈춰 있는지** 다시 확인한다 — 적재 중에 자리를 뜨면 워크셀이 이
프로세스를 끊는다. `job_loop` 가 Gateway 에 다시 물어야 했던 것은 그쪽에
그런 보증이 없어서다. 여기서는 `MockPinkyArrival(already_arrived=True)` 로
`run_order()` 안의 재확인을 즉시 통과시킨다 — `job_loop._handle_dispatch` 가
Gateway 로 도착을 확인한 뒤에 하는 것과 같다.

종료 코드
    0  집어서 바구니에 놓았다 (release 확인됨)
    2  추론기·드라이버가 이 자리에 없다
    3  팔이나 카메라가 안 붙는다
    4  주문을 확정할 수 없다 (모르는 품목, zone 불일치)
    5  팔은 돌았으나 인계를 확인 못 했다 (파지/release 미확인)
"""

import argparse
import os
import sys
import time

# Trihouse 팔 코드는 `rmf_control_ui/tools/` 에 통째로 들어 있다. 그 디렉터리를
# import 경로에 넣는다 — 코드는 안 건드리고 부르기만 한다.
TOOLS = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'tools')
sys.path.insert(0, TOOLS)

EXIT_OK = 0
EXIT_NO_DRIVER = 2
EXIT_NO_ARM = 3
EXIT_BAD_ORDER = 4
EXIT_NOT_HANDED_OVER = 5

# 팔마다 맡은 창고 구역. **omx_02 는 냉동실이다.**
#
# zone 을 팔에 묶어 두는 것이 policy_catalog 의 fail-closed 를 살린다 — 냉동실
# 팔에 상온 품목이 오면 UnknownProductError 로 거절된다. RMF 요청에 실린 값을
# 그대로 믿으면 그 보호가 없어진다.
ZONE_BY_NAMESPACE = {
    'omx_02': 'frozen',
}

# 어느 팔인지 모를 때 쓰는 구역. None 이면 모르는 팔을 거절한다.
DEFAULT_ZONE = None


def log(message):
    print(f'[rmf_dispenser_runner] {message}', flush=True)


def zone_for(namespace):
    """이 팔이 맡은 구역. 모르는 팔이면 None."""
    return ZONE_BY_NAMESPACE.get(namespace.strip('/'), DEFAULT_ZONE)


def parse_type_guid(type_guid):
    """RMF 의 `type_guid` 를 (품목, 수량) 목록으로 바꾼다.

    dispenser 요청은 문자열 하나만 싣는다. `deliver.py --order` 와 같은 문법을
    그대로 쓴다 — 사람이 CLI 로 시험한 것과 RMF 가 보내는 것이 같은 모양이어야
    둘 사이에서 헷갈리지 않는다.

        dumpling            → dumpling 1개
        dumpling:2          → dumpling 2개
        dumpling:2,icebar:1 → 두 품목

    `mock_inputs.parse_items()` 가 이미 이 문법을 안다. 여기서 다시 짜지
    않는다.
    """
    import mock_inputs

    text = (type_guid or '').strip()
    if not text:
        raise ValueError('type_guid 가 비었습니다')
    # `이름@버전` 으로 오면 버전을 떼고 본다. 워크셀의 policy 이름 규칙과
    # 섞여 들어올 수 있다.
    if '@' in text and ':' not in text and ',' not in text:
        text = text.split('@', 1)[0]
    return mock_inputs.parse_items(text)


class VerdictCatcher:
    """`run_order()` 가 내린 판정을 받아 둔다.

    `run_order()` 는 아무것도 돌려주지 않고 결과를 `outcome_report` 로만
    내보낸다. 종료 코드를 정하려면 그 판정이 필요하다.

    **`gateway=` 로는 못 받는다.** `report_outcome` 은 gateway 가 있으면
    `control_tower.gateway.fms_client` 를 import 해서 요청 객체를 만든 뒤에야
    그것을 부르는데, `control_tower` 는 Trihouse 저장소에만 있고 여기에는
    없다(tools/VENDORED.md 참고). 그래서 gateway 는 안 쓰고 `report_outcome`
    자체를 감싼다 — 원래 것을 그대로 부른 뒤(JSONL 기록과 콘솔 출력이 그대로
    남는다) 판정만 챙긴다.

    tools/ 의 코드는 한 줄도 안 고친다.
    """

    def __init__(self):
        self.outcome = None
        self.reason_code = None
        self._original = None
        self._module = None

    def install(self):
        """`deliver` 가 부르는 `report_outcome` 을 감싼다.

        `deliver.py` 는 `import outcome_report` 후 `outcome_report.report_outcome(...)`
        로 부른다 — 모듈 속성을 그때그때 찾으므로, 모듈 쪽을 바꿔 두면 걸린다.
        """
        import outcome_report

        self._module = outcome_report
        self._original = outcome_report.report_outcome

        def wrapped(step_outcome, **kwargs):
            # gateway 는 넘기지 않는다. 위 docstring 참고.
            kwargs.pop('gateway', None)
            result = self._original(step_outcome, **kwargs)
            self.outcome = getattr(step_outcome, 'outcome', None)
            self.reason_code = getattr(step_outcome, 'reason_code', None)
            log(f'판정 outcome={self.outcome} reason={self.reason_code}')
            return result

        outcome_report.report_outcome = wrapped
        return self

    def restore(self):
        if self._module is not None and self._original is not None:
            self._module.report_outcome = self._original

    def __enter__(self):
        return self.install()

    def __exit__(self, *exc):
        self.restore()
        return False


def main(argv=None):
    parser = argparse.ArgumentParser(prog='rmf_dispenser_runner')
    # 워크셀이 넘기는 인자. 이름을 바꾸면 워크셀도 함께 바꿔야 한다.
    parser.add_argument('--policy-id', required=True,
                        help='RMF 가 보낸 type_guid. 품목:수량 목록')
    parser.add_argument('--namespace', required=True,
                        help='이 팔의 ROS 네임스페이스. zone 을 여기서 정한다')
    parser.add_argument('--policy', default=None,
                        help='워크셀이 넘기는 policy ZIP. 여기서는 안 쓴다')
    parser.add_argument('--model', default=None, help='팔 모델. 기록용')
    parser.add_argument('--seconds', type=float, default=None,
                        help='워크셀이 넘기는 값. 여기서는 안 쓴다')
    # 팔 하드웨어. deliver.py 의 것과 같은 이름을 쓴다.
    parser.add_argument('--port', default=os.environ.get('OMX_PORT'),
                        help='OMX follower 시리얼 포트 (기본: $OMX_PORT)')
    parser.add_argument('--front-cam', default=None)
    parser.add_argument('--wrist-cam', default=None)
    parser.add_argument('--episode-steps', type=int, default=900)
    parser.add_argument('--fps', type=float, default=15.0)
    parser.add_argument('--cam-width', type=int, default=640)
    parser.add_argument('--cam-height', type=int, default=480)
    parser.add_argument('--cam-fps', type=int, default=30)
    parser.add_argument('--debug-gripper', action='store_true')
    parser.add_argument('--dry-run', action='store_true',
                        help='팔 없이 주문 해석과 zone 검사까지만 한다')
    args = parser.parse_args(argv if argv is not None else sys.argv[1:])

    started = time.monotonic()
    namespace = args.namespace.strip('/')

    # ── 이 팔이 맡은 구역 ─────────────────────────────────────────────────
    zone = zone_for(namespace)
    if zone is None:
        log(f'[{namespace}] 이 팔이 어느 구역인지 모릅니다 — '
            f'ZONE_BY_NAMESPACE 에 넣으세요')
        return EXIT_BAD_ORDER
    log(f'[{namespace}] 구역 {zone} · 요청 {args.policy_id}')

    # ── type_guid → 주문 ──────────────────────────────────────────────────
    try:
        items = parse_type_guid(args.policy_id)
    except Exception as error:
        log(f'요청을 못 읽었습니다 [{args.policy_id}]: {error}')
        return EXIT_BAD_ORDER

    # 품목이 이 구역 것인지 먼저 본다. 팔을 붙이기 전에 걸러야 한다 —
    # policy_catalog 가 fail-closed 로 거절하는 것을 여기서 미리 확인해,
    # 로봇·카메라를 붙였다가 첫 품목에서 실패하는 일을 막는다.
    try:
        import policy_catalog
        for item in items:
            policy_catalog.lookup(item.product_code, zone=zone)
    except Exception as error:
        log(f'{type(error).__name__}: {error}')
        return EXIT_BAD_ORDER

    log('주문: ' + ', '.join(
        f'{i.product_code}x{i.reserved_quantity}' for i in items))

    if args.dry_run:
        log(f'모의 실행 — 팔에 아무것도 안 냅니다 '
            f'({time.monotonic() - started:.1f}초)')
        return EXIT_OK

    if not args.port:
        log('--port 가 없습니다 (또는 $OMX_PORT)')
        return EXIT_NO_ARM

    # ── 팔 코드 부르기 ────────────────────────────────────────────────────
    try:
        import bench
        import deliver
        import mock_inputs
        import policy_runtime
        import robot_session
    except Exception as error:
        log(f'팔 코드를 못 불러왔습니다: {type(error).__name__}: {error}')
        log('lerobot 이 있는 python 으로 돌려야 합니다 (~/venv/il/bin/python).')
        return EXIT_NO_DRIVER

    try:
        front_cam, wrist_cam = resolve_cameras(args)
    except Exception as error:
        log(f'카메라를 못 정했습니다: {error}')
        return EXIT_NO_ARM

    order = mock_inputs.MockOrder(
        order_id=f'rmf-{namespace}-{int(started)}',
        # RMF 에는 job_step_id 가 없다. JSONL 기록을 위한 자리라 0 을 둔다.
        job_step_id=0,
        assignment_revision=1,
        items=items,
        # 도착은 RMF 와 워크셀이 이미 보증했다. 위 docstring 참고.
        pinky=mock_inputs.MockPinkyArrival(already_arrived=True),
    )

    catcher = VerdictCatcher()

    try:
        robot = robot_session.build_robot(
            port=args.port,
            cameras=(
                robot_session.CameraSpec(
                    'front', front_cam, width=args.cam_width,
                    height=args.cam_height, fps=args.cam_fps),
                robot_session.CameraSpec(
                    'wrist', wrist_cam, width=args.cam_width,
                    height=args.cam_height, fps=args.cam_fps),
            ),
        )
        with robot_session.RobotSession(robot) as connected, catcher:
            features = policy_runtime.build_dataset_features(connected)
            deliver.run_order(
                connected, features, order,
                zone=zone,
                episode_steps=args.episode_steps,
                fps=args.fps,
                bench_=bench.Bench(),
                debug_gripper=args.debug_gripper,
                is_first_order=True,
                worker_id=f'rmf-{namespace}',
            )
    except Exception as error:
        log(f'팔을 못 움직였습니다: {type(error).__name__}: {error}')
        return EXIT_NO_ARM

    elapsed = time.monotonic() - started

    # ── 판정을 종료 코드로 ────────────────────────────────────────────────
    if catcher.outcome is None:
        # run_order 는 어떤 길로 끝나도 report_outcome 을 부른다. 안 불렸다면
        # 우리가 모르는 길로 빠진 것이니 성공으로 치지 않는다.
        log('판정이 안 나왔습니다 — 성공으로 보지 않습니다')
        return EXIT_NOT_HANDED_OVER
    if catcher.outcome == 'succeeded':
        log(f'인계를 끝냈습니다 — {elapsed:.1f}초')
        return EXIT_OK
    log(f'인계를 확인 못 했습니다 [{catcher.reason_code}] — {elapsed:.1f}초')
    return EXIT_NOT_HANDED_OVER


def resolve_cameras(args):
    """`--front-cam/--wrist-cam` 이 없으면 set_cameras.py 가 저장한 값을 쓴다.

    `deliver._resolve_camera_ports()` 와 같은 규칙이다. 그것을 그대로 부르지
    않는 것은 그 함수가 `SystemExit` 를 던지기 때문이다 — 여기서는 종료 코드를
    우리가 정해야 한다.
    """
    import camera_config

    if args.front_cam and args.wrist_cam:
        return args.front_cam, args.wrist_cam
    saved = camera_config.load()
    if saved is None:
        raise RuntimeError(
            '카메라 포트를 모릅니다 — --front-cam/--wrist-cam 을 주거나 '
            'set_cameras.py 로 저장하세요')
    front = args.front_cam or saved.front
    wrist = args.wrist_cam or saved.wrist
    log(f'저장된 카메라 포트: front={front} wrist={wrist}')
    return front, wrist


if __name__ == '__main__':
    sys.exit(main())
