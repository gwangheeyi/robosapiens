#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RMF_WS="${RMF_WS:-$HOME/rmf_ws}"
RMF_API_URL="${RMF_API_URL:-http://127.0.0.1:8000}"
RMF_SERVER_URI="${RMF_SERVER_URI:-ws://127.0.0.1:8000/_internal}"
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
API_CONTAINER="${RMF_API_CONTAINER:-robosapiens-rmf-api}"
export ROS_DOMAIN_ID RMW_IMPLEMENTATION
if [[ "$RMW_IMPLEMENTATION" == "rmw_fastrtps_cpp" ]]; then
  FASTDDS_BUILTIN_TRANSPORTS="${FASTDDS_BUILTIN_TRANSPORTS:-UDPv4}"
  export FASTDDS_BUILTIN_TRANSPORTS
fi
STARTED_API=0
RMF_PID=""

cleanup() {
  if [[ -n "$RMF_PID" ]]; then
    kill "$RMF_PID" 2>/dev/null || true
    wait "$RMF_PID" 2>/dev/null || true
  fi
  if [[ "$STARTED_API" == "1" ]]; then
    docker stop "$API_CONTAINER" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

if [[ ! -f "$RMF_WS/install/setup.bash" ]]; then
  echo "Open-RMF workspace not found: $RMF_WS/install/setup.bash" >&2
  exit 1
fi

if ! curl --silent --fail "$RMF_API_URL/time" >/dev/null 2>&1; then
  if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon is not accessible. Add this user to the docker group or start rmf-web API manually." >&2
    exit 1
  fi
  docker rm -f "$API_CONTAINER" >/dev/null 2>&1 || true
  docker run --detach --rm \
    --name "$API_CONTAINER" \
    --network host \
    --ipc host \
    -e "ROS_DOMAIN_ID=$ROS_DOMAIN_ID" \
    -e "RMW_IMPLEMENTATION=$RMW_IMPLEMENTATION" \
    -e "FASTDDS_BUILTIN_TRANSPORTS=${FASTDDS_BUILTIN_TRANSPORTS:-DEFAULT}" \
    -e "RMF_SERVER_USE_SIM_TIME=true" \
    ghcr.io/open-rmf/rmf-web/api-server:jazzy
  STARTED_API=1
fi

for _ in $(seq 1 60); do
  if curl --silent --fail "$RMF_API_URL/time" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl --silent --fail "$RMF_API_URL/time" >/dev/null 2>&1; then
  echo "rmf-web API did not become ready at $RMF_API_URL" >&2
  exit 1
fi

set +u
source /opt/ros/jazzy/setup.bash
source "$RMF_WS/install/setup.bash"
set -u

ros2 launch "$ROOT_DIR/openrmf/launch/office_web.launch.xml" \
  "server_uri:=$RMF_SERVER_URI" &
RMF_PID=$!

ADMIN_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJzdHViIiwicHJlZmVycmVkX3VzZXJuYW1lIjoiYWRtaW4iLCJpYXQiOjE1MTYyMzkwMjIsImF1ZCI6InJtZl9hcGlfc2VydmVyIiwiaXNzIjoic3R1YiIsImV4cCI6MjA1MTIyMjQwMH0.zzX3zXp467ldkzmLVIadQ_AHr8M5uWVV43n4wEB0OhE"
for _ in $(seq 1 90); do
  if curl --silent --fail \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "$RMF_API_URL/building_map" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

cd "$ROOT_DIR/openrmf_app"
flutter pub get
flutter run -d linux \
  --dart-define="RMF_API_URL=$RMF_API_URL" \
  --dart-define="RMF_API_TOKEN=$ADMIN_TOKEN"
