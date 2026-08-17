#!/usr/bin/env python3
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--stage', required=True)
display = parser.add_mutually_exclusive_group()
display.add_argument('--headless', action='store_true')
display.add_argument('--gui', action='store_true')
args = parser.parse_args()

from isaacsim import SimulationApp

app = SimulationApp({'headless': not args.gui})

import omni.timeline
from isaacsim.core.utils.extensions import enable_extension
from isaacsim.core.utils.stage import open_stage

enable_extension('isaacsim.ros2.bridge')
open_stage(args.stage)
app.update()

import omni.graph.core as og
try:
    og.Controller.edit(
        {'graph_path': '/World/ROS2Clock', 'evaluator_name': 'execution'},
        {
            og.Controller.Keys.CREATE_NODES: [
                ('Tick', 'omni.graph.action.OnPlaybackTick'),
                ('SimTime', 'isaacsim.core.nodes.IsaacReadSimulationTime'),
                ('PublishClock', 'isaacsim.ros2.bridge.ROS2PublishClock'),
            ],
            og.Controller.Keys.CONNECT: [
                ('Tick.outputs:tick', 'PublishClock.inputs:execIn'),
                ('SimTime.outputs:simulationTime', 'PublishClock.inputs:timeStamp'),
            ],
        },
    )
except Exception as error:
    if 'already exists' not in str(error):
        raise
app.update()

timeline = omni.timeline.get_timeline_interface()
timeline.play()
try:
    while app.is_running():
        app.update()
finally:
    timeline.stop()
    app.close()
