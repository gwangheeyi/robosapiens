#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/openrmf/scripts/validate_layout.sh"
validate_robosapiens_layout "$ROOT_DIR"
ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
if [[ -z "${RMW_IMPLEMENTATION:-}" ]]; then
  if [[ -f /opt/ros/jazzy/lib/librmw_fastrtps_cpp.so ]]; then
    RMW_IMPLEMENTATION=rmw_fastrtps_cpp
  elif [[ -f /opt/ros/jazzy/lib/librmw_cyclonedds_cpp.so ]]; then
    RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
  else
    echo "No supported ROS 2 RMW implementation was found." >&2
    exit 1
  fi
fi
export ROS_DOMAIN_ID RMW_IMPLEMENTATION
if [[ "$RMW_IMPLEMENTATION" == "rmw_fastrtps_cpp" ]]; then
  FASTDDS_BUILTIN_TRANSPORTS="${FASTDDS_BUILTIN_TRANSPORTS:-UDPv4}"
  export FASTDDS_BUILTIN_TRANSPORTS
fi

docker run --detach --rm \
  --name robosapiens-rmf-api \
  --network host \
  --ipc host \
  -e "ROS_DOMAIN_ID=$ROS_DOMAIN_ID" \
  -e "RMW_IMPLEMENTATION=$RMW_IMPLEMENTATION" \
  -e "FASTDDS_BUILTIN_TRANSPORTS=${FASTDDS_BUILTIN_TRANSPORTS:-DEFAULT}" \
  -e "RMF_SERVER_USE_SIM_TIME=true" \
  ghcr.io/open-rmf/rmf-web/api-server:jazzy

set +u
source /opt/ros/jazzy/setup.bash
source "$RMF_WS/install/setup.bash"
set -u

exec ros2 launch "$ROOT_DIR/openrmf/launch/office_web.launch.xml" \
  server_uri:=ws://127.0.0.1:8000/_internal
