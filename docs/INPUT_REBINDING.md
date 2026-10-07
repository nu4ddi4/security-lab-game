# Windows Native 키 바인딩

`feature/input-rebinding`에서 개발합니다. 처음 `godot-port`의 `d9c573d`에서 시작했으며,
사용자의 Beta 통합 지시에 따라 작업을 `beta`의 `3ad57ab` 위로 옮겼습니다.
완료된 변경은 Beta에 병합하며 main/godot-port/다른 feature에는 커밋하지 않습니다.

조사 Beta: 휴대 단말 → 설정 → **조작키 변경…**.
기존 미션: 환경 설정 → 조작키 → **조작키 변경…**.
두 화면에서 같은 입력 정의와 편집 창을 사용합니다. Beta 0.4.0은 F 상호작용으로 통합하여 E 조사 항목을 표시하지 않고 9개 활성 액션만 편집합니다. 기존 미션과 저장 프로필은 10개 액션을 유지합니다.

## 정의와 동작

`godot/scripts/input_bindings.gd`의 `ACTIONS`가 액션 ID·기본 물리 키·표시 이름의 단일 기준입니다.
앞/뒤/좌/우, 달리기, 앉기, 점프, 조사, 상세 도구, 일시정지/조사 노트의 10개 액션을 지원합니다.
기본값은 WASD / Shift / Ctrl와 C / Space / E / F / Esc입니다.
조사 Beta의 고정 Tab 휴대 단말 단축키, 터미널 편집키, 마우스 look, 터치 설정은 유지합니다.

변경할 키 버튼 → 다음 물리 키 입력 → **조작키 적용하고 저장** 순서입니다.
기존 액션의 키들을 새 키 하나로 교체합니다. 기본값 복원 시 Ctrl/C의 두 기본 별칭도 복원됩니다.
필수 액션은 비우거나 삭제할 수 없고, 최대 두 키를 가진 저장 형식을 검증합니다.
다른 액션의 키를 지정하면 그 액션 이름을 보여주며 거부합니다. 기존 키를 자동으로 빼앗지 않습니다.
키를 서로 바꾸려면 임시로 비어 있는 키를 사용하는 단계가 필요합니다.

저장하기 전에는 draft만 변경됩니다. 닫기/X/Esc는 미저장 변경을 버립니다.
입력 대기 중 Esc는 키 후보이며 창을 닫지 않습니다. 취소는 별도의 **입력 대기 취소** 버튼으로 합니다.
중복/지원하지 않는 키/키 조합 입력은 대기를 유지합니다. 포커스를 잃으면 대기를 취소합니다.
auto-repeat 및 키 release는 새 바인딩으로 인식하지 않습니다.

편집 창이 살아 있는 동안 플레이어 이동·점프·조사·도구·pause·마우스/터치 look을 막습니다.
키를 누른 채 닫았으면 그 키를 놓을 때까지 입력을 차단하고 action state도 해제합니다.
기존 모바일 touch axes 및 touch/keyboard 혼합 입력을 유지합니다.
키 변경 후 HUD, onboarding, 조사 안내, 장비 placard 및 닫기 단축키 표시는 현재 InputMap으로 갱신합니다.

## 저장과 복구

일반 설정/저장/updater 설정 파일을 변경하지 않고 `user://input_bindings.json`에 저장합니다.

```json
{
  "schema": 1,
  "mode": "physical_keyboard",
  "actions": {
    "forward": [87], "back": [83], "left": [65], "right": [68],
    "sprint": [4194325], "crouch": [4194326, 67], "jump": [32],
    "inspect": [69], "tool": [70], "pause": [4194305]
  }
}
```

위 특수 키 숫자는 Godot `Key` 상수입니다. 실제 값은 소스 정의로 생성하며 키 이름 문자열을 저장하지 않습니다.
16KiB 제한과 schema/mode, 전체 액션 목록, 키 코드 타입·범위, 빈/중복 할당을 검증합니다.
손상/누락/잘못된 형식은 전체 기본값으로 복구합니다. 손상 원본은 시작 시 덮어쓰지 않습니다.
명시적인 저장은 `.tmp` 쓰기·flush·rename에 성공한 뒤 InputMap에 적용합니다.
쓰기 실패 시 기존 파일과 현재 입력을 유지하고 창에 오류를 표시합니다.
진행 파일/controls.cfg/채널 업데이트 설정에는 손대지 않습니다.
일반 QA는 별도 QA profile을 사용하고 기본 키로 실행하여 기존 검사를 안정적으로 유지합니다.

## 구현 및 검사

- `input_bindings.gd`: 정의, 검증, 파일 복구/저장, InputMap, 키 이름/안내 formatter.
- `input_rebinding.gd`: 두 실행 경로가 공유하는 Windows 편집 창과 capture lifecycle.
- `player.gd`, 두 `game.gd`: 입력 잠금과 하나의 InputMap 초기화.
- Native `settings.gd/ui.gd/device.gd`, Beta `ui.gd/input_controls.gd`: UI·안내와 혼합 입력 보존.
- `input_bindings_test.gd`: 기본·변경·저장/복구·복원·충돌·malformed·쓰기 실패 검사.
- `input_review.gd`: 실제 버튼/capture, Esc·repeat·충돌·키 조합·저장 실패·복원·이동·점프·pause·진행 저장 검사.
- `ci-godot-test.py`, `prototype-build.py`, export preset: 빠른 검사와 EXE-only 검사에 포함.

```powershell
python scripts/ci-godot-test.py --godot <Godot-4.7.2-console.exe>
godot --headless --path godot -- --prototype-smoke --prototype-dummy --prototype-input-review
godot --headless --path godot -- --qa-input
python scripts/prototype-build.py --godot <Godot-4.7.2-console.exe> --rendered-check
```

Windows GUI 검사는 headless 없이 위 입력 review 플래그를 실행하고 `--input-output=<폴더>`를 추가합니다.
`input-rebinding.png`와 `input-review.json`을 기록합니다.
headless에서는 Window signal로 capture를 검증하고 Windows GUI에서는 실제 Window ID로 입력을 전달합니다.

## 제한

Windows 키보드 물리 키만 편집합니다. 마우스 버튼/look, 게임패드, 키 조합, IME 문자/소프트웨어 키보드 재바인딩은 지원하지 않습니다.
Tab은 휴대 단말 고정키이며 Windows/Meta 등의 OS 제어키는 지정할 수 없습니다.
일반 UI 편집/터미널 단축키는 게임 액션 바인딩과 별개입니다.
Android UI에는 Windows 전용 키 편집 버튼을 추가하지 않으며 기존 터치와 하드웨어 키보드 입력을 보존합니다.
공통 자료 저장 위치를 사용하므로 조사 Beta와 기존 미션은 같은 PC 키 profile을 공유합니다.
