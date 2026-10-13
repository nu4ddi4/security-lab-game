# 설치 업데이트

Windows 설치형 조사 게임은 현재 제품·채널의 더 새 버전을 확인하고 **업데이트가 있습니다** 알림을 표시한다. 동의 전에는 설치 파일을 다운로드하지 않는다. 취소·나중에·창 닫기는 모두 현재 플레이를 유지한다.

동의 → 다운로드·크기/SHA-256 검증 → 조사 진행 저장 → 설치 helper 준비 확인 → 게임 종료 → Inno 설치 → 새 게임·저장 건강 확인 순서다. 저장이 실패하면 종료하지 않는다. 설치·시작·건강 확인 실패 시 기존 실행 파일·전체 설치 디렉터리·저장을 복구하고 기존 게임을 재실행한다.

| 경로 | 역할 |
| --- | --- |
| `godot/prototype/scripts/installer_updates.gd` | 현재 조사 저장·건강 확인·설정 연결 |
| `godot/scripts/update_manager.gd` · `update_policy.gd` | 사용자 동의, 제품·채널·버전·URL·해시 검증 |
| `godot/resources/native_update_helper.ps1` | 설치 트랜잭션·백업·복구 |
| `godot/prototype/scripts/content_bootstrap.gd` · `prototype/bootstrap.tscn` | 내보낸 빌드의 시작 장면. 동의 후 받은 게임 데이터 팩을 적용·확인·복구 |
| `scripts/content_pack.py` | 팩을 쓸 수 있는 실행 파일을 가르는 호환 키와 팩 내보내기 설정 |
| `installer/SecurityLabBeta.iss` | 현재 베타 설치 프로그램 |
| `scripts/beta-installer-build.py` · `prototype-release.py` | 검증된 파일 패키징·명시적 게시 |

베타 제품은 `security-lab-beta`이다. 모든 빌드는 `beta-channel-stable/update.json`을 확인하고, **Beta 업데이트 미리보기**(설정 › 일반)가 켜져 있으면 `beta-channel-beta/update.json`도 확인해 더 새 버전을 제안한다. beta 빌드는 미리보기가 기본으로 켜져 있어 beta 커밋마다 업데이트를 받고, 정식 빌드는 직접 켠 뒤에만 받는다. 선택은 `controls.cfg`에 저장한다. 두 채널 중 한쪽이 응답하지 않아도 다른 쪽의 업데이트는 제안한다. 정식 승격본이 더 새 버전이면 beta 사용자도 정식으로 돌아온다. 미리보기를 끄면 더 새 정식 버전만 받는다. 이전 웹·Native 제품이나 dev 채널·이전 버전으로는 전환하지 않는다. stable↔beta 전환은 같은 설치 폴더에 대상 채널 설치 프로그램을 설치하고, 건강 확인 후 이전 채널의 제거 항목을 지운다. 실패하면 두 채널의 제거 항목까지 복구한다. Android·포터블 Windows는 플랫폼에 맞는 새 베타 다운로드를 안내한다. Android 패키지 ID·서명을 유지한다.

확인에 실패하거나 "나중에"를 눌러도 설정의 "업데이트 확인"으로 다시 확인할 수 있다. 설치 준비 신호는 최대 30초 기다린다.

## 게임 데이터 팩

모든 릴리스는 약 0.5MB의 `SecurityLabContent.pck`(스크립트·장면·사건 데이터, 큰 3D 에셋·폰트 제외)를 함께 게시한다. `update.json`의 `compat`이 설치된 실행 파일의 `build_info.json`과 같으면 업데이트는 설치 프로그램(약 110MB) 대신 이 팩만 받는다. 동의 → 다운로드·크기/SHA-256 검증 → 진행 저장 → `user://content/pending.*` 기록 → 게임 재시작 순서이며 도우미·설치 프로그램은 쓰지 않는다.

- **호환 키**(`compat`): Godot 버전, 프로젝트 설정, 내보내기 옵션, `class_name` 스크립트 목록, 큰 에셋의 해시. 새 `class_name`이나 큰 에셋·엔진 설정이 바뀌면 키가 달라져 자동으로 전체 설치 프로그램으로 돌아간다. 함수·장면·콘텐츠 수정만으로는 달라지지 않는다.
- **적용**: 시작 장면이 `pending` 팩을 검증(키·버전·SHA-256)해 `active.pck`로 바꾸고 이전 팩은 `previous.pck`로 남긴다. 새 팩은 5초 동안 정상 실행되거나 정상 종료해야 확인된다. 확인 전에 끝난 팩은 다음 시작에서 이전 팩으로 되돌리고 `rejected.json`에 기록해 같은 팩을 다시 제안하지 않는다(그때는 전체 설치 프로그램을 제안).
- **새 실행 파일**: 설치 프로그램으로 설치한 실행 파일이 팩보다 새롭거나 키가 다르면 오래된 팩은 지운다. 도우미는 `installed`(디스크의 실행 파일)와 `current`(실행 중인 게임)를 따로 받아, 팩 때문에 게임이 더 새로워도 설치 폴더 검증은 실행 파일 기준으로 한다.
- **한계**: 팩은 설치된 Windows 빌드용이다. 이 기능이 없던 이전 빌드(`compat` 없음)는 한 번 설치 프로그램으로 업데이트해야 한다. 포터블 실행 파일은 자동 업데이트를 하지 않으므로 팩을 받지 않는다.

빠른 정책·저장·건강 검사는 `python scripts/prototype-test.py --suite services`로 실행한다. 실제 HTTP 요청·동의 UI·helper 실행·Inno 설치와 실패 복구는 수동 플랫폼 검증에서 수행한다. 네트워크 fixture는 명시적으로 허용한 loopback 주소만 사용한다. 개발 중 매번 설치하지 않는다.
