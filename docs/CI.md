# 검사와 자동 배포

| 시점 | 검사와 배포 |
| --- | --- |
| 작업 중 | 수정 영역의 로컬 검사: `rules`, `services`, `scene` |
| 개발 브랜치 push·beta 대상 PR | 자동 실행 없음 |
| main 대상 PR | 보호 규칙의 빠른 `test`. 게시 없음 |
| main·beta push | 빠른 검사 → 배포 플랫폼 빌드·설치/실행 검사 → 자동 릴리스 |
| 통합 전 플랫폼 검증 | `Build, test and release` 수동 실행. 기본값은 게시 안 함 |

자동 배포는 문서 변경을 포함한 모든 main·beta push에 적용한다. 빠른 검사·해당 배포 플랫폼 검사 중 하나라도 실패하면 릴리스를 게시하지 않는다. main은 Windows 정식 릴리스, beta는 Windows·Android 사전 릴리스다. APK 설치에는 서명이 필수이므로 Android는 고정 개발 서명으로 beta에서만 배포한다. 버전·재시도 규칙은 [버전 관리](VERSIONING.md)를 따른다.

## 로컬 검사

```sh
python scripts/prototype-test.py --godot /path/to/Godot-4.7.2 --suite rules
python scripts/prototype-test.py --godot /path/to/Godot-4.7.2 --suite services
python scripts/prototype-test.py --godot /path/to/Godot-4.7.2 --suite scene
```

`--suite all`은 빠른 검사를 모두 실행한다. 같은 입력으로 통과한 빠른 검사·Windows EXE는 캐시로 재사용한다. 검사·빌드 캐시는 버전과 입력이 일치할 때만 사용한다. 통합 파이프라인에서 빠른 검사를 한 번 실행하며 플랫폼 작업에서 같은 소스 검사를 반복하지 않는다.

Windows는 내보낸 EXE의 진행·저장·UI, Inno 설치·건강 확인·실패 복구, 동의 전 다운로드 차단을 검사한다. Android는 실제 APK 설치·화면·터치/키보드·저장·덮어 설치·재실행을 검사한다. 테스트용 QA APK는 릴리스 파일에 포함하지 않는다.

수동 실행은 `platforms=all/windows/android`로 필요한 플랫폼만 선택한다. `publish=true`는 main의 Windows 검사 또는 beta의 Windows·Android 검사를 모두 통과했을 때만 게시한다. 개발 브랜치에서는 항상 게시하지 않는다. 자동 실행은 해당 브랜치의 배포 플랫폼을 생략하지 않는다. 검사 화면은 실행 시도별로 보관하고, 같은 실행의 플랫폼 아티팩트는 재실행 시 교체해 업로드 충돌을 피한다. ADB 로그 읽기의 일시 오류는 기존 제한 시간 안에서 재시도하며 설치·게임 동작은 재실행하지 않는다.

CI 설정 변경은 `python -m unittest discover -s tests/ci`와 actionlint로 검사한다. 문서만 바꾸면 링크와 `git diff --check`만 로컬에서 확인한다. 보호 맵 변경은 `node scripts/godot-asset-test.mjs`로 검사한다.

## 추후 정식 Android 배포를 추가할 때

현재 main은 Android를 배포하지 않는다. 추후 정식 APK를 추가하려면 아래 비공개 서명 설정과 정식 APK 검증 후 워크플로를 활성화한다.

저장소의 **Settings → Secrets and variables → Actions → Repository secrets**에 다음을 등록한다. 키·비밀번호를 Git이나 PR·채팅에 넣지 않는다.

| Secret | 값 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 정식 keystore 파일의 Base64(줄바꿈 없이) |
| `ANDROID_KEYSTORE_PASSWORD` | keystore와 해당 키에 공통으로 설정한 비밀번호 |
| `ANDROID_KEY_ALIAS` | keystore 안의 서명 키 alias |

기존 정식 키가 있다면 같은 키를 사용한다. 새 제품의 키가 없다면 사용자 컴퓨터에서 JDK의 `keytool`로 만들고 별도 백업한다:

```sh
keytool -genkeypair -keystore security-lab-release.jks -alias securitylab -keyalg RSA -keysize 3072 -validity 10000
```

키 비밀번호는 keystore 비밀번호와 같게 설정한다. GitHub CLI로 등록하려면 사용자 계정으로 로그인한 뒤 실행한다:

```sh
python -c "import base64,pathlib; print(base64.b64encode(pathlib.Path('security-lab-release.jks').read_bytes()).decode())" | gh secret set ANDROID_KEYSTORE_BASE64 --repo nu4ddi4/security-lab-game
gh secret set ANDROID_KEYSTORE_PASSWORD --repo nu4ddi4/security-lab-game
gh secret set ANDROID_KEY_ALIAS --repo nu4ddi4/security-lab-game
```

main APK는 private 키로 release export하며, QA APK도 같은 키를 써서 덮어 설치를 검사한다. 비디버그 APK의 저장 검사는 테스트용 AOSP 에뮬레이터에서만 root로 확인한다. 공개 AOSP 테스트 키는 beta 전용이다. 기존 beta APK와 정식 APK는 서명이 달라 직접 덮어 설치할 수 없다.

아티팩트는 14일 보관한다. 버전 릴리스 파일은 검사된 EXE·ZIP·설치 파일·APK·체크섬·빌드 기록이며, 게시 완료 후 업데이트 채널을 반영한다.
