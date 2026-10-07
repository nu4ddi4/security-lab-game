# 로컬 진단과 지원 ZIP

조사 게임의 설정에서 **진단 정보 복사**, **지원 패키지 만들기**, 생성 폴더 열기·다른 폴더 저장을 사용한다. 사용자가 실행할 때만 수집하며 네트워크 업로드는 하지 않는다.

버전·빌드 커밋·Godot/화면·제한된 실행 상태, 저장의 유효/손상/누락 여부, 최근 엔진 로그의 허용된 이벤트·오류 위치, 업데이트 상태, 이전 종료 표시를 기록한다. ZIP에는 저장 내용·메모·증거·원본 로그·임의 파일·업데이트 토큰·계정·실제 시스템 경로를 넣지 않는다. 비정상 종료 표시는 충돌을 확정하는 정보가 아니다.

| 경로 | 역할 |
| --- | --- |
| `godot/prototype/scripts/diagnostics.gd` | 현재 조사 저장 검증·실행 상태·격리된 진단 디렉터리 |
| `godot/scripts/diagnostics.gd` · `diagnostics_serializer.gd` | 제한된 파일 읽기·익명화·로그 요약·ZIP·종료 표시 |
| `godot/prototype/scripts/ui.gd` | 복사·저장·결과와 오류 표시 |
| `godot/prototype/build_info.json` | 소스 실행 식별; 빌드 시 정확한 Git HEAD 내장 |

검사는 `python scripts/prototype-test.py --suite services`로 실행한다. Windows 쓰기 금지·junction·실제 EXE 안의 ZIP은 수동 플랫폼 검증에서 확인한다. 손상된 저장을 검사할 때 원본과 현재 진행을 변경하지 않는다. Windows 저장 루트의 `Security Lab · Native` 이름은 기존 사용자 저장 호환성을 위해 유지한다.
