# 잔여 권한 · Godot 프로토타입

브랜치: `codex/godot-investigation-prototype` · 기반: `godot-port`의 `d2c27a4`.

업로드된 `SECURITY_LAB_WEB_PROTOTYPE_PLAN.md`의 최신 본문과 P1~P22를 Godot에 적용합니다. 웹 UI 대신 더미 3D 환경을 사용하고, 사건 규칙과 콘텐츠는 장면에서 분리합니다.

## 실행

Godot **4.7.2 stable**에서 `godot/project.godot`을 열고 F5를 누릅니다. 기본 진입은 조사 프로토타입입니다.

Windows 테스트 빌드는 `Investigation prototype Windows`의 Actions 아티팩트로 제공합니다. `SecurityLab-Prototype-0.1.0-커밋-Windows-x64.exe`만 실행하면 됩니다. 더미 환경·사건 자료·한국어 폰트를 EXE에 포함하며 기존 맵·웹·가이드는 포함하지 않습니다. 이 빌드는 OpenGL 호환 렌더러를 사용합니다.

배포는 [SecurityLab-proto-0.1.0](https://github.com/nu4ddi4/security-lab-game/releases/tag/SecurityLab-proto-0.1.0)입니다. 제목·태그·EXE·ZIP은 `SecurityLab-proto-X.Y.Z` 형식을 사용합니다. Pre-release로 게시하고 정식 Latest를 바꾸지 않습니다. 검증된 Windows 빌드를 재사용하고 EXE·EXE만 담은 ZIP·체크섬을 제공합니다. 수정 배포는 `0.1.1`, 다음 기능 배포는 `0.2.0`으로 올립니다.

이 브랜치의 `.github/workflows/godot-prototype.yml`을 변경하면 빌드를 실행합니다. 일반 개발 push에서는 빠른 검사만 유지합니다. 같은 커밋은 Actions에서 재실행할 수 있습니다. 로컬 Windows 빌드 명령은 `python scripts/prototype-build.py --godot "Godot 실행 파일 경로"`입니다.

- WASD·마우스: 이동·시점, Shift: 달리기, C: 앉기, Space: 점프.
- E: 외관 확인. 원본 기록을 확보하지 않습니다.
- F: 선택한 현장 장비 또는 NPC의 도구. 열린 동안 이동을 멈춥니다.
- Tab/Esc: 휴대 단말. 터미널의 `help`로 현재 장비에서 가능한 명령을 확인합니다.
- 업무 탭: 오늘의 운영 확인, 업무 종료, 진행 내보내기·가져오기.

터미널의 장비 선택은 더미 환경의 대체 조사 경로입니다. 현장 도구와 같은 장비·권한 검사를 거칩니다. 실행 중지와 업무 종료에는 확인 창이 있습니다.

기존 학습 게임은 다음처럼 엽니다.

```powershell
godot --path godot -- --legacy
```

## 구현 범위

| 단계 | 구현한 흐름 | 상태 |
| --- | --- | --- |
| 1. 기반 | 단일 JSON 콘텐츠, 순수 사건 엔진, 고정 명령, 검증된 저장 | 완료 |
| 2. 1~2일차 | 기준 확인·인계 → 야간 실제 실행 → 백업 복구·재검증, 조기 보고·중지 | 완료 |
| 3. 3~4일차 | 조건부 검색 장애, 원본 확인·색인 복구, 근거를 직접 고르는 발생 보고 | 완료 |
| 4. 더미 플레이 | 3개 구역, 장비 6개, NPC 4명, 터미널·노트·메신저·보고·업무 | 완료 |
| 5. 5~7일차 | 운영 확인, 상태별 후속 연락, 승인 후 감사 원본 조회, 종료 확인 | 기본 진행 |
| 6. 본편 | 상세 경위 대조, 최종 행위자 보고, T-19 통제·반출 결과, 정식 결말 | 다음 작업 |
| 7. 실제 환경 | 더미를 실제 맵·장비·NPC로 교체, Windows 플레이 확인·배포 | 이후 |

2일차에도 범위·접근·수집 근거가 갖춰지면 발생 보고를 승인합니다. 보고 전 실행 중지도 가능하며, 스냅샷은 선택 사항입니다. 중지는 재실행을 막지만 기존 장애를 복구하지 않습니다. 색인 복구는 수집 작업을 중지하지 않습니다. 날짜만으로 예방한 장애를 다시 만들지 않습니다.

보고 승인 이후 감사 권한은 날짜가 바뀌어도 유지됩니다. 계정 담당자, 실제 접근, 내부 수집, 외부 반출은 구분합니다. 열람하지 않은 원본은 노트·보고 선택지에 나타나지 않습니다. 미확인 수집량도 자동 표시하지 않습니다.

7일차 종료는 프로토타입 상태를 닫는 기능입니다. 정식 행위자 판정·최종 반출 결과·결말 점수는 계산하지 않습니다.

## 구성과 저장

| 경로 | 역할 |
| --- | --- |
| `godot/prototype/content/*.json` | 사건·장비·원본·명령·질문 조건·보고 규칙·한국어 문구의 공통 원본 |
| `prototype/scripts/engine.gd` | `create_state()` · `parse()` · `step()` · `project()`; Node·파일·시계에 의존하지 않는 진행 규칙 |
| `prototype/scripts/save_codec.gd` | 버전·ID·기록 참조·날짜 이력 검증, JSON 변환 |
| `prototype/scripts/store.gd` | 파일 저장·백업·보존·가져오기 |
| `prototype/scripts/game.gd` · `ui.gd` · `target.gd` | 더미 환경, UI, 논리 장비 ID 연결 |
| `prototype/tests/scenarios.json` | 엔진 교체 시 재사용할 입력·기대 결과 시나리오 |

기존 `LabPlayer`만 이동에 재사용합니다. 기존 `LabMissions`와 학습 저장에는 의존하지 않습니다. 장비 ID가 같으면 실제 맵을 붙일 때 사건 엔진을 바꿀 필요가 없습니다. 다른 런타임은 같은 JSON·논리 ID·시나리오를 사용할 수 있습니다.

저장은 `user://investigation/save.json`이며 기존 `user://progress.json`과 분리됩니다. Windows 기본 위치는 `%APPDATA%/Godot/app_userdata/Security Lab · Native/investigation/`입니다. 최신 이전 저장은 `save.backup.json`에 남깁니다. 손상·미지원 저장은 자동 초기화하지 않습니다. 새 조사나 가져오기로 교체하기 전에 원본을 보존하고, 보존에 실패하면 교체를 중단합니다. 진행 JSON은 256KiB 이하여야 합니다.

## 검증

```powershell
python scripts/prototype-test.py --godot "C:/path/to/Godot_v4.7.2-stable_win64_console.exe"
```

새 시나리오 8개와 더미 장면의 이동·실제 장비 레이캐스트·UI 정지·저장 검사를 실행합니다. 매 시나리오 전이에서 입력 상태 불변성과 저장 복원을 확인합니다. Windows Native CI에도 같은 검사를 연결했습니다.

Windows 프로토타입 0.1.0 빌드 `1339e19`에서 시나리오 8개·433개 검증과 더미 장면 검사가 통과했습니다. EXE만 있는 폴더에서도 headless 실행·상호작용·이동·저장 검사를 두 번 통과했습니다. 실제 화면·마우스 조작의 사용성은 직접 플레이로 확인합니다.

프로토타입 전용 빌드는 임시 프로젝트에서 규칙·더미 장면을 검사합니다. 내보내기 후 임시 소스를 삭제하고 EXE만 별도 폴더로 복사해 검증합니다.

## 다음 작업 순서

1. 더미 환경에서 1~4일차를 직접 플레이해 명령 발견·노트 대조·보고 작성의 사용성을 조정합니다.
2. 5~6일차 질문과 감사 원본 대조를 확장하고, 증거 조건에 따른 최종 행위자 보고를 추가합니다.
3. T-19와 잔여 경로 통제, 실제 전달 결과, 7일차 정식 결말을 구현합니다.
4. Windows에서 프로토타입 EXE를 확인한 뒤 실제 맵과 연출을 연결합니다.
