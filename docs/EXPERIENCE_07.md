# v0.7.0 · 회사형 운영 공간과 장비 표시

## 선택한 범위

v0.6.1의 책상/시설/천장 설비는 이미 충분했다. 더 많은 장식보다 과한 공통
조명을 낮추고 표면/접점 대비, 팀별 업무 화면, 실제 장비의 사건 상태를
우선했다. 기존 세 미션과 저장 호환성을 유지하기 위해 신규 SOC 미션은
추가하지 않았다. 환경음보다 이번 시각 변경의 체감 가치가 커 오디오는 생략했다.

## Authoring → runtime

Interior 06은 보존한다. `experience_upgrade.py`는 이 원본을 읽는 별도
background Blender에서 Interior 07을 만든다. 동일한 protected snapshot을
비교하고 공유 1K 거칠기/직물 Normal, 2K 카펫, 원래 contact AO, 공유 소품을
사용한다. 원본 텍스처·스캔 자산과 라이선스는 기존 credits를 유지한다.

기존 export_interior_lab → runtime-lod → pack_corporate_lab 순서로 경량 GLB를
만든다. 1.2mm base/4mm·12mm LOD 오차와 lossless DOOR/COLLIDER 기하를 유지한다.
새 master는 `assets/authoring/Security_Lab_Interior_07.blend`의 LFS 자산이며
Windows 빌드는 기존처럼 runtime GLB만 가져온다. 큰 master는 EXE에 포함하지 않는다.

## Runtime 장비 화면

`equipmentStatus(state)`는 실제 내장 포트/로그인 시뮬레이션/계산된 해시와
현장 기록을 읽기 전용 snapshot으로 투영한다. 새 save 필드는 없다.
`device-visuals.js`는 기존 화면 표면의 재질과 UV 사본, 랙 하위 primitive의
기존 LED 재질을 연결한다. Anchor/position/index/normal/문/충돌은 바꾸지 않는다.
GLB import가 랙을 여러 Mesh로 나누는 경우도 상위 장비를 찾아 연결한다.

SOC는 사건 현황·alert queue·service health·log·timeline을 나누고 네트워크
콘솔은 현재 포트와 topology를 보여준다. 직원 화면은 팀별 8개 공유 그래픽을
사용하며 두 번째 모니터/노트북의 역할도 구분한다. 기존 벽면 절차/
교대 안내 표면은 읽기 쉬운 인쇄 그래픽을 사용한다. 일부 작은 랙 LCD는
기존 정적 자산으로 남고, 실제 서비스 상태는 LED와 SOC/네트워크 화면에 표시한다.

상태가 달라질 때만 CanvasTexture를 갱신하고 temporal history를 reset한다.
장비 표시는 새 화면 geometry·광원·backend·post-process 추가 없이 기존 표면과 재질을 사용한다.
모델 교체 때 재질/UV를 복원하고 소유한 texture/material/geometry를 해제한다.
3D retry namespace에는 optional module로 제공해 2D fallback을 유지한다.

표시등과 live telemetry는 현장 조사 완료/미션 완료와 다르다. 변경된 장비는
실제 값을 보여주되 현장 기록은 E 재확인이 필요하다. 복구 직후 새 해시가
없으면 pending이고, 자동 hash 복원도 기존 재방문 gate를 충족하지 않는다.

## 검증

기존 보호 인터페이스·정밀 geometry·물리 동선과 save/fallback 회귀를 유지한다.
장비 하위 LED 연결·UV 사본/소유 자원 해제·잘못된 방어의 live 상태·해시 대기를
짧은 unit 검사로 추가한다. 기존 단일 Chrome smoke에 실제 화면/LED 연결 수를
확인하며, 긴 walking review/12개 시점 screenshot/다섯 구역의 GPU timer 비교는
로컬 검토에만 둔다. FPS cap을 성능 비교로 사용하지 않는다.
