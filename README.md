# Security Lab · 잔여 권한

Godot 기반 보안 조사 게임. 사무실 장비·NPC를 조사하고 터미널·노트·메신저·보고로 사건을 진행합니다. 1~4일차 핵심 흐름과 5~7일차 기본 진행을 구현했으며 정식 결말은 후속 작업입니다.

Godot **4.7.2 stable**에서 `godot/project.godot`을 열고 F5로 실행합니다. PC는 WASD·마우스·F 상호작용, Android는 터치가 기본입니다. 창 비율에 맞춰 UI가 조정되며, 명령 안내는 터미널에서 `help`를 입력하면 나옵니다.

현재 목표는 **0.8.0**, 베타 빌드 표기는 **0.8.0-beta.1**입니다. [기존 베타 다운로드](https://github.com/nu4ddi4/security-lab-game/releases/tag/SecurityLab-beta-0.4.0)는 표시 이름만 맞춘 0.4.0 파일입니다. 새 파일이 배포된 것은 아닙니다. Windows 설치형 업데이트는 사용자 동의 후에만 다운로드·설치합니다.

## 개발

```sh
python scripts/prototype-test.py --godot /path/to/Godot-4.7.2 --suite rules
```

수정 영역에 맞춰 `rules`(사건·저장), `services`(진단·업데이트), `scene`(UI·입력·이동)을 선택합니다. 베타 통합 CI는 빠른 전체 검사를 실행하고, Windows·Android 패키지 검사는 필요할 때 수동 실행합니다. 웹 서버·Chrome·npm 설치는 필요하지 않습니다.

- [게임 구조·현재 범위](docs/INVESTIGATION_PROTOTYPE.md)
- [개발 규칙](AGENTS.md) · [검사·빌드](docs/CI.md) · [버전 규칙](docs/VERSIONING.md)
- [조작키](docs/INPUT_REBINDING.md) · [로컬 진단](docs/NATIVE_DIAGNOSTICS.md) · [업데이트](docs/NATIVE_AUTO_UPDATE.md)

현재 조사 게임과 공용 사무실·이동·문·입력·진단·업데이트 코드를 유지합니다. 구 웹 게임과 `--legacy` 학습 모드는 정리했으며 이전 소스·릴리스는 Git 기록에 남아 있습니다. 기존 조사 저장 경로·Android 패키지 ID는 유지합니다.
