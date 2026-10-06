# 개발 규칙

- 웹 학습 게임의 기획은 `docs/PLAN.md`이다. Godot 프로젝트가 있는 브랜치의 조사 계획은 `docs/INVESTIGATION_PROTOTYPE.md`이다. CI 운영은 `docs/CI.md`를 따른다.
- 실제 IP·URL로 요청하지 않는다. 명령어는 허용 목록만 해석한다.
- `eval`, `Function`, 사용자 입력 기반 `fetch`, 소켓, 셸 실행을 도입하지 않는다.
- 웹 동적 출력에는 `textContent`를 사용한다. 개인 파일·실제 비밀번호는 받지 않는다.
- 포트와 로그인은 시뮬레이션이다. 웹 SHA-256은 Web Crypto 실제 연산이다.
- 기존 학습 미션은 방어 적용과 정상 기능 재검증을 모두 통과해야 완료된다. 조사 프로토타입은 사건별 운영·보고·통제 조건을 따른다.
- 선택 암호 퍼즐과 실제 서버 실습은 필수 미션 안정화 후 진행한다.

## 작업 중 검증

변경에 필요한 검사만 실행한다. 통과한 검사는 관련 코드가 다시 바뀌거나 실패·미해결 문제가 있을 때만 반복한다. Godot 전용 변경에 웹 전체 검사를 실행하지 않는다.

| 변경 범위 | 필요한 검사 |
| --- | --- |
| 문서·주석만 | `git diff --check`, 수정한 경로·명령 확인. 실행 테스트 생략 |
| Godot 프로토타입 콘텐츠·엔진·저장 | `godot --headless --path godot --script res://prototype/tests/unit.gd` — 시나리오·저장 검증 포함 |
| Godot 프로토타입 UI·장면·이동 | `npm run test:prototype` — 시나리오·더미 장면 검사. 화면이나 입력을 바꿨으면 해당 부분만 실제 화면 확인 |
| 기존 Godot 학습 게임 | `godot --headless --path godot --script res://tests/unit.gd`와 `godot --headless --path godot -- --qa`. 공통 이동·진입을 바꾸면 프로토타입 검사도 실행 |
| 웹 엔진·저장·장면 로직 | `npm test` |
| 웹 서버·실행기 | `npm run test:server` |
| 웹 UI·CSS·입력·브라우저 시작 | 관련 Playwright 검사만 `npm run test:e2e -- --grep "검사 이름"`으로 실행. 로직·서버도 바꾸면 해당 검사 추가 |
| 자산·패키징·CI | 변경한 자산 검사·빌드·워크플로 검증. CI 정책은 `python -m unittest discover -s tests/ci`, YAML은 actionlint로 확인. Godot 보호 지오메트리 변경은 `node scripts/godot-asset-test.mjs`로 확인 |

- Godot 명령은 프로젝트가 있는 브랜치에서 실행한다. Godot는 **4.7.2 stable**을 사용한다. CLI가 PATH에 없으면 실행 파일 경로를 사용한다. 프로토타입 검사에는 `npm run test:prototype -- --godot "실행 파일 경로"`를 쓸 수 있다.
- Godot·의존성·가져온 자산 캐시를 재사용한다. 버전·의존성·자산 변경이나 캐시 오류가 없으면 다운로드·전체 가져오기를 반복하지 않는다.
- 웹 공식 E2E는 **Windows 10/11 + 설치된 최신 Google Chrome Desktop**이다. 해당 환경이 없으면 실행 가능한 검사만 수행하고 미검증 항목을 명시한다. 같은 환경 오류를 반복 실행하지 않는다.
- 개발 중에는 느린 전체 CI가 끝날 때까지 매번 기다리지 않는다. 현재 커밋의 통과한 CI 검사를 로컬에서 중복 실행하지 않는다.

## 병합·배포 전 검증

- 영향을 받는 런타임의 전체 회귀 검사 결과를 확인한다. 웹은 `npm run check`, Godot는 프로토타입 검사와 기존 Native unit·`--qa` 검사다. 변경하지 않은 다른 런타임의 전체 검사는 생략한다.
- Windows EXE를 배포할 때는 대상 빌드의 첫 화면·조작·저장·재실행을 Windows에서 확인한다. 기존 게임과 프로토타입을 함께 포함하면 두 진입 경로를 확인한다.
- 현재 커밋의 CI 결과로 충족되는 검사는 재사용한다. 통과·실패·환경 부족으로 미검증인 항목을 구분해 기록한다.
