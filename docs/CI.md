# 검사와 자동 배포

| 시점 | 검사와 배포 |
| --- | --- |
| 작업 중 | 수정 영역의 로컬 검사: `rules`, `services`, `scene` |
| 개발 브랜치 push·beta 대상 PR | 자동 실행 없음 |
| main 대상 PR | 보호 규칙의 빠른 `test`. 게시 없음 |
| main·beta push | 빠른 검사 → 배포 플랫폼 빌드·설치/실행 검사 → 자동 릴리스 |
| 통합 전 플랫폼 검증 | `Build, test and release` 수동 실행. 기본값은 게시 안 함 |

자동 배포는 문서 변경을 포함한 모든 main·beta push에 적용한다. 빠른 검사·해당 배포 플랫폼 검사 중 하나라도 실패하면 릴리스를 게시하지 않는다. 두 브랜치 모두 Windows·Android를 배포하며 main은 정식, beta는 사전 릴리스로 표시한다. 출시 전 APK는 같은 고정 공용 개발 키로 서명한다. 버전·재시도 규칙은 [버전 관리](VERSIONING.md)를 따른다.

## 로컬 검사

```sh
python scripts/prototype-test.py --godot /path/to/Godot-4.7.2 --suite rules
python scripts/prototype-test.py --godot /path/to/Godot-4.7.2 --suite services
python scripts/prototype-test.py --godot /path/to/Godot-4.7.2 --suite scene
```

`--suite all`은 빠른 검사를 모두 실행한다. 같은 입력으로 통과한 빠른 검사·Windows EXE는 캐시로 재사용한다. 검사·빌드 캐시는 버전과 입력이 일치할 때만 사용한다. 통합 파이프라인에서 빠른 검사를 한 번 실행하며 플랫폼 작업에서 같은 소스 검사를 반복하지 않는다.

Windows는 내보낸 EXE의 진행·저장·UI, Inno 설치·건강 확인·실패 복구, 동의 전 다운로드 차단을 검사한다. Android는 실제 APK 설치·화면·터치/키보드·저장·덮어 설치·재실행을 검사한다. 테스트용 QA APK는 릴리스 파일에 포함하지 않는다.

수동 실행은 `platforms=all/windows/android`로 필요한 플랫폼만 선택한다. 새 릴리스의 `publish=true`는 Windows·Android 검사를 모두 통과했을 때만 게시한다. 기존 정식 버전에 APK만 추가할 때는 동일한 게임 소스를 확인하고 Android만 빌드·검증한다. 개발 브랜치에서는 항상 게시하지 않는다. 검사 화면은 실행 시도별로 보관하고, 같은 실행의 플랫폼 아티팩트는 재실행 시 교체해 업로드 충돌을 피한다. ADB 로그 읽기의 일시 오류는 기존 제한 시간 안에서 재시도하며 설치·게임 동작은 재실행하지 않는다.

CI 설정 변경은 `python -m unittest discover -s tests/ci`와 actionlint로 검사한다. 문서만 바꾸면 링크와 `git diff --check`만 로컬에서 확인한다. 보호 맵 변경은 `node scripts/godot-asset-test.mjs`로 검사한다.

## Android 서명

main과 beta는 같은 패키지 ID와 핀으로 고정한 AOSP 공용 테스트 키를 사용한다. APK와 QA APK의 인증서를 확인하고, 같은 키로 서명된 파일의 덮어 설치·저장 유지·재실행을 검사한다. 비디버그 APK의 저장 검사는 테스트용 AOSP 에뮬레이터에서 root로 확인한다. 서명 비밀값 등록은 필요하지 않으며 전용 서명 전환은 정식 출시 준비 때 진행한다.

아티팩트는 14일 보관한다. 버전 릴리스 파일은 검사된 EXE·ZIP·설치 파일·APK·체크섬·빌드 기록이며, 게시 완료 후 업데이트 채널을 반영한다.
