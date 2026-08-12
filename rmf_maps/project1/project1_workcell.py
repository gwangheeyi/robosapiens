#!/usr/bin/env python3
"""project1 프로젝트의 RMF 워크셀 어댑터.

rmf_control_ui 가 맵 프로젝트에서 생성했다. 손으로 고치면 다음 저장 때
덮어써진다.

로봇이 픽업 자리에 닿으면 RMF 가 `/dispenser_requests` 로 그 자리 이름을
부른다. 여기서 팔을 움직이고 `/dispenser_results` 로 끝났다고 답한다.

답하지 않으면 RMF 는 영원히 기다린다. 오류는 안 난다 — 작업이 그 자리에서
멈춰 있을 뿐이다.
"""

import sys
import threading

import rclpy
import rclpy.node
from rclpy.qos import QoSProfile, QoSDurabilityPolicy, QoSReliabilityPolicy

from builtin_interfaces.msg import Time
from rmf_dispenser_msgs.msg import DispenserRequest, DispenserResult, DispenserState
from rmf_ingestor_msgs.msg import IngestorRequest, IngestorResult, IngestorState
from trajectory_msgs.msg import JointTrajectory, JointTrajectoryPoint

# 로봇 ID, ROS 네임스페이스, 맡은 픽업 자리, 맡은 드랍오프 자리.
WORKCELLS = [
    ('OMX_01', 'omx_01', ['픽업1'], []),
    ('OMX_02', 'omx_02', ['픽업2'], []),
]

# 팔이 한 번 움직이는 데 걸리는 시간 [s].
#
# RMF 는 이 시간을 모른다. 우리가 끝났다고 알릴 때까지 기다릴 뿐이다.
ACTION_SECONDS = 4.0

# 집는 자세와 놓는 자세. OpenMANIPULATOR-X 의 관절 넷이다.
#
# 실제 물건 자리에 맞춰 고쳐야 한다. 지금 값은 팔을 앞으로 뻗었다 세우는
# 것뿐이라, 물건을 집지는 않고 **움직임이 실제로 나가는지** 보는 용도다.
JOINT_NAMES = ['joint1', 'joint2', 'joint3', 'joint4']
PICK_POSE = [0.0, 0.6, -0.4, 0.8]
HOME_POSE = [0.0, -1.0, 0.3, 0.7]


def now_msg(node):
    stamp = node.get_clock().now().to_msg()
    return Time(sec=stamp.sec, nanosec=stamp.nanosec)


class Workcell:
    """설비 한 대. 맡은 자리 이름으로 불린다."""

    def __init__(self, node, robot_id, namespace, dispensers, ingestors):
        self.node = node
        self.robot_id = robot_id
        self.namespace = namespace
        self.dispensers = dispensers
        self.ingestors = ingestors
        self.busy = False
        self.lock = threading.Lock()
        self.arm = node.create_publisher(
            JointTrajectory, f'/{namespace}/arm_controller/joint_trajectory', 10)

    def serves(self, guid):
        return guid in self.dispensers or guid in self.ingestors

    def move(self, pose, seconds):
        """팔에 관절 궤적을 보낸다."""
        message = JointTrajectory()
        message.joint_names = list(JOINT_NAMES)
        point = JointTrajectoryPoint()
        point.positions = list(pose)
        point.time_from_start.sec = int(seconds)
        point.time_from_start.nanosec = int((seconds % 1) * 1e9)
        message.points = [point]
        self.arm.publish(message)


class WorkcellAdapter(rclpy.node.Node):

    def __init__(self):
        super().__init__('project1_workcell')

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
            Workcell(self, robot_id, namespace, dispensers, ingestors)
            for robot_id, namespace, dispensers, ingestors in WORKCELLS
        ]

        self.create_subscription(
            DispenserRequest, '/dispenser_requests',
            lambda msg: self.on_request(msg, dispenser=True), 10)
        self.create_subscription(
            IngestorRequest, '/ingestor_requests',
            lambda msg: self.on_request(msg, dispenser=False), 10)

        # 상태를 안 내면 RMF 가 이 워크셀을 없는 것으로 보고 요청조차 안 한다.
        self.create_timer(1.0, self.publish_states)

        served = sum(len(c.dispensers) + len(c.ingestors) for c in self.cells)
        self.get_logger().info(
            f'워크셀 {len(self.cells)}대, 맡은 자리 {served}곳을 RMF 에 이었습니다.')

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

        # 같은 요청이 여러 번 온다. RMF 는 답이 올 때까지 되풀이해 부른다.
        with cell.lock:
            if cell.busy:
                return
            cell.busy = True

        self.get_logger().info(
            f'[{cell.robot_id}] {msg.target_guid} 요청 받음 '
            f'({msg.request_guid})')
        self.answer(msg, dispenser, DispenserResult.ACKNOWLEDGED)

        cell.move(PICK_POSE, ACTION_SECONDS / 2)

        def finish():
            timer.cancel()
            cell.move(HOME_POSE, ACTION_SECONDS / 2)
            with cell.lock:
                cell.busy = False
            self.get_logger().info(f'[{cell.robot_id}] {msg.target_guid} 끝.')
            self.answer(msg, dispenser, DispenserResult.SUCCESS)

        timer = self.create_timer(ACTION_SECONDS, finish)

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
