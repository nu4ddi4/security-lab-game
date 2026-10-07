# Security Lab · 잔여 권한

Godot 기반 보안 조사 게임입니다. 사무실 장비와 NPC를 조사하고, 터미널·노트·메신저·보고를 활용해 사건을 해결합니다.

## 실행과 조작

Godot **4.7.2 stable**에서 `godot/project.godot`을 열고 **F5**로 실행합니다.

- PC: **WASD** 이동, **마우스** 시점 조작, **F** 상호작용.
- Android: 화면의 터치 컨트롤을 사용합니다.
- 장비 명령 안내: 터미널에서 `help`를 입력합니다.

## 개발

```sh
python scripts/prototype-test.py --godot /path/to/Godot-4.7.2 --suite rules
```

수정 영역에 맞춰 `rules`(사건·저장), `services`(진단·업데이트), `scene`(UI·입력·이동)을 선택합니다. 전체 빠른 검사는 `--suite all`로 실행합니다.

## 문서

- [게임 구조·현재 범위](docs/INVESTIGATION_PROTOTYPE.md)
- [개발 규칙](AGENTS.md) · [검사·빌드](docs/CI.md) · [버전 규칙](docs/VERSIONING.md)
- [조작키](docs/INPUT_REBINDING.md) · [로컬 진단](docs/NATIVE_DIAGNOSTICS.md) · [업데이트](docs/NATIVE_AUTO_UPDATE.md)
