# 설치 업데이트

Windows 설치형 조사 게임은 현재 제품·채널의 더 새 버전을 확인하고 **업데이트가 있습니다** 알림을 표시한다. 동의 전에는 설치 파일을 다운로드하지 않는다. 취소·나중에·창 닫기는 모두 현재 플레이를 유지한다.

동의 → 다운로드·크기/SHA-256 검증 → 조사 진행 저장 → 설치 helper 준비 확인 → 게임 종료 → Inno 설치 → 새 게임·저장 건강 확인 순서다. 저장이 실패하면 종료하지 않는다. 설치·시작·건강 확인 실패 시 기존 실행 파일·전체 설치 디렉터리·저장을 복구하고 기존 게임을 재실행한다.

| 경로 | 역할 |
| --- | --- |
| `godot/prototype/scripts/installer_updates.gd` | 현재 조사 저장·건강 확인·설정 연결 |
| `godot/scripts/update_manager.gd` · `update_policy.gd` | 사용자 동의, 제품·채널·버전·URL·해시 검증 |
| `godot/resources/native_update_helper.ps1` | 설치 트랜잭션·백업·복구 |
| `installer/SecurityLabBeta.iss` | 현재 베타 설치 프로그램 |
| `scripts/beta-installer-build.py` · `prototype-release.py` | 검증된 파일 패키징·명시적 게시 |

베타 제품은 `security-lab-beta`이며 `beta` 빌드는 `beta-channel-beta/update.json`, 정식 빌드는 `beta-channel-stable/update.json`을 확인한다. 이전 웹·Native 제품이나 다른 채널·이전 버전으로 전환하지 않는다. Android·포터블 Windows는 플랫폼에 맞는 새 베타 다운로드를 안내한다. Android 패키지 ID·서명을 유지한다.

빠른 정책·저장·건강 검사는 `python scripts/prototype-test.py --suite services`로 실행한다. 실제 HTTP 요청·동의 UI·helper 실행·Inno 설치와 실패 복구는 수동 플랫폼 검증에서 수행한다. 네트워크 fixture는 명시적으로 허용한 loopback 주소만 사용한다. 개발 중 매번 설치하지 않는다.
