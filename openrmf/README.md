# Open-RMF Office Flutter Console

This integration runs the stock Open-RMF office simulation, connects its
dispatcher and `tinyRobot` fleet adapter to the official `rmf-web` API server,
and renders that API in a dedicated Flutter desktop console.

한국어 실행 순서는
[`docs/OPENRMF_APP_RUN_GUIDE.md`](docs/OPENRMF_APP_RUN_GUIDE.md)를 참고합니다.

```text
rmf_demos_gz office
        |
        | ROS 2 + ws://127.0.0.1:8000/_internal
        v
rmf-web api-server
        |
        | GET /building_map, /fleets, /tasks
        v
openrmf_app (Flutter)
```

## Run everything

Prerequisites:

- Ubuntu 24.04, ROS 2 Jazzy and a built `~/rmf_ws`
- Docker access for the current user
- Flutter with Linux desktop support

```bash
cd /home/gyi/robosapiens
./openrmf/scripts/run_office_flutter.sh
```

The script starts the official
`ghcr.io/open-rmf/rmf-web/api-server:jazzy` container, launches the office
world with the API URI forwarded to both RMF components, waits for the building
map, and starts Flutter.

For separate terminals:

```bash
# Terminal 1: API and office simulation
./openrmf/scripts/start_backend.sh

# Terminal 2: Flutter
cd openrmf_app
flutter run -d linux --dart-define=RMF_API_URL=http://127.0.0.1:8000
```

The API documentation is available at <http://127.0.0.1:8000/docs> while the
backend is running. The Flutter client polls RMF state once per second, while
the RMF dispatcher and fleet adapter publish their state to the API server's
internal WebSocket endpoint.

The app defaults to rmf-web's documented development `admin` token. For a
secured deployment, pass the identity provider token explicitly:

```bash
flutter run -d linux \
  --dart-define=RMF_API_URL=https://rmf.example.com \
  --dart-define=RMF_API_TOKEN="$ACCESS_TOKEN"
```

## Configuration

| Variable | Default |
| --- | --- |
| `RMF_WS` | `$HOME/rmf_ws` |
| `RMF_API_URL` | `http://127.0.0.1:8000` |
| `RMF_SERVER_URI` | `ws://127.0.0.1:8000/_internal` |
| `ROS_DOMAIN_ID` | `0` |
| `RMW_IMPLEMENTATION` | 설치된 Fast DDS/CycloneDDS 구현 자동 선택 |
