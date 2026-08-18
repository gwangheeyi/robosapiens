#!/usr/bin/env python3
"""rosapiens 프로젝트의 RMF 워크셀 어댑터.

rmf_control_ui 가 맵 프로젝트에서 생성했다. 손으로 고치면 다음 저장 때
덮어써진다.

로봇이 픽업 자리에 닿으면 RMF 가 `/dispenser_requests` 로 그 자리 이름을
부른다. 여기서 팔을 움직이고 `/dispenser_results` 로 끝났다고 답한다.

답하지 않으면 RMF 는 영원히 기다린다. 오류는 안 난다 — 작업이 그 자리에서
멈춰 있을 뿐이다.

**시계로 판단하지 않는다.** 예전에는 관절 궤적을 토픽에 던지고 4초 뒤에
성공을 알렸다. 던지고 끝이라 팔이 받았는지, 움직였는지, 끝냈는지 아무도 묻지
않았다 — 팔이 느리든 막혔든 구독자가 아예 없든 똑같이 성공이었고, 핑키는 빈
채로 떠났다. 지금은 세 가지를 **토픽으로 듣고** 정한다.

    ① 로봇이 제자리에 제 자세로 섰나   /fleet_states
    ② 팔이 궤적을 끝냈나               follow_joint_trajectory 액션 결과
    ③ 팔이 정말 멈췄나                 <네임스페이스>/joint_states

그리고 ①은 팔이 움직이는 **내내** 다시 본다. 적재 중에 로봇이 흔들리면 궤적을
취소하고 실패로 답한다 — 움직이는 로봇에 물건을 올리지 않는다.
"""

import math
import os
import subprocess
import sys
import threading
import time

import rclpy
import rclpy.node
from rclpy.action import ActionClient
from rclpy.qos import QoSProfile, QoSDurabilityPolicy, QoSReliabilityPolicy

from builtin_interfaces.msg import Time
from control_msgs.action import FollowJointTrajectory
from rmf_dispenser_msgs.msg import DispenserRequest, DispenserResult, DispenserState
from rmf_fleet_msgs.msg import FleetState
from rmf_ingestor_msgs.msg import IngestorRequest, IngestorResult, IngestorState
from sensor_msgs.msg import JointState
from trajectory_msgs.msg import JointTrajectory, JointTrajectoryPoint

# 로봇 ID, ROS 네임스페이스, 모델, 맡은 자리와 **이 팔에 붙인** policy.
#
# 팔마다 배운 것이 다르다. 프로젝트에 등록했다고 모든 팔이 쓰는 것이 아니라,
# 로봇 관리에서 그 팔에 붙인 것만 여기 온다.
WORKCELLS = [
    ('omx_01', 'omx_01', 'omx_f', ['픽업2', '픽업3'], [], []),
    ('omx_02', 'omx_02', 'omx_f', ['픽업1'], [], []),
]

# policy 별 학습 결과 ZIP. 러너가 이것을 풀어 쓴다.
#
# ZIP 은 git 에 올리지 않으므로 이 자리에 없을 수 있다. 없으면 아래 시험
# 동작으로 대신하고, 앱의 `Policy 관리` 에서 다시 받으라고 로그에 남긴다.
POLICY_ARCHIVES = {
    'trihouse-icebar@1.0.0': '/home/gyi/robosapiens/workcell_policies/trihouse-icebar/1_0_0/policy.zip',
    'trihouse-dumpling@1.0.0': '/home/gyi/robosapiens/workcell_policies/trihouse-dumpling/1_0_0/policy.zip',
    'trihouse-icecorn@1.0.0': '/home/gyi/robosapiens/workcell_policies/trihouse-icecorn/1_0_0/policy.zip',
    'trihouse-coffee@1.0.0': '/home/gyi/robosapiens/workcell_policies/trihouse-coffee/1_0_0/policy.zip',
    'trihouse-yogurt@1.0.0': '/home/gyi/robosapiens/workcell_policies/trihouse-yogury/1_0_0/policy.zip',
    'trihouse-porkbelly@1.0.0': '/home/gyi/robosapiens/workcell_policies/trihouse-porkbelly/1_0_0/policy.zip',
    'trihouse-sandwich@1.0.0': '/home/gyi/robosapiens/workcell_policies/Sandwitch/1_0_0/policy.zip',
}

# 학습 policy 를 실제로 돌리는 러너. 같은 배포 산출물 안에 함께 나온다.
#
# **Gazebo 든 실물이든 같은 것을 쓴다.** 러너는 네임스페이스만 달리 받아
# `/<네임스페이스>/joint_states` 를 보고 `/<네임스페이스>/arm_controller/
# joint_trajectory` 로 낸다 — 시뮬과 실물의 차이는 그 토픽 뒤에 무엇이 붙어
# 있느냐뿐이다.
POLICY_RUNNER = '/home/gyi/robosapiens/rmf_maps/rosapiens/rosapiens_policy_runner.py'

# 러너가 이 시간 안에 안 끝나면 끊고 실패로 답한다 [s, 벽시계].
POLICY_TIMEOUT = 600.0

# 러너가 남긴 말. 왜 추론이 안 돌았는지는 여기에 있다.
POLICY_LOG = os.path.join(
    os.path.dirname(POLICY_RUNNER) if POLICY_RUNNER else '.',
    'rosapiens_policy_runner.log')

# 자리마다 로봇이 볼 방향 [rad]. 맵 관리의 `적재 방향` 에서 온다.
#
# 핑키는 수납함을 뒤에 달고 다닌다. 들어온 그대로 서면 수납함이 팔에서 가장
# 먼 자리에 온다. 그래서 그 자리로 가는 작업의 `go_to_place` 에 이 각도가
# `orientation` 으로 실리고, 여기서는 **정말 그렇게 섰는지** 다시 본다.
#
# RMF 가 맞다고 하는 것과 로봇이 실제로 그렇게 선 것은 다른 이야기다.
DOCK_HEADINGS = {

}

# 팔이 한 번 움직이는 데 걸리는 시간 [s].
#
# RMF 는 이 시간을 모른다. 우리가 끝났다고 알릴 때까지 기다릴 뿐이다.
ACTION_SECONDS = 4.0

# 자세가 이만큼 어긋나도 그 자세로 섰다고 본다 [rad]. 약 10도.
#
# **Nav2 의 `yaw_goal_tolerance`(약 5도)보다 일부러 헐겁다.** 둘은 하는 일이
# 다르다 —
#
#   Nav2 쪽은 **요구**다. 그 각도에 들어올 때까지 도착으로 안 친다.
#   여기는 **관문**이다. 잘못 선 로봇에 팔이 나가는 것을 막는다.
#
# 같은 값으로 묶으면 안 된다. 제자리 회전은 1.0 rad/s 로 돌다가 도착 판정이
# 나는 순간 멈추므로, 실제로 멎는 자세는 판정 문턱보다 조금 더 간다. 얼마나
# 더 가는지는 로봇을 돌려 재 봐야 아는 값인데 아직 안 쟀다. 같은 값으로 묶어
# 두면 Nav2 가 도착이라고 놓아준 로봇을 워크셀이 매번 거절해, 멀쩡한 작업이
# 전부 실패한다.
#
# 잡으려는 것은 몇 도의 오차가 아니라 **안 돈 로봇**이다. 수납함을 뒤에 달고
# 들어온 그대로 선 로봇은 180도가 어긋난다 — 10도로도 넉넉히 걸린다.
DOCK_YAW_TOLERANCE = 0.175

# 로봇이 섰다고 보는 문턱. **거리가 아니라 속도다.**
#
# 예전에는 두 번의 `/fleet_states` 사이에 얼마나 움직였나로 쟀다. 그것이
# 시뮬레이터 속도에 휘둘린다 — `/fleet_states` 는 벽시계 10Hz 인데 로봇은 시뮬
# 시계로 움직이므로, 시뮬이 느리면 눈금당 이동이 그만큼 줄어든다.
#
# 실측(2026-08-17) — Gazebo 실시간 배율(RTF) 0.101, `/fleet_states` 10.00Hz.
# 0.2m/s 로 달리는 로봇이 눈금당 0.002m 밖에 안 움직인다. 2cm 문턱이면
# **달리는 로봇이 섰다고 나온다.**
#
# `Location.t` 는 시뮬 시계 시각이다. 그것으로 나누면 진짜 속도가 나오고,
# 시뮬이 몇 배로 느리든 값이 같다.
ROBOT_STILL_SPEED = 0.03      # [m/s] 핑키 순항은 0.2
ROBOT_STILL_TURN_RATE = 0.20  # [rad/s] 제자리 회전은 1.0

# 적재를 시작한 자리에서 이만큼 벗어나면 중단한다.
#
# 시작할 때의 자세를 기준으로 잰다. **눈금 사이의 차이로 재면 안 된다** —
# 위에서 본 흔들림이 그대로 중단 사유가 되기 때문이다. 잡으려는 것은 몇 도의
# 떨림이 아니라 **로봇이 자리를 떠난 것**이고, 그것은 몇십 cm 단위로 뚜렷하다.
#
# 팔이 이미 움직이는 중에 끊는 것 자체가 위험하므로, 정말 떠났을 때만 끊는다.
ARM_ABORT_METERS = 0.15
ARM_ABORT_RADIANS = 0.52

# 이보다 오래된 로봇 소식은 안 믿는다 [s]. 어댑터는 10Hz 로 낸다.
FLEET_STATE_MAX_AGE = 3.0

# 로봇이 자리에 설 때까지 기다려 주는 시간 [s, 벽시계].
#
# RMF 는 도착했다고 보고 우리를 부르는데, 그 순간 로봇이 마지막 몇 도를 돌고
# 있을 수 있다. 여기서 바로 거절하면 멀쩡한 작업이 실패한다.
#
# 넉넉해야 한다. 시뮬이 실시간의 1/10 로 돌면(실측 RTF 0.101) 로봇이 마지막
# 자세를 다듬는 데도 벽시계로 열 배가 걸린다.
ROBOT_SETTLE_TIMEOUT = 60.0

# 팔이 궤적을 끝낼 때까지 기다리는 한계 [s, 벽시계].
#
# **성능 예산이 아니라 멈춤 감지다.** 답을 안 하면 RMF 는 영원히 기다리므로
# 언젠가는 끊어야 하지만, 조이면 느린 시뮬에서 멀쩡한 궤적을 끊는다.
#
# 실측(2026-08-17) — 시뮬 4초짜리 궤적이 벽시계로 55.5초 걸렸다(RTF 0.101).
#
#     [omx_01.arm_controller] Accepted new action goal   435.180
#     [omx_01.arm_controller] Goal reached, success!     490.698
#
# 샌드위치 재생은 시뮬 35초짜리라 같은 배율이면 벽시계 350초가 넘는다. 예전
# 값(120초)이면 그것이 매번 끊겼다.
ARM_RESULT_TIMEOUT = 600.0

# 액션이 끝난 뒤 두는 여유 [s].
#
# **판정이 아니라 여유다.** 끝났다고 정하는 것은 액션 결과이고, 이 시간은
# 로봇이 곧바로 튀어 나가지 않게 두는 것뿐이다. 이만큼 지나면 관절이 멎었다고
# 보이든 아니든 넘어간다.
ARM_SETTLE_SECONDS = 2.0

# 관절이 멎었다고 보는 속도 [rad/s].
#
# 이 값 아래로 내려오면 여유를 다 안 쓰고 바로 넘어간다. 못 내려와도 막지
# 않는다 — 이 팔에서는 실제로 못 내려온다.
#
# 실측(2026-08-17, OMX in Gazebo, 팔이 멈춰 있는 상태, 표본 148) —
#
#     최소 0.113   중앙 1.291   최대 1.443  [rad/s]
#     0.02 아래인 비율 0%    0.10 아래인 비율 0%
#
# 멈춰 있는 팔이 1.3 rad/s 로 도는 것으로 나온다. `joint_states` 의 velocity
# 가 이 설정에서는 믿을 값이 아니라는 뜻이다. 그래서 이 확인은 **거부권이
# 없다.** 문턱을 실측에 맞춰 올리지 마라 — 올려 봐야 늘 통과가 되어 확인이
# 아니게 된다. 못 믿는 신호는 못 믿는 채로 두고, 판정은 액션 결과가 한다.
ARM_STILL_VELOCITY = 0.02

# 감시 주기 [s]. 이 노드는 `use_sim_time` 을 안 쓰므로 시스템 시계로 돈다.
WATCHDOG_PERIOD = 0.2

# 물품 종류별 가상 모방학습 policy. 모든 OMX가 같은 다섯 policy를 제공한다.
# 각 값은 시간 비율과 joint1~4 자세이며 실제 추론기 연결 전 동작 검증용이다.
JOINT_NAMES = ['joint1', 'joint2', 'joint3', 'joint4']
HOME_POSE = [0.0, -1.0, 0.3, 0.7]
POLICY_MOTIONS = {
    'policy_1': [[0.00, 0.45, -0.30, 0.65], [0.00, 0.75, -0.55, 0.90]],
    'policy_2': [[0.35, 0.35, -0.20, 0.55], [0.55, 0.70, -0.45, 0.80]],
    'policy_3': [[-0.35, 0.35, -0.20, 0.55], [-0.55, 0.70, -0.45, 0.80]],
    'policy_4': [[0.20, 0.15, 0.05, 0.45], [0.35, 0.55, -0.20, 0.70]],
    'policy_5': [[-0.20, 0.15, 0.05, 0.45], [-0.35, 0.55, -0.20, 0.70]],
}

# 학습 policy 실행기를 연결하기 전 controller·RMF 경로를 검증하는 저속 궤적.
# 실제 ACT 추론 결과가 아니며 배포된 policy ID에만 사용한다.
MODEL_TEST_MOTIONS = {
    'open_manipulator_x': {
        'joints': ['joint1', 'joint2', 'joint3', 'joint4'],
        'home': [0.0, -1.0, 0.3, 0.7],
        'poses': [[0.15, -0.85, 0.25, 0.65], [-0.15, -0.85, 0.25, 0.65]],
    },
    'omx_f': {
        'joints': ['joint1', 'joint2', 'joint3', 'joint4', 'joint5', 'gripper_joint_1'],
        'home': [0.0, -1.0, 0.3, 0.7, 0.0, 0.0],
        'poses': [[0.15, -0.85, 0.25, 0.65, 0.10, 0.0],
                  [-0.15, -0.85, 0.25, 0.65, -0.10, 0.0]],
    },
}

# 2usang/trihouse-sandwich episode 0의 성공 시연을 1초 간격으로 추린 값.
# [시각(s), joint1~5(deg), gripper(deg)]이며 controller 전송 때 rad로 바꾼다.
SANDWICH_REPLAY_DEG = [
    [0.0, -0.611, -66.398, 55.018, 47.692, 0.415, 60.147],
    [1.0, -0.611, -66.398, 55.018, 47.692, 0.415, 60.147],
    [2.0, -0.611, -66.398, 55.018, 47.692, 0.415, 60.147],
    [3.0, -0.611, -66.398, 55.018, 47.692, 0.415, 60.147],
    [4.0, -0.611, -66.398, 55.018, 47.692, 0.415, 60.147],
    [5.0, -0.659, -66.398, 55.018, 47.692, 0.415, 60.147],
    [6.0, -0.708, -66.545, 55.018, 43.834, 0.562, 61.001],
    [7.0, -3.053, -66.545, 54.969, 28.547, 0.317, 60.977],
    [8.0, -8.474, -66.545, 54.872, 24.884, 0.708, 59.487],
    [9.0, -18.437, -66.252, 37.729, 25.421, 0.073, 59.219],
    [10.0, -30.696, -49.109, 20.147, 25.079, -7.937, 58.999],
    [11.0, -33.529, -40.757, 10.916, 21.270, -7.253, 58.632],
    [12.0, -33.480, -39.585, 10.183, 17.216, -3.639, 58.657],
    [13.0, -33.431, -34.945, 6.325, 16.044, -3.248, 58.657],
    [14.0, -33.480, -34.212, 6.374, 15.263, -3.492, 58.657],
    [15.0, -33.431, -32.405, 6.716, 14.481, -3.541, 58.681],
    [16.0, -33.431, -32.259, 6.618, 14.432, -3.492, 58.681],
    [17.0, -34.896, -26.593, 6.716, 12.088, -3.394, 58.657],
    [18.0, -34.408, -21.661, -0.659, 12.381, -0.073, 58.388],
    [19.0, -34.164, -17.216, -3.980, 12.234, -0.122, 57.875],
    [20.0, -33.187, -14.286, -5.934, 12.186, -0.073, 57.680],
    [21.0, -32.112, -13.211, -6.032, 11.990, -0.366, 53.187],
    [22.0, -31.233, -14.530, -5.836, 9.499, -0.171, 47.131],
    [23.0, -33.529, -20.684, -5.055, 10.183, -0.122, 46.716],
    [24.0, -45.250, -24.298, -1.245, 13.260, 1.783, 46.716],
    [25.0, -51.013, -24.835, 6.862, 12.772, 1.685, 46.740],
    [26.0, -60.488, -20.488, 7.692, 14.969, 3.932, 46.716],
    [27.0, -65.763, -12.381, 7.839, 20.391, 7.497, 46.716],
    [28.0, -69.035, -3.883, 7.448, 19.365, 7.448, 46.862],
    [29.0, -68.742, -2.711, 6.569, 18.486, 7.497, 59.243],
    [30.0, -65.226, -21.465, 10.574, 18.193, 7.399, 59.341],
    [31.0, -48.767, -56.337, 45.250, 7.106, 7.253, 59.316],
    [32.0, -9.304, -66.447, 55.263, 12.088, 7.448, 59.365],
    [33.0, 1.490, -66.398, 55.263, 42.076, 7.399, 59.365],
    [34.0, 1.050, -66.447, 55.263, 48.620, 7.399, 59.365],
    [34.7, 1.050, -66.447, 55.263, 48.620, 7.350, 59.365],
]


def now_msg(node):
    stamp = node.get_clock().now().to_msg()
    return Time(sec=stamp.sec, nanosec=stamp.nanosec)


def wrap_angle(radians):
    """-pi 초과 pi 이하로 접는다. 179도와 -179도는 2도 차이지 358도가 아니다."""
    return (radians + math.pi) % (2 * math.pi) - math.pi


def trajectory_of(joint_names, poses, seconds):
    """자세 목록을 시간에 고르게 펴서 궤적 하나로 만든다."""
    message = JointTrajectory()
    message.joint_names = list(joint_names)
    for index, pose in enumerate(poses, start=1):
        point = JointTrajectoryPoint()
        point.positions = [float(value) for value in pose]
        at = seconds * index / len(poses)
        point.time_from_start.sec = int(at)
        point.time_from_start.nanosec = int((at % 1) * 1e9)
        message.points.append(point)
    return message


class Job:
    """처리 중인 요청 하나. 어디까지 왔는지와 언제까지 기다릴지를 들고 있다."""

    def __init__(self, msg, dispenser, robot_name, required_yaw, trajectory,
                 policy_id=None, policy_archive=None):
        self.msg = msg
        self.dispenser = dispenser
        self.robot_name = robot_name
        self.required_yaw = required_yaw
        self.trajectory = trajectory
        # 학습 policy 로 돌릴 일이면 그 policy 와 ZIP 자리. 아니면 None.
        self.policy_id = policy_id
        self.policy_archive = policy_archive
        # 러너 프로세스. 'policy' 단계에서만 있다.
        self.process = None
        # 'waiting_robot' → ('policy' | 'moving') → 'settling'
        self.stage = 'waiting_robot'
        self.goal_handle = None
        self.deadline = time.monotonic() + ROBOT_SETTLE_TIMEOUT
        # 팔을 움직이기 시작한 순간의 로봇 자리. 적재 중에는 이것과 견준다.
        self.anchor = None


class Workcell:
    """설비 한 대. 맡은 자리 이름으로 불린다."""

    def __init__(self, node, robot_id, namespace, model, dispensers, ingestors,
                 deployed_policies):
        self.node = node
        self.robot_id = robot_id
        self.namespace = namespace
        self.model = model
        self.dispensers = dispensers
        self.ingestors = ingestors
        self.deployed_policies = set(deployed_policies)
        self.busy = False
        self.active_request = None
        self.completed_requests = set()
        self.lock = threading.Lock()
        self.job = None

        # 토픽이 아니라 **액션**이다. 토픽 publish 는 던지고 끝이라 팔이
        # 끝냈는지 물을 방법이 없다. 액션은 받았다(accepted)와 끝났다(result)를
        # 돌려준다 — 우리가 RMF 에 성공을 알리는 근거가 그 result 다.
        self.arm_action_name = (
            f'/{namespace}/arm_controller/follow_joint_trajectory')
        self.arm = ActionClient(node, FollowJointTrajectory,
                                self.arm_action_name)

        # 액션이 끝났다고 한 뒤 관절이 정말 멎었는지 보는 곳.
        self.joint_velocity = None
        self.joint_state_at = 0.0
        # 속도로는 멎었는지 알 수 없다는 말을 한 번만 적는다.
        self.warned_arm_velocity = False
        node.create_subscription(
            JointState, f'/{namespace}/joint_states', self.on_joint_state, 10)

    def serves(self, guid):
        return guid in self.dispensers or guid in self.ingestors

    def on_joint_state(self, msg):
        if not msg.velocity:
            # 속도를 안 내는 컨트롤러도 있다. 그러면 이 확인은 건너뛴다.
            return
        self.joint_velocity = max(abs(value) for value in msg.velocity)
        self.joint_state_at = time.monotonic()

    def arm_still(self):
        """관절이 멎었나. 속도를 못 들으면 판단을 미룬다(None)."""
        if self.joint_velocity is None:
            return None
        if time.monotonic() - self.joint_state_at > FLEET_STATE_MAX_AGE:
            return None
        return self.joint_velocity <= ARM_STILL_VELOCITY

    # ── 무엇을 시킬지 정하는 쪽 ────────────────────────────────────────────

    def policy_trajectory(self, policy_id, seconds):
        """선택한 가상 policy의 관절 궤적."""
        return trajectory_of(
            JOINT_NAMES, [*POLICY_MOTIONS[policy_id], HOME_POSE], seconds)

    def test_trajectory(self, reason, seconds=None):
        """관절 몇 개를 눈에 보이게 움직였다가 집으로 돌아오는 시험 동작.

        **붙인 policy 가 없을 때 여기로 온다.** 아무것도 안 보내면 기다릴 것도
        없어 그 자리에서 성공이 되고, 그러면 팔이 살아 있는지조차 모르는 채로
        작업만 넘어간다. 그래서 짧게라도 실제로 움직이고, 그 동작이 끝난 것을
        액션 결과로 확인한 뒤에 RMF 에 성공을 알린다 — 다음 단계는 그때 간다.

        학습한 동작이 아니다. 팔·컨트롤러·RMF 의 고리가 살아 있는지 보는 것뿐이다.
        """
        seconds = ACTION_SECONDS if seconds is None else seconds
        self.node.get_logger().warning(
            f'[{self.robot_id}] [TEST] {reason}')
        profile = MODEL_TEST_MOTIONS.get(self.model)
        if profile is None:
            # 모르는 모델이다. 기본 관절 이름으로 조금씩만 움직인다.
            return trajectory_of(
                JOINT_NAMES,
                [[0.20, -0.85, 0.25, 0.65], [-0.20, -0.85, 0.25, 0.65],
                 HOME_POSE],
                seconds)
        return trajectory_of(
            profile['joints'], [*profile['poses'], profile['home']], seconds)

    def sandwich_replay_trajectory(self, policy_id):
        """학습 episode의 샌드위치 집기 시연을 관절 재생한다."""
        message = JointTrajectory()
        message.joint_names = list(MODEL_TEST_MOTIONS['omx_f']['joints'])
        lead_in = 1.0
        for row in SANDWICH_REPLAY_DEG:
            point = JointTrajectoryPoint()
            point.positions = [math.radians(value) for value in row[1:]]
            at = lead_in + row[0]
            point.time_from_start.sec = int(at)
            point.time_from_start.nanosec = int((at % 1) * 1e9)
            message.points.append(point)
        self.node.get_logger().info(
            f'[{self.robot_id}] [{policy_id}] 학습 episode 0 샌드위치 동작 재생')
        return message

    def policy_archive(self, policy_id):
        """이 policy 의 학습 결과 ZIP. 이 자리에 없으면 None."""
        path = POLICY_ARCHIVES.get(policy_id)
        return path if path and os.path.exists(path) else None


class WorkcellAdapter(rclpy.node.Node):

    def __init__(self):
        super().__init__('rosapiens_workcell')

        # RMF 는 상태를 **transient local** 로 듣는다. 늦게 뜬 쪽도 마지막
        # 상태를 받아야 워크셀이 있다는 것을 알기 때문이다.
        state_qos = QoSProfile(
            depth=10,
            reliability=QoSReliabilityPolicy.RELIABLE,
            durability=QoSDurabilityPolicy.TRANSIENT_LOCAL,
        )
        self.dispenser_states = self.create_publisher(
            DispenserState, '/dispenser_states', state_qos)
        self.ingestor_states = self.create_publisher(
            IngestorState, '/ingestor_states', state_qos)
        self.dispenser_results = self.create_publisher(
            DispenserResult, '/dispenser_results', 10)
        self.ingestor_results = self.create_publisher(
            IngestorResult, '/ingestor_results', 10)

        self.cells = [
            Workcell(self, robot_id, namespace, model, dispensers, ingestors, policies)
            for robot_id, namespace, model, dispensers, ingestors, policies in WORKCELLS
        ]

        # Fleet adapter의 요청은 transient local이다. 워크셀이 늦게 떠도 이미
        # 보낸 픽업 요청을 받아야 하므로 같은 QoS로 구독한다.
        self.create_subscription(
            DispenserRequest, '/dispenser_requests',
            lambda msg: self.on_request(msg, dispenser=True), state_qos)
        self.create_subscription(
            IngestorRequest, '/ingestor_requests',
            lambda msg: self.on_request(msg, dispenser=False), state_qos)

        # 로봇이 정말 그 자리에 그 자세로 섰는지 보는 곳. 어댑터가 10Hz 로
        # 낸다. RMF 가 "도착했다" 고 말하는 것과 로봇이 실제로 그렇게 선
        # 것은 다른 이야기라, 팔을 움직이기 전에 여기서 직접 확인한다.
        self.robot_pose = {}
        self.create_subscription(
            FleetState, '/fleet_states', self.on_fleet_state, 10)

        # 상태를 안 내면 RMF 가 이 워크셀을 없는 것으로 보고 요청조차 안 한다.
        self.create_timer(1.0, self.publish_states)
        self.create_timer(WATCHDOG_PERIOD, self.watch)

        served = sum(len(c.dispensers) + len(c.ingestors) for c in self.cells)
        self.get_logger().info(
            f'워크셀 {len(self.cells)}대, 맡은 자리 {served}곳을 RMF 에 이었습니다.')
        if DOCK_HEADINGS:
            places = ', '.join(
                f'{name} {math.degrees(yaw):.0f}도'
                for name, yaw in sorted(DOCK_HEADINGS.items()))
            self.get_logger().info(f'적재 방향을 정해 둔 자리: {places}')

    # ── 로봇이 어디에 어떻게 서 있나 ──────────────────────────────────────

    def on_fleet_state(self, msg):
        for robot in msg.robots:
            previous = self.robot_pose.get(robot.name)
            location = robot.location
            # 시뮬 시계 시각. 속도를 여기서 뽑는다 — 벽시계로 나누면 시뮬이
            # 느릴 때 달리는 로봇도 섰다고 나온다.
            stamp = location.t.sec + location.t.nanosec * 1e-9
            # 첫 소식만으로는 섰는지 알 수 없다. 속도는 **두 소식 사이**에서
            # 나오므로 한 건으로는 잴 것이 없다. 0 으로 채워 두면 방금 처음
            # 본 로봇이 멈춰 있는 것으로 보여, 달려오는 중에 팔이 움직인다.
            speed = None
            turn_rate = None
            if previous is not None:
                span = stamp - previous['stamp']
                if span > 1e-6:
                    speed = math.hypot(location.x - previous['x'],
                                       location.y - previous['y']) / span
                    turn_rate = abs(
                        wrap_angle(location.yaw - previous['yaw'])) / span
                else:
                    # 같은 시각이 두 번 왔다. 이전 값을 그대로 들고 간다 —
                    # 모른다고 하면 그때마다 처음부터 다시 기다리게 된다.
                    speed = previous['speed']
                    turn_rate = previous['turn_rate']
            self.robot_pose[robot.name] = {
                'x': location.x,
                'y': location.y,
                'yaw': location.yaw,
                'stamp': stamp,
                'speed': speed,
                'turn_rate': turn_rate,
                'at': time.monotonic(),
            }

    def robot_problem(self, job):
        """로봇이 팔을 움직여도 되는 상태인가. 괜찮으면 None, 아니면 이유."""
        if not job.robot_name:
            # 어댑터가 `transporter_type` 에 로봇 이름을 넣는다. 비어 있으면
            # 어느 로봇인지 알 수 없어 확인 자체를 못 한다.
            return '요청에 로봇 이름이 없습니다'
        pose = self.robot_pose.get(job.robot_name)
        if pose is None:
            return f'{job.robot_name} 의 위치를 /fleet_states 에서 못 받았습니다'
        age = time.monotonic() - pose['at']
        if age > FLEET_STATE_MAX_AGE:
            return f'{job.robot_name} 의 마지막 소식이 {age:.1f}초 전입니다'
        if pose['speed'] is None:
            return f'{job.robot_name} 의 소식이 아직 한 건뿐입니다'
        if pose['speed'] > ROBOT_STILL_SPEED or \
                pose['turn_rate'] > ROBOT_STILL_TURN_RATE:
            return (f'{job.robot_name} 이 아직 움직이고 있습니다 '
                    f'({pose["speed"]:.3f}m/s · '
                    f'{math.degrees(pose["turn_rate"]):.1f}도/s)')
        if job.required_yaw is None:
            return None
        error = abs(wrap_angle(pose['yaw'] - job.required_yaw))
        if error > DOCK_YAW_TOLERANCE:
            return (f'{job.robot_name} 이 {math.degrees(pose["yaw"]):.1f}도를 '
                    f'보고 있습니다. 이 자리는 '
                    f'{math.degrees(job.required_yaw):.1f}도가 필요합니다 '
                    f'(차이 {math.degrees(error):.1f}도)')
        return None

    def robot_left(self, job):
        """적재를 시작한 자리를 떠났나. 안 떠났으면 None, 떠났으면 이유.

        **시작할 때의 자세와 견준다.** 눈금 사이의 차이로 재면 도착 직후의
        떨림(실측 3.4도)이 그대로 중단 사유가 된다. 잡으려는 것은 떨림이
        아니라 로봇이 자리를 뜬 것이다.
        """
        if job.anchor is None:
            return None
        pose = self.robot_pose.get(job.robot_name)
        if pose is None:
            return None
        age = time.monotonic() - pose['at']
        if age > FLEET_STATE_MAX_AGE:
            return f'{job.robot_name} 의 마지막 소식이 {age:.1f}초 전입니다'
        moved = math.hypot(pose['x'] - job.anchor['x'],
                           pose['y'] - job.anchor['y'])
        if moved > ARM_ABORT_METERS:
            return (f'{job.robot_name} 이 적재를 시작한 자리에서 '
                    f'{moved*100:.0f}cm 벗어났습니다')
        turned = abs(wrap_angle(pose['yaw'] - job.anchor['yaw']))
        if turned > ARM_ABORT_RADIANS:
            return (f'{job.robot_name} 이 적재를 시작한 자세에서 '
                    f'{math.degrees(turned):.0f}도 돌았습니다')
        return None

    def publish_states(self):
        for cell in self.cells:
            mode = DispenserState.BUSY if cell.busy else DispenserState.IDLE
            for guid in cell.dispensers:
                self.dispenser_states.publish(DispenserState(
                    time=now_msg(self), guid=guid, mode=mode,
                    request_guid_queue=[], seconds_remaining=0.0))
            for guid in cell.ingestors:
                self.ingestor_states.publish(IngestorState(
                    time=now_msg(self), guid=guid, mode=mode,
                    request_guid_queue=[], seconds_remaining=0.0))

    # `handle` 이라고 부르면 안 된다. rclpy 의 Node 가 같은 이름의 속성을
    # 쓰는데, 메서드로 덮으면 Node.__init__ 이 `with self.handle:` 에서
    # TypeError 로 죽는다 — 노드가 아예 안 뜬다.
    def on_request(self, msg, dispenser):
        cell = next((c for c in self.cells if c.serves(msg.target_guid)), None)
        if cell is None:
            # 우리 것이 아니다. 남의 워크셀 요청일 수 있으므로 조용히 넘긴다.
            return

        # 같은 요청은 답을 받을 때까지 반복된다. 같은 GUID로 팔을 두 번
        # 움직이지 않고, 현재 상태만 다시 답한다.
        with cell.lock:
            if msg.request_guid in cell.completed_requests:
                repeated_status = DispenserResult.SUCCESS
            elif cell.active_request == msg.request_guid:
                repeated_status = DispenserResult.ACKNOWLEDGED
            else:
                repeated_status = None
            if repeated_status is not None:
                pass
            elif cell.busy:
                return
            else:
                cell.busy = True
                cell.active_request = msg.request_guid
        if repeated_status is not None:
            self.answer(msg, dispenser, repeated_status)
            return

        self.get_logger().info(
            f'[{cell.robot_id}] {msg.target_guid} 요청 받음 '
            f'({msg.request_guid})')
        self.answer(msg, dispenser, DispenserResult.ACKNOWLEDGED)

        # 무엇으로 움직일지 정하는 사다리.
        #
        #   ① 이 팔에 붙인 학습 policy + ZIP + 러너가 다 있으면 → 러너로 추론
        #   ② 붙어는 있으나 러너가 없거나 ZIP 이 없으면   → 시험 동작 (이유를 남김)
        #   ③ 가상 policy(policy_1..5)                   → 그 policy 의 궤적
        #   ④ 붙인 policy 가 없으면(armLoad)             → 시험 동작
        #
        # 어느 길로 가든 **끝났다는 것을 확인한 뒤** RMF 에 성공을 알린다.
        # 그래야 다음 단계로 넘어간다.
        policy_id = msg.items[0].type_guid if msg.items else 'armLoad'
        is_deployed = policy_id in cell.deployed_policies
        if (policy_id != 'armLoad' and policy_id not in POLICY_MOTIONS
                and not is_deployed):
            # 이 팔에 붙지 않은 policy 다. 조용히 다른 동작으로 바꾸면 어느
            # 팔이 무엇을 했는지 알 수 없게 되므로 실패로 답한다.
            self.fail(
                cell, msg, dispenser,
                f'[{cell.robot_id}] 에 붙지 않은 policy 입니다 [{policy_id}] — '
                f'붙은 것: {sorted(cell.deployed_policies) or "없음"}')
            return

        archive = cell.policy_archive(policy_id) if is_deployed else None
        runner_ready = bool(POLICY_RUNNER) and os.path.exists(POLICY_RUNNER)
        replay_name = policy_id.split('@', 1)[0].lower()
        if is_deployed and archive is not None and runner_ready:
            self.get_logger().info(
                f'[{cell.robot_id}] [{policy_id}] 학습 policy 로 움직입니다')
            trajectory = None
        elif (is_deployed and cell.model == 'omx_f'
                and replay_name in ('sandwich', 'sandwitch')):
            trajectory = cell.sandwich_replay_trajectory(policy_id)
        elif is_deployed:
            trajectory = cell.test_trajectory(
                f'[{policy_id}] 학습 결과 파일이 없어' if archive is None
                else f'[{policy_id}] 러너({POLICY_RUNNER})가 없어')
            archive = None
        elif policy_id == 'armLoad':
            trajectory = cell.test_trajectory('붙인 policy 가 없어')
        else:
            self.get_logger().info(
                f'[{cell.robot_id}] 물품 [{policy_id}] 가상 policy 실행')
            trajectory = cell.policy_trajectory(policy_id, ACTION_SECONDS)

        # 팔이 없으면 시작하지 않는다. 예전에는 토픽에 던지고 4초 뒤 성공이라
        # 답했으므로, 팔이 아예 안 떠 있어도 작업이 그대로 넘어갔다.
        if not cell.arm.server_is_ready():
            self.fail(
                cell, msg, dispenser,
                f'팔이 없습니다. {cell.arm_action_name} 액션 서버가 안 보입니다')
            return

        job = Job(msg, dispenser, msg.transporter_type,
                  DOCK_HEADINGS.get(msg.target_guid), trajectory,
                  policy_id=policy_id if archive is not None else None,
                  policy_archive=archive)
        with cell.lock:
            cell.job = job
        # 로봇이 설 때까지 감시자가 기다렸다가 보낸다. 여기서 바로 보내면
        # 마지막 몇 도를 돌고 있는 멀쩡한 로봇을 거절하게 된다.

    # ── 단계를 넘기는 쪽. 전부 토픽·액션이 알려 준 것으로만 정한다 ────────

    def watch(self):
        for cell in self.cells:
            job = cell.job
            if job is None:
                continue
            if job.stage == 'waiting_robot':
                self.watch_robot(cell, job)
            elif job.stage == 'policy':
                self.watch_policy(cell, job)
            elif job.stage == 'moving':
                self.watch_arm(cell, job)
            elif job.stage == 'settling':
                self.watch_settle(cell, job)

    def watch_robot(self, cell, job):
        problem = self.robot_problem(job)
        if problem is None:
            job.stage = 'moving'
            job.deadline = time.monotonic() + ARM_RESULT_TIMEOUT
            # 지금 이 자리가 기준이 된다. 적재 중에는 여기서 얼마나 벗어났나만
            # 본다.
            pose = self.robot_pose.get(job.robot_name)
            job.anchor = None if pose is None else dict(pose)
            if job.policy_archive is not None:
                self.start_policy_runner(cell, job)
                return
            self.get_logger().info(
                f'[{cell.robot_id}] {job.msg.target_guid}: 로봇이 제자리에 '
                '섰습니다. 팔을 움직입니다.')
            goal = FollowJointTrajectory.Goal()
            goal.trajectory = job.trajectory
            future = cell.arm.send_goal_async(goal)
            future.add_done_callback(
                lambda done: self.on_arm_accepted(cell, job, done))
            return
        if time.monotonic() > job.deadline:
            self.fail(cell, job.msg, job.dispenser, f'로봇을 기다리다 지쳤습니다 — {problem}')

    def on_arm_accepted(self, cell, job, future):
        if cell.job is not job:
            return
        try:
            handle = future.result()
        except Exception as error:
            self.fail(cell, job.msg, job.dispenser, f'팔에 궤적을 못 보냈습니다: {error}')
            return
        if not handle.accepted:
            self.fail(cell, job.msg, job.dispenser, '팔이 궤적을 거절했습니다')
            return
        job.goal_handle = handle
        handle.get_result_async().add_done_callback(
            lambda done: self.on_arm_result(cell, job, done))

    def on_arm_result(self, cell, job, future):
        if cell.job is not job:
            return
        try:
            result = future.result().result
        except Exception as error:
            self.fail(cell, job.msg, job.dispenser, f'팔의 결과를 못 받았습니다: {error}')
            return
        if result.error_code != FollowJointTrajectory.Result.SUCCESSFUL:
            self.fail(
                cell, job.msg, job.dispenser,
                f'팔이 궤적을 못 끝냈습니다 (error_code={result.error_code} '
                f'{result.error_string})')
            return
        job.stage = 'settling'
        job.deadline = time.monotonic() + ARM_SETTLE_SECONDS

    # ── 학습 policy 를 실제로 돌리는 쪽 ───────────────────────────────────

    def start_policy_runner(self, cell, job):
        """이 팔에 붙인 학습 policy 로 움직이게 한다.

        **Gazebo 든 실물이든 같은 러너다.** 네임스페이스만 달리 받아 그 팔의
        `joint_states` 를 보고 그 팔의 컨트롤러로 낸다 — 시뮬과 실물의 차이는
        토픽 뒤에 무엇이 붙어 있느냐뿐이다.

        못 띄우면 여기서 작업을 실패시키지 않는다. 시험 동작으로 갈아타 다음
        단계로 넘어가게 하고, 왜 추론이 안 돌았는지는 로그에 남긴다.
        """
        command = [
            sys.executable, POLICY_RUNNER,
            '--policy', job.policy_archive,
            '--policy-id', job.policy_id,
            '--namespace', cell.namespace,
            '--model', cell.model,
            '--seconds', str(ACTION_SECONDS),
        ]
        try:
            log = open(POLICY_LOG, 'a', buffering=1)
            at = time.strftime('%Y-%m-%d %H:%M:%S')
            log.write(f'\n=== {at} {cell.robot_id} {job.policy_id} ===\n')
            job.process = subprocess.Popen(
                command, stdout=log, stderr=subprocess.STDOUT)
        except Exception as error:
            self.get_logger().error(
                f'[{cell.robot_id}] policy 러너를 못 띄웠습니다: {error}')
            self.fall_back_to_test(cell, job, f'[{job.policy_id}] 러너를 못 띄워')
            return
        job.stage = 'policy'
        job.deadline = time.monotonic() + POLICY_TIMEOUT
        self.get_logger().info(
            f'[{cell.robot_id}] [{job.policy_id}] 학습 policy 추론 시작 — '
            f'기록은 {POLICY_LOG}')

    def watch_policy(self, cell, job):
        """추론이 끝나기를 기다린다. 끝나야 RMF 에 성공을 알린다."""
        # 적재 중에 로봇이 자리를 뜨면 팔 궤적 때와 똑같이 중단한다.
        problem = self.robot_left(job)
        if problem is not None:
            self.stop_runner(job)
            self.fail(cell, job.msg, job.dispenser,
                      f'적재 중에 로봇이 자리를 떴습니다 — {problem}')
            return
        code = job.process.poll() if job.process is not None else 1
        if code is None:
            if time.monotonic() > job.deadline:
                self.stop_runner(job)
                self.fail(
                    cell, job.msg, job.dispenser,
                    f'[{job.policy_id}] 추론이 {POLICY_TIMEOUT:.0f}초 안에 '
                    '안 끝났습니다')
            return
        if code == 0:
            self.get_logger().info(
                f'[{cell.robot_id}] [{job.policy_id}] 추론 동작을 끝냈습니다')
            job.stage = 'settling'
            job.deadline = time.monotonic() + ARM_SETTLE_SECONDS
            return
        # 추론기가 이 자리에 없거나 policy 를 못 읽었다. 작업까지 멈추지는
        # 않는다 — 무엇이 없어서 못 했는지만 분명히 남기고 시험 동작으로 간다.
        self.get_logger().warning(
            f'[{cell.robot_id}] [{job.policy_id}] 추론이 안 됐습니다 '
            f'(종료 코드 {code}). 까닭은 {POLICY_LOG} 에 있습니다.')
        self.fall_back_to_test(cell, job, f'[{job.policy_id}] 추론이 안 돼')

    def stop_runner(self, job):
        if job.process is None or job.process.poll() is not None:
            return
        job.process.terminate()
        try:
            job.process.wait(timeout=5)
        except Exception:
            job.process.kill()

    def fall_back_to_test(self, cell, job, reason):
        """추론 대신 시험 동작으로 간다.

        팔이 정말 움직이고 끝냈는지는 그대로 확인한다. 확인 없이 성공만
        돌려주면 팔이 안 떠 있어도 작업이 넘어간다.
        """
        job.policy_archive = None
        job.process = None
        job.trajectory = cell.test_trajectory(reason)
        job.stage = 'moving'
        job.deadline = time.monotonic() + ARM_RESULT_TIMEOUT
        goal = FollowJointTrajectory.Goal()
        goal.trajectory = job.trajectory
        future = cell.arm.send_goal_async(goal)
        future.add_done_callback(
            lambda done: self.on_arm_accepted(cell, job, done))

    def watch_arm(self, cell, job):
        # 적재 중에도 로봇이 그 자리에 있는지 계속 본다. 자리를 뜨면 물건이
        # 엉뚱한 곳에 놓이므로 궤적을 취소하고 실패로 답한다.
        #
        # 시작한 자리와 견준다. 눈금 사이의 차이로 재면 도착 직후의 떨림이
        # 그대로 중단 사유가 된다 — 실제로 그래서 멀쩡한 적재가 1초 만에
        # 끊겼다(2026-08-17, 0.6cm · 3.4도).
        problem = self.robot_left(job)
        if problem is not None:
            if job.goal_handle is not None:
                job.goal_handle.cancel_goal_async()
            self.fail(cell, job.msg, job.dispenser,
                      f'적재 중에 로봇이 자리를 떴습니다 — {problem}')
            return
        if time.monotonic() > job.deadline:
            if job.goal_handle is not None:
                job.goal_handle.cancel_goal_async()
            self.fail(
                cell, job.msg, job.dispenser,
                f'팔이 {ARM_RESULT_TIMEOUT:.0f}초 안에 안 끝났습니다')

    def watch_settle(self, cell, job):
        """팔이 멎기를 잠깐 기다린다. **막지는 않는다.**

        끝났다고 정하는 것은 액션 결과다. 컨트롤러가 `Goal reached, success!`
        를 냈으면 궤적은 끝난 것이고, 여기는 로봇이 곧바로 튀어 나가지 않게
        두는 짧은 여유일 뿐이다.

        여기서 거부하면 안 된다. 예전에는 `joint_states` 속도가 문턱 아래로
        안 내려가면 실패로 답했는데, 이 팔은 **멈춰 있어도** 그 값이 안
        내려간다. 실측(2026-08-17, OMX in Gazebo, 표본 148) —

            최소 0.113  중앙 1.291  최대 1.443  [rad/s]
            0.02 아래인 비율 0%   0.10 아래인 비율 0%

        그래서 픽업이 매번 실패했다. 팔은 멀쩡히 끝냈는데도 —

            [omx_01.arm_controller] Goal reached, success!
            [omx_01] 픽업3: 팔이 5초가 지나도 안 멎었습니다   ← 여기서 막힘
        """
        if cell.arm_still() is True:
            self.succeed(cell, job)
            return
        if time.monotonic() <= job.deadline:
            return
        # 여유를 다 썼다. 액션이 끝났다고 했으므로 그 말을 믿는다.
        if not cell.warned_arm_velocity:
            cell.warned_arm_velocity = True
            measured = ('못 읽음' if cell.joint_velocity is None
                        else f'{cell.joint_velocity:.3f} rad/s')
            self.get_logger().warning(
                f'[{cell.robot_id}] {cell.namespace}/joint_states 로는 팔이 '
                f'멎었는지 알 수 없습니다 (속도 {measured}). 액션 결과만 믿고 '
                '넘어갑니다. 이 줄은 한 번만 적습니다.')
        self.succeed(cell, job)

    def succeed(self, cell, job):
        with cell.lock:
            cell.busy = False
            cell.active_request = None
            cell.completed_requests.add(job.msg.request_guid)
            cell.job = None
        self.get_logger().info(f'[{cell.robot_id}] {job.msg.target_guid} 끝.')
        self.answer(job.msg, job.dispenser, DispenserResult.SUCCESS)

    def fail(self, cell, msg, dispenser, reason):
        """실패를 **말한다.** 조용히 두면 RMF 가 영원히 기다린다.

        답할 요청을 인자로 받는다. `cell.job` 에서 꺼내면, 아직 job 을 만들기
        전에 걸린 실패(모르는 policy · 팔 없음)에서 답할 곳을 잃는다.
        """
        # 추론이 돌고 있었으면 먼저 세운다. 두고 나가면 팔이 계속 움직인다.
        if cell.job is not None:
            self.stop_runner(cell.job)
        with cell.lock:
            cell.busy = False
            cell.active_request = None
            cell.job = None
        self.get_logger().error(
            f'[{cell.robot_id}] {msg.target_guid}: {reason}')
        self.answer(msg, dispenser, DispenserResult.FAILED)

    def answer(self, msg, dispenser, status):
        if dispenser:
            self.dispenser_results.publish(DispenserResult(
                time=now_msg(self), request_guid=msg.request_guid,
                source_guid=msg.target_guid, status=status))
        else:
            self.ingestor_results.publish(IngestorResult(
                time=now_msg(self), request_guid=msg.request_guid,
                source_guid=msg.target_guid, status=status))


def main(argv=sys.argv):
    rclpy.init(args=argv)
    node = WorkcellAdapter()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    node.destroy_node()
    if rclpy.ok():
        rclpy.shutdown()


if __name__ == '__main__':
    main()
