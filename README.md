# Security Lab · 퇴근.exe

터미널 명령으로 회사 컴퓨터 6대를 고치는 코미디 스테이지 게임입니다. 첫 두 스테이지는 연습용이고, 3스테이지부터 잘못 입력하면 게임 속 PC가 폭발합니다. 실패한 스테이지만 바로 재도전합니다.

## 실행과 조작

Godot **4.7.2 stable**에서 `godot/project.godot`을 열고 **F5**로 실행합니다.

- PC: 명령 입력 후 **Enter**, **↑↓** 이력, **Tab** 자동완성, **Esc** 메뉴.
- Android: 터미널 입력창과 소프트웨어 키보드를 사용합니다.
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
