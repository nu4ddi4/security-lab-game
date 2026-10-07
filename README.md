# Security Lab

보안 학습 게임과 Godot 조사 프로토타입.

## Godot 베타

`beta`는 **잔여 권한** 프로토타입의 사건·저장·대화 흐름에 검증한 `godot-port` 맵과 진단·업데이트 기능을 합친 테스트·안정화 브랜치입니다. Godot 4.7.2에서 `godot/project.godot`을 열고 F5로 실행합니다.

사무실 맵의 장비·NPC에서 조사하고 터미널·노트·보고로 사건을 진행합니다. 1~4일차 핵심 흐름과 5~7일차 기본 진행을 구현했습니다. 정식 결말은 후속 작업입니다. [실행·구조·다음 단계](docs/INVESTIGATION_PROTOTYPE.md).

[SecurityLab-beta-0.3.0](https://github.com/nu4ddi4/security-lab-game/releases/tag/SecurityLab-beta-0.3.0)에서 Windows EXE·ZIP·설치 파일과 Android APK를 받습니다. 설치형 Windows 업데이트는 알림에 동의한 뒤에만 다운로드·저장·종료·설치·재실행합니다. 설정에서 로컬 진단을 복사하고 지원 ZIP을 만들 수 있습니다.

개발 중인 상호작용·모바일·로딩 변경과 검증 범위는 [개선 기록](docs/BETA_UX_MOBILE_PLAN.md)을 참고하세요.

기존 Godot 학습 게임은 소스에서 `--legacy`로 실행합니다. 아래 릴리즈 안내는 기존 웹 버전입니다.

## 실행

1. [최신 릴리즈](https://github.com/nu4ddi4/security-lab-game/releases/latest)의 Windows EXE 또는 ZIP을 받습니다.
2. EXE를 실행합니다. ZIP은 압축을 풀고 안의 EXE를 실행합니다.
3. 게임을 하는 동안 실행창을 열어둡니다.

Windows 10/11 64비트용입니다. 게임 파일과 Python이 EXE에 포함되어 있어 소스코드·Python·Node.js를 따로 설치하지 않습니다. 진행은 브라우저와 접속 주소별로 저장됩니다. 다른 주소로 옮길 때는 진행 내보내기/가져오기를 사용하세요.

공식 플레이 환경은 **Windows 10/11 + 최신 Google Chrome Desktop + 키보드·마우스**입니다. 최소 1280×720, 기준 1920×1080입니다. 모바일·터치·Edge·Firefox·Safari/WebKit은 공식 지원하지 않습니다. 실행창은 Chrome을 직접 엽니다.

## 미션

| 미션 | 목표 |
| --- | --- |
| 튜토리얼 | 명령어와 조사 범위 확인 |
| 노출된 서비스 | 443 유지, 불필요한 8080 차단 |
| 약한 로그인 정책 | 흔한 값 차단과 시도 제한, 정상 로그인 확인 |
| 변조된 자료 | SHA-256 비교, 원본 복구, 재비교 |

포트와 로그인은 시뮬레이션입니다. SHA-256은 실제로 계산합니다. 다음 행동 안내, 힌트, 진행 백업·이동, 초기화, 방어 전후 비교를 지원합니다.

첫 실행은 2D 화면입니다. ‘3D 실습실’을 선택하면 WASD·마우스로 이동하고 **E로 현장 조사**, **F로 상세 도구**를 엽니다. 서버·관제 PC·자료 보관함에서 단서를 확보하고 설정 변경 후 해당 장비를 다시 확인합니다. 현장 조사로 시작한 미션은 터미널 조회만으로 재방문을 대신할 수 없습니다. 기존 2D 전용 진행과 완료 저장도 유지합니다. 처음 탐색할 때 짧은 E/F 안내를 표시합니다. HUD의 구역·방향·직선 거리와 상태판의 테두리는 다음 장비를 안내하고, 설정 변경 후에는 이전 관찰의 만료와 재확인 이유를 보여줍니다. [3D 조작](docs/3D_LAB.md) · [현장 미션 구조](docs/SPATIAL_MISSIONS.md).

## 개발

```sh
python run.py
```

검증: Windows에 최신 Google Chrome 설치 → `npm ci` → `npm run check`. Chrome 단일 Playwright 프로젝트이며 브라우저를 별도로 다운로드하지 않습니다.

3D 일시정지 화면에서 Native/Ultra/Quality/Balanced/Performance 화질을 선택합니다. 기본 Quality는 75%로 3D만 렌더링하고 HTML은 원래 해상도를 유지합니다. F3으로 성능 정보를 확인합니다. [런타임·CI 최적화](docs/CHROME_RUNTIME.md).

[구조](docs/PROJECT_REVIEW.md) · [계획](docs/PLAN.md) · [안정화 계획](docs/STABILIZATION_PLAN.md) · [다음 작업](docs/ROADMAP.md) · [검증](docs/VALIDATION.md) · [배포](docs/DEPLOYMENT.md)


v0.7.0은 회사형 실내 조명·재질과 실제 장비의 시각 피드백을 개선합니다.
SOC 화면, 네트워크 콘솔과 랙 표시등은 내장 미션 상태를 읽기 전용으로
표시합니다. 보이는 결과가 단서 기록이나 최종 검증을 대신하지 않으며
E 현장 조사 / F 상세 도구와 설정 후 재확인 흐름은 그대로입니다.
[제작·검증 구조](docs/EXPERIENCE_07.md).
