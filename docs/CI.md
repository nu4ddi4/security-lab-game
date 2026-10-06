# 검사와 빌드

## 실행 범위

| 변경·이벤트 | 실행 |
| --- | --- |
| 일반 문서·AGENTS | CI 정책 검사와 필수 `test` 판정 |
| 개발 브랜치 push | 변경한 웹 또는 Godot의 빠른 검사 |
| Draft PR | 빠른 검사 |
| 일반 PR·main push | 빠른 검사 후 해당 런타임의 Windows EXE 빌드·검사 |
| Windows 패키지 수동 실행 | 선택한 브랜치의 웹 또는 Godot EXE 빌드 |

웹은 unit·서버 검사, Godot는 기존 Native 규칙·저장과 프로토타입 시나리오·더미 장면을 검사합니다. 빠른 Godot 검사는 임시 프로젝트에 필요한 스크립트·JSON·폰트만 복사해 큰 GLB와 내보내기 템플릿을 가져오지 않습니다.

필수 검사 이름은 `test`로 유지합니다. 선택된 검사·Windows 빌드가 실패하거나 예상과 다르게 건너뛰면 `test`도 실패합니다. 문서 PR에도 결과를 반환합니다. push와 PR은 별도 실행 그룹을 사용해 필수 검사를 서로 취소하지 않습니다. Windows 전체 빌드는 개발 push에서 실행하지 않습니다.

공통 설정·미분류 런타임 파일은 보수적으로 검사합니다. 소스 Blend만 바뀌면 실행 검사를 생략하고, 내보낸 GLB가 바뀌면 관련 검사를 실행합니다. `docs/RELEASE.md`는 main에서 미출시 버전의 재빌드를 요청할 수 있는 배포 문서입니다.

## 릴리즈

`package.json`·잠금 파일의 버전과 `docs/RELEASE.md`를 갱신해 PR을 병합합니다. main의 `Test`가 성공하면 릴리즈 작업은 그 실행의 **같은 커밋**에서 만든 `SecurityLab-Windows-X64`를 다운로드합니다. Windows 빌드를 다시 실행하지 않습니다.

릴리즈 작업은 저장소·main·실행 종류·성공 상태·Windows 작업·아티팩트 만료·커밋을 검증합니다. PR·fork 실행이나 다른 커밋의 파일은 배포하지 않습니다. 이미 게시한 버전은 건너뜁니다. 선택한 커밋의 릴리즈 안내와 버전을 사용합니다.

수동 릴리즈에는 현재 main 커밋의 성공한 `Test` 또는 `Package executable` 실행 ID와 버전 태그를 입력합니다. 태그 push만으로 새 패키지를 만들지 않습니다. Godot 네이티브 EXE는 기존처럼 Actions 아티팩트로 제공하며, 이 작업은 웹 릴리즈를 게시합니다.

## 보관과 브랜치 정리

- 개발 EXE 아티팩트는 **14일**, 실패 진단은 **7일** 보관합니다. 릴리즈 다운로드는 GitHub Releases에 남습니다.
- LFS와 Godot 가져오기 캐시를 재사용합니다. Windows Godot 콘솔 실행 파일 복구는 유지합니다.
- main의 `Test`가 성공하면 보호되지 않은 `codex/` 브랜치 중 커밋 전체가 main에 포함된 브랜치를 정리합니다. `main`, `godot-port`, `work`와 미병합 브랜치는 보존합니다.
- 삭제 직전에 브랜치가 변경됐으면 Git lease가 삭제를 거부합니다. 저장소 관리자 설정을 변경하지 않고 같은 자동 정리를 수행합니다.

## 로컬 확인

```sh
python -m unittest discover -s tests/ci
actionlint
```

Godot 브랜치에서는 다음 검사도 실행할 수 있습니다.

```sh
python scripts/ci-godot-test.py --godot /path/to/Godot-4.7.2
```
