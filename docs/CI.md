# 검사와 빌드

| 시점 | 검사 |
| --- | --- |
| 작업 중 | 수정 영역의 로컬 검사만: `rules`, `services`, `scene` |
| 개발 브랜치 push·beta 대상 PR | 자동 검사 없음. 필요한 로컬 결과를 PR에 기록 |
| beta 통합 push | 빠른 전체 검사와 CI 정책. 성공한 동일 입력은 캐시 재사용 |
| main 대상 PR | 보호 규칙의 `test`. 빠른 검사와 기존 검증 결과 재사용 |
| main 병합 직후 | 같은 내용을 다시 빌드·검사하지 않음 |
| 큰 화면·모바일·패키징 변경 또는 릴리스 | `Godot platform validation` 수동 실행 |

기본 CI는 Linux의 `test` 작업 하나다. 큰 GLB·LFS·내보내기 템플릿·Chrome·npm·Android 에뮬레이터를 받지 않는다. 임시 프로젝트에 현재 조사 스크립트·콘텐츠·필요한 폰트만 복사해 사건·저장·진단·업데이트 정책·입력·더미 장면을 검사한다. 문서·Blender 원본만 바뀌면 게임 실행을 생략한다. 실행 실패나 오류 출력·성공 표식 누락은 실패로 처리하며, 성공한 전체 검사만 콘텐츠 해시별 캐시에 남긴다. 캐시를 읽을 수 없는 브랜치·변경된 입력은 검사를 실행한다.

## 로컬

```sh
python scripts/prototype-test.py --godot /path/to/Godot-4.7.2 --suite rules
python scripts/prototype-test.py --godot /path/to/Godot-4.7.2 --suite services
python scripts/prototype-test.py --godot /path/to/Godot-4.7.2 --suite scene
```

`--suite all`은 위 검사를 모두 실행한다. 수정 영역만 먼저 확인하고 큰 구조 변경·베타 통합 때 전체 검사를 한 번 확인한다. 동일 코드로 통과한 CI가 있으면 로컬에서 다시 실행하지 않는다. 화면·입력을 바꿨으면 해당 동작만 실제 화면으로 확인한다.

CI 설정은 `python -m unittest discover -s tests/ci`와 actionlint로 검증한다. 사무실 보호 노드·충돌 지오메트리를 바꾸면 `node scripts/godot-asset-test.mjs`를 실행한다. 이 제작 도구는 Node 표준 모듈만 사용한다.

## 플랫폼과 배포

Actions의 `Godot platform validation`을 검사할 브랜치에서 수동 실행한다. Windows와 Android를 병렬로 빌드하고 EXE 단독 실행·입력·저장/재로드·실제 화면, Windows 동의 전 다운로드 차단·Inno 설치·실패 복구, Android 설치·터치/키보드·백그라운드 저장·덮어 설치·재실행을 확인한다. 소스 단계의 빠른 시나리오를 두 플랫폼에서 반복하지 않고, 내보낸 실제 앱의 동작을 검사한다. 플랫폼 작업은 릴리스나 큰 플랫폼 변경에만 필요하다.

명시적 베타 배포는 검증된 **beta 브랜치**의 성공한 실행 ID·빌드 SHA로 `Publish verified beta`를 수동 실행한다. 같은 소스·버전·체크섬의 EXE·ZIP·설치 파일·APK를 게시하고 마지막에 업데이트 채널을 반영한다. 커밋 문구·태그·통합 성공만으로 게시하지 않는다. 기존 릴리스는 변경하지 않는다. 정식 Android 배포에는 비공개 서명이 필요하다.

검증 아티팩트는 14일 보관한다. `main`과 `beta`는 유지하고 통합을 마친 작업 브랜치는 작업자가 삭제한다. 이전 웹 버전과 제작 기록은 Git 태그·커밋에서 찾는다.
