# Security Lab · 퇴근.exe

사무실을 돌아다니며 컴퓨터를 고치고 동료와 대화하는 코미디 스테이지 게임입니다. 신입사원의 목표는 여섯 가지 업무를 끝내고 퇴근하기. 마지막에는 발판을 건너 컴퓨터 전원도 꺼야 합니다. 실패한 스테이지만 바로 재도전합니다.

## 실행과 조작

Godot **4.7.2 stable**에서 `godot/project.godot`을 열고 **F5**로 실행합니다.

- 이동: **WASD**, 마우스 시점, **F** 상호작용, **Space** 점프.
- 터미널: 명령 입력 후 **Enter**, **↑↓** 이력, **Tab** 자동완성, **Esc** 메뉴.
- Android: 왼쪽 스틱으로 이동하고 오른쪽 화면을 쓸어 시점을 바꿉니다. 상호작용·점프 버튼과 터미널 소프트웨어 키보드를 사용합니다.
- 장비 명령 안내: 터미널에서 `help`를 입력합니다.

## 개발

```sh
python scripts/prototype-test.py --godot /path/to/Godot-4.7.2 --suite rules
```

수정 영역에 맞춰 `rules`(사건·저장), `services`(진단·업데이트), `scene`(UI·입력·이동)을 선택합니다. 전체 빠른 검사는 `--suite all`로 실행합니다.

## 문서

- [스테이지·현재 구조](docs/TERMINAL_STAGES.md) · [이전 조사 모드](docs/INVESTIGATION_PROTOTYPE.md)
- [개발 규칙](AGENTS.md) · [검사·빌드](docs/CI.md) · [버전 규칙](docs/VERSIONING.md)
- [조작키](docs/INPUT_REBINDING.md) · [로컬 진단](docs/NATIVE_DIAGNOSTICS.md) · [업데이트](docs/NATIVE_AUTO_UPDATE.md)
