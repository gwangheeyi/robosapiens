#!/usr/bin/env python3
"""project1-ver2 프로젝트의 학습 policy 실행기.

rmf_control_ui 가 맵 프로젝트에서 생성했다. 손으로 고치면 다음 저장 때
덮어써진다.

하는 일은 하나다 — **붙여 둔 policy 로 그 팔을 움직이고 끝나면 0 으로 끝난다.**

    /<네임스페이스>/joint_states                    관측(관절 위치)
    /<네임스페이스>/arm_controller/joint_trajectory 명령
    /<네임스페이스>/camera/image_raw                policy 가 이미지를 볼 때만

Gazebo 와 실물의 차이는 그 토픽 뒤에 무엇이 붙어 있느냐뿐이라, 같은 러너가
둘 다 움직인다.

**추론기가 없는 것은 오류가 아니다.** torch·lerobot 이 이 자리에 없으면 2 로
끝내고, 워크셀 노드가 시험 동작으로 대신한다. 그래야 추론기를 아직 안 깐
자리에서도 RMF 작업이 멈추지 않는다.

종료 코드
    0  추론 동작을 끝냈다
    2  추론기가 없거나 policy 를 못 읽었다
    3  관절 상태가 안 온다 (팔이 안 떠 있다)
    4  policy 압축이 이상하다
"""

import argparse
import json
import os
import sys
import time
import zipfile

# 관측을 몇 Hz 로 넣고 명령을 몇 Hz 로 낼지.
CONTROL_HZ = 10.0

# 첫 관절 상태를 이만큼 기다린다 [s]. 안 오면 팔이 없는 것이다.
OBSERVATION_TIMEOUT = 10.0

# 명령 하나가 목표에 닿을 시간 [s]. 너무 짧으면 컨트롤러가 따라오지 못한다.
COMMAND_HORIZON = 0.3

# 끝내고 집으로 돌아가는 데 주는 시간 [s].
HOME_SECONDS = 2.0


def log(message):
    print(f'[policy_runner] {message}', flush=True)


def unpack(archive, policy_id):
    """policy ZIP 을 캐시에 한 번만 푼다. 수백 MB 를 매번 풀 이유가 없다."""
    safe = ''.join(c if c.isalnum() or c in '-_' else '_' for c in policy_id)
    target = os.path.join(
        os.path.expanduser('~/.cache/robosapiens/policies'), safe)
    marker = os.path.join(target, 'config.json')
    if os.path.exists(marker):
        return target
    os.makedirs(target, exist_ok=True)
    try:
        with zipfile.ZipFile(archive) as bundle:
            for entry in bundle.namelist():
                # ZIP 안의 경로를 그대로 믿지 않는다.
                if entry.startswith('/') or '..' in entry.split('/'):
                    continue
                bundle.extract(entry, target)
    except (zipfile.BadZipFile, OSError) as error:
        log(f'policy 압축을 못 풀었습니다: {error}')
        sys.exit(4)
    if not os.path.exists(marker):
        log('config.json 이 없습니다. LeRobot policy 가 아닙니다.')
        sys.exit(4)
    return target


def load_policy(directory):
    """LeRobot policy 를 불러온다. 추론기가 없으면 2 로 끝낸다."""
    try:
        import torch
    except Exception as error:
        log(f'torch 가 없습니다: {error}')
        log('이 자리에는 추론기가 없습니다. 워크셀이 시험 동작으로 대신합니다.')
        sys.exit(2)
    loaders = []
    try:
        from lerobot.common.policies.factory import get_policy_class
        loaders.append(lambda: get_policy_class(
            json.load(open(os.path.join(directory, 'config.json')))
            .get('type', 'act')).from_pretrained(directory))
    except Exception:
        pass
    try:
        from lerobot.common.policies.act.modeling_act import ACTPolicy
        loaders.append(lambda: ACTPolicy.from_pretrained(directory))
    except Exception:
        pass
    if not loaders:
        log('lerobot 이 없습니다. 워크셀이 시험 동작으로 대신합니다.')
        sys.exit(2)
    last = None
    for loader in loaders:
        try:
            policy = loader()
            policy.eval()
            return torch, policy
        except Exception as error:
            last = error
    log(f'policy 를 못 불러왔습니다: {last}')
    sys.exit(2)


def image_features(directory):
    """policy 가 이미지를 요구하는가. 요구하면 그 키 이름들."""
    try:
        with open(os.path.join(directory, 'config.json')) as handle:
            config = json.load(handle)
    except Exception:
        return []
    features = config.get('input_features') or {}
    return [key for key in features if 'image' in key]


def to_array(numpy, message):
    """sensor_msgs/Image 를 HxWx3 배열로. cv_bridge 없이 직접 옮긴다."""
    data = numpy.frombuffer(message.data, dtype=numpy.uint8)
    frame = data.reshape(message.height, message.width, -1)
    if message.encoding == 'bgr8':
        frame = frame[:, :, ::-1]
    return frame[:, :, :3]


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument('--policy', required=True, help='policy ZIP 자리')
    parser.add_argument('--policy-id', required=True)
    parser.add_argument('--namespace', required=True)
    parser.add_argument('--model', default='')
    parser.add_argument('--seconds', type=float, default=6.0)
    args = parser.parse_args(argv[1:])

    if not os.path.exists(args.policy):
        log(f'학습 결과 파일이 없습니다: {args.policy}')
        log('앱의 `Policy 관리` 에서 다시 받으세요.')
        sys.exit(2)

    directory = unpack(args.policy, args.policy_id)
    torch, policy = load_policy(directory)
    images = image_features(directory)
    import numpy

    import rclpy
    import rclpy.node
    from sensor_msgs.msg import Image, JointState
    from trajectory_msgs.msg import JointTrajectory, JointTrajectoryPoint

    rclpy.init(args=argv)
    node = rclpy.node.Node('policy_runner')
    state = {'joints': None, 'names': None, 'frame': None}

    def on_joint_state(message):
        state['names'] = list(message.name)
        state['joints'] = list(message.position)

    def on_image(message):
        state['frame'] = to_array(numpy, message)

    node.create_subscription(
        JointState, f'/{args.namespace}/joint_states', on_joint_state, 10)
    if images:
        node.create_subscription(
            Image, f'/{args.namespace}/camera/image_raw', on_image, 1)
    command = node.create_publisher(
        JointTrajectory,
        f'/{args.namespace}/arm_controller/joint_trajectory', 10)

    # 팔이 무엇을 하고 있는지 알기 전에는 명령하지 않는다.
    deadline = time.monotonic() + OBSERVATION_TIMEOUT
    while state['joints'] is None and time.monotonic() < deadline:
        rclpy.spin_once(node, timeout_sec=0.1)
    if state['joints'] is None:
        log(f'/{args.namespace}/joint_states 가 안 옵니다. 팔이 떠 있습니까?')
        node.destroy_node()
        rclpy.shutdown()
        sys.exit(3)
    if images and state['frame'] is None:
        log('policy 가 이미지를 요구하는데 카메라 토픽이 안 옵니다: '
            f'/{args.namespace}/camera/image_raw')
        node.destroy_node()
        rclpy.shutdown()
        sys.exit(3)

    home = list(state['joints'])
    names = list(state['names'])
    log(f'[{args.policy_id}] 추론 시작 — 관절 {len(names)}개, '
        f'이미지 {len(images)}개, {args.seconds:.1f}초')

    period = 1.0 / CONTROL_HZ
    finish = time.monotonic() + args.seconds
    sent = 0
    while time.monotonic() < finish:
        rclpy.spin_once(node, timeout_sec=period)
        observation = {
            'observation.state': torch.tensor(
                [state['joints']], dtype=torch.float32),
        }
        for key in images:
            if state['frame'] is None:
                continue
            frame = numpy.ascontiguousarray(
                state['frame'].transpose(2, 0, 1))
            observation[key] = torch.tensor(
                frame[None], dtype=torch.float32) / 255.0
        try:
            with torch.no_grad():
                action = policy.select_action(observation)
        except Exception as error:
            log(f'추론이 실패했습니다: {error}')
            node.destroy_node()
            rclpy.shutdown()
            sys.exit(2)
        target = [float(value) for value in action.squeeze(0).tolist()]
        if len(target) < len(names):
            # 액션이 관절보다 적으면 앞에서부터 채우고 나머지는 그대로 둔다.
            target = target + list(state['joints'])[len(target):]
        message = JointTrajectory()
        message.joint_names = names[:len(target)]
        point = JointTrajectoryPoint()
        point.positions = target[:len(message.joint_names)]
        point.time_from_start.sec = int(COMMAND_HORIZON)
        point.time_from_start.nanosec = int((COMMAND_HORIZON % 1) * 1e9)
        message.points.append(point)
        command.publish(message)
        sent += 1

    # 끝내고 시작 자세로 돌아간다. 다음 요청이 늘 같은 자리에서 시작하도록.
    message = JointTrajectory()
    message.joint_names = names
    point = JointTrajectoryPoint()
    point.positions = home
    point.time_from_start.sec = int(HOME_SECONDS)
    message.points.append(point)
    command.publish(message)
    end = time.monotonic() + HOME_SECONDS
    while time.monotonic() < end:
        rclpy.spin_once(node, timeout_sec=0.1)

    log(f'[{args.policy_id}] 추론 동작을 끝냈습니다 (명령 {sent}회)')
    node.destroy_node()
    if rclpy.ok():
        rclpy.shutdown()
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
