# Native 로컬 진단 / 지원 패키지

`feature/native-diagnostics`는 `godot-port`의 `d9c573d`에서 시작했습니다.
Windows Native에서 환경 설정 → **진단 정보 복사** 또는 **지원 패키지 만들기**를 사용합니다.
기본 출력은 `user://diagnostics/packages`이며, UI에 `%USERPROFILE%`로 익명화한 생성 위치를 표시합니다.
**생성 폴더 열기**로 실제 폴더를 열거나 **다른 폴더에 지원 패키지 저장…**으로 쓰기 가능한 로컬 폴더를 선택할 수 있습니다.
사용자가 실행했을 때만 수집하며 네트워크 업로드, 원격 telemetry, crash server는 없습니다.

## 파일과 데이터

| 파일 | 역할 |
| --- | --- |
| `godot/scripts/diagnostics.gd` | 고정된 앱 소유 파일의 제한된 읽기, runtime snapshot, 저장 검증, ZIP, 세션 종료 표시 |
| `godot/scripts/diagnostics_serializer.gd` | 필드 allowlist, 문자열 익명화, 보수적인 로그 투영, JSON 직렬화 |
| `godot/scripts/settings.gd` | 복사·생성·대상 폴더 선택·결과 및 오류 표시 |
| `godot/resources/build_info.json` | 개발 기본 version/channel, 소스 실행 commit은 `unknown` |
| `scripts/godot-build.ps1` | export 직전에 정확한 Git HEAD를 내장하고 원본 metadata를 항상 복원; 기존 version/channel 및 updater 추가 필드는 유지 |

수집: 앱 version/commit/channel, Godot 버전, OS 버전, CPU 모델/논리 코어 수,
GPU 모델/vendor/API, renderer/driver, 창 크기·창 모드, 그래픽 preset·MSAA·render scale,
허용된 현재 설정, 현재 미션 ID·단계·검증 여부, 동작 상태, anchor/collider/door/device 수,
최근 프레임 draw calls/triangles/FPS, 제한된 최근 로그 요약, 저장 검증, 이전 세션 종료 표시.
프레임 수치는 수집 시점의 값이며 벤치마크가 아닙니다. Graphics driver의 느린 OS 조회는 하지 않습니다.

제외: 계정/컴퓨터/도메인 이름, machine ID, IP/MAC, 인증 정보, 명령행,
환경 변수 덤프, 저장 원문·답안·파일 내용, 임의 사용자 파일, crash dump, 자유 형식 로그 문장.
하드웨어 문자열에도 profile 경로, 이름, 이메일, IP/MAC, credential 형태, network 위치 필터를 적용합니다.
USERNAME/USERDOMAIN/COMPUTERNAME/USERPROFILE은 필터를 위한 메모리상의 비교값으로만 읽으며 출력하지 않습니다.
다른 개인 경로는 `[path redacted]`, 사용자 루트는 `%USERPROFILE%`로 처리합니다.
모든 ZIP 경로는 고정된 상대 경로이며 개인 원본 파일을 그대로 압축하지 않습니다.

## ZIP 구조

파일명은 로컬 시각 `SecurityLab-Diagnostics-YYYYMMDD-HHMMSS.zip`입니다.
같은 시각에 생성하면 `-01` 같은 suffix를 붙여 기존 ZIP을 유지합니다. JSON 시각은 UTC입니다.

```text
README.txt
diagnostics.json
build_info.json
save_validation.json
logs/
  recent.json
updater.json
session.json
```

저장은 임시 `.partial` ZIP → 모든 쓰기/close 성공 → 최종 rename 순서입니다.
열기·쓰기·종료·rename 실패 시 불완전 ZIP을 제거하고 UI에 실패 원인과 다른 폴더 선택 안내를 표시합니다.
진단 실패는 진행 저장이나 종료를 차단하지 않습니다.

저장 검증은 `progress.json`과 `progress.backup.json`만 최대 128KiB로 읽고,
독립된 `LabSave`/`LabMissions`에 decode합니다. 원본과 현재 game state/error_message를 변경하지 않습니다.
결과는 `valid`, `invalid`, `missing`, `unreadable`, `oversize`, `unsafe_path`뿐입니다.

## 로그, updater, 비정상 종료

엔진 소유 `user://logs/godot*.log` 중 최근 3개, 각각 마지막 64KiB만 읽습니다.
로그 이름은 고정된 숫자/날짜 형태로 제한하고 일반 사용자 파일을 탐색하지 않습니다.
free-form 문장은 **redaction 후에도 포함하지 않습니다**. 오류/경고 수, crash marker,
오류 종류와 허용된 `res://scripts/*.gd` 소스/행, 고정 `NATIVE_READY` 숫자·renderer만 남깁니다.
파일이 없거나 읽을 수 없으면 상태를 남기고 나머지 패키지를 생성합니다.

이 기준선에는 updater가 아직 없습니다. 향후 `game.updater`의 상태·enabled·build만 읽을 수 있으며,
기존 updater의 32자리 hex stage 폴더 중 최근 `result.json`을 읽어 `installed`, `rolled_back`,
`recovery_required`, `cancelled`, `verifying_startup`만 남깁니다.
URL/token/PID/backup 경로/error 문장/transaction/설치 프로그램은 포함하지 않습니다.
updater 메서드를 호출하거나 상태를 바꾸지 않습니다.

`user://diagnostics/session.json`에는 개인 식별자가 없는 시작 UTC·build·ready·clean_exit를 기록합니다.
앱 준비 전 marker를 만들고 정상 tree 종료 시 clean_exit를 기록합니다.
지난 실행의 clean_exit가 false면 **비정상 종료 의심**으로 표시하며 crash로 단정하지 않습니다.
강제 종료·정전·동시 실행도 같은 표시를 낼 수 있습니다. Windows Event Log/dump는 수집하지 않습니다.
QA는 `user://qa` 하위 marker/save/log/updater fixture만 사용합니다.
입력 및 출력 경로의 symlink/junction/reparse ancestor와 UNC 경로는 거부합니다.

## 검사

```powershell
python scripts/ci-godot-test.py --godot <Godot-4.7.2-console.exe>
./scripts/godot-diagnostics-windows-test.ps1 -Godot <Godot-4.7.2-console.exe>
python -m unittest discover -s tests/ci
./scripts/godot-build.ps1 -Godot <Godot-4.7.2-console.exe>
./godot/builds/Windows/SecurityLab.exe --headless -- --qa-diagnostics
```

`diagnostics_test.gd`는 redaction·프로필 익명화·JSON·고정 ZIP 구조·실제 저장 검증·누락/손상/대용량 파일·
선택적 updater·정상/비정상 세션·동일 시각 파일 충돌을 검사합니다.
Windows harness는 새 fixture 폴더에만 쓰기 거부 ACL과 junction을 설정하고 반드시 복원/정리합니다.
빠른 CI는 작은 임시 프로젝트에서 같은 검사와 기존 Native 452 assertions를 실행합니다.
Windows CI는 내보낸 EXE에서 설정 버튼, 실제 ZIP, 내장 commit, 저장 상태 보존까지 확인합니다.

화면/클립보드 확인은 Windows에서 `SecurityLab.exe -- --qa-diagnostics --qa-output=<폴더>`로 실행합니다.
설정 창 PNG, 복사 결과, 생성 ZIP, `review.json`을 남깁니다. `--qa-ux`는 기존 네 미션 흐름 검사입니다.

## 한계

- 전체 crash dump, 원본 stack/error 문장과 OS Event Log를 제공하지 않아 원인 분석에 추가 설명이 필요할 수 있습니다.
- 이전 종료 표시는 추정이며 동시 실행을 식별하지 않습니다.
- 개인정보는 고정 allowlist와 보수적인 로그 요약으로 제한합니다. 공유 전에 패키지를 확인하세요.
- 파일이 없는 환경, headless renderer, platform API 미지원 정보는 missing/unavailable로 기록합니다.
- 실제 updater와의 함께 설치한 통합 검사는 updater 브랜치가 병합된 뒤 필요합니다. 현재 선택적 연동은 fixture로 검증합니다.
- 정상 사용자 권한의 로컬 지원 도구이며 동일 사용자 권한을 가진 악성 프로세스의 파일 변경 경쟁을 방어하는 sandbox는 아닙니다.
