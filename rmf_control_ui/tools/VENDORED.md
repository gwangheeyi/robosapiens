# 가져온 코드 (vendored)

이 디렉터리는 **Trihouse 저장소의 `trihouse_omx/` 를 통째로 복사한 것**입니다.
여기서 고치면 원본과 갈라집니다.

    출처   https://github.com/dadaru7887/Trihouse
    가지   usang/omx
    경로   trihouse_omx/
    시점   2726b88f7d83b28bf0d93c79b65a90c9ac8fa98c
           (fix(omx): job_loop.py 정책 로딩을 HuggingFace 네트워크 의존 없이 오프라인으로)
    가져온 날  2026-08-21

`.py` 15개와 `.gitignore` 를 그대로 가져왔습니다. 원본과 **바이트까지
같습니다** (`diff -r` 로 확인).

## 돌리는 법

`lerobot` 이 필요합니다. 시스템 python 에는 없고 `~/venv/il` 에 있습니다.

    ~/venv/il/bin/python deliver.py --help

## 두 파일은 이 자리에서 import 가 안 됩니다

`job_loop.py` 와 `stream_wrist_camera.py` 는 **Trihouse 저장소의 다른 패키지를
부릅니다.** 둘 다 `parents[1]` — 자기 위 디렉터리 — 를 저장소 루트로 보고
`sys.path` 에 넣습니다.

| 파일 | 부르는 것 | 원본에서 |
|---|---|---|
| `job_loop.py` | `control_tower.gateway.fms_client` · `control_tower.process_lifecycle` | `Trihouse/control_tower/` |
| `stream_wrist_camera.py` | `vision_system.stream_hub.ingress` | `Trihouse/vision_system/` |

여기서는 `parents[1]` 이 `rmf_control_ui/` 라 그 둘이 없습니다. **코드 잘못이
아닙니다** — 원본 자리에서는 둘 다 정상 import 됩니다(확인함). 나머지 13개는
이 자리에서도 그대로 돕니다.

쓰려면 `control_tower/` · `vision_system/` 도 가져오거나, `PYTHONPATH` 로
Trihouse 저장소를 가리켜야 합니다.

## 이름이 바뀐 적이 있습니다

전에 `deliver.py` 를 `delivery.py` 로 이름을 바꿔 두었고, 그 사본 436행에
`s` 한 글자가 들어가 있었습니다. 모듈 최상위라 import 하는 순간 `NameError` 가
나는 상태였습니다. 지금은 원본 이름 `deliver.py` 로 돌아왔고 그 글자도
없습니다.

**원본을 고치고 다시 가져오는 것**이 낫습니다. 손으로 복사하면 갈라집니다.

## 다시 가져오기

    git clone --branch usang/omx --depth 1 \
        https://github.com/dadaru7887/Trihouse.git /tmp/trihouse
    cp /tmp/trihouse/trihouse_omx/*.py        rmf_control_ui/tools/
    cp /tmp/trihouse/trihouse_omx/.gitignore  rmf_control_ui/tools/
