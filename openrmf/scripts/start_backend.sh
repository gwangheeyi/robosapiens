#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RMF_WS="${RMF_WS:-$HOME/rmf_ws}"
ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"

docker run --detach --rm \
  --name robosapiens-rmf-api \
  --network host \
  -e "ROS_DOMAIN_ID=$ROS_DOMAIN_ID" \
  -e "RMW_IMPLEMENTATION=$RMW_IMPLEMENTATION" \
  -e "RMF_SERVER_USE_SIM_TIME=true" \
  ghcr.io/open-rmf/rmf-web/api-server:jazzy

set +u
source /opt/ros/jazzy/setup.bash
source "$RMF_WS/install/setup.bash"
set -u

exec ros2 launch "$ROOT_DIR/openrmf/launch/office_web.launch.xml" \
  server_uri:=ws://127.0.0.1:8000/_internal
