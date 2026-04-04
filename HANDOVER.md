# Floor Measure - 개발 인수인계 (2026-04-04)

## 프로젝트 정보
- **앱**: Floor Measure - 바닥재 시공용 공간 측정
- **GitHub**: marufirst1st-hash/self-maru
- **Flutter**: 3.35.4 / Dart 3.9.2
- **ARCore**: 1.46.0
- **명세서**: `C:\Users\HP\Downloads\Floor_Measure_개발명세서_ABC_전체.md`

## 프로그램 목적
사용자가 본인이 가진 스펙을 이용해서 **빠르고 쉽게, 정확하게 도면을 그리는 것**
최종 출력: **CAD/SketchUp 호환 DXF 파일**

## 동작 개념 (사용자가 정의, 반드시 따를 것)
```
B안 시작 → AR이 바닥 인식 → 바닥 그림 → 기준점 체크
→ 벽 비춤 → 벽 그림 → 벽+바닥 만남 = 모서리
→ 옆 벽 비춤 → 기존 벽과 연결 → 다시 바닥 → 기존 바닥과 연결
→ 반복 → 시작점 복귀 → 도면 완성
```
보조 센서:
- **Flash**: 모서리 정확도 향상 (명암 차이로 면 경계)
- **자이로/가속도**: 바닥/벽 구분 (pitch), 이동거리 (PDR)
- **Sonar**: AR 거리 보정

## 현재 상태 (완료)

### 기반
- 코드 구조: 명세서 100% 일치 (55+ Dart 파일)
- ARCore 네이티브 GL 렌더링 (Sceneform 없이 직접)
- 모든 센서 연결: AR + PDR + Flash + Sonar + Corner + WallConstraint + Merger
- 가혹 테스트 3라운드 통과
- 자동 업데이트, Hive 저장, DXF 출력, ERP 전송

### 이번 대화에서 구현한 것 (2026-04-03~04)
1. **RANSAC 벽 인식** (`lib/core/utils/ransac_wall.dart`)
   - hitTest 3D 점군 → RANSAC → 벽 평면 → 교차점 = 코너
   - 시뮬레이션 검증: 직사각/L자/오각형/팔각형/T자/계단형 10/13 PASS
   - 교차점 근접 체크로 가짜 코너 제거
2. **3D 벽 GL 렌더링** (네이티브 `ArCoreTexturePlugin.kt`)
   - RANSAC 결과를 바닥~천장 높이의 3D quad로 GL 렌더링
   - 파란 반투명 벽면 + 외곽선
   - hitTest 점도 작게 표시 (스캔 진행 상태)
3. **hitTest 연속 실행** (네이티브, 200ms 간격)
   - 화면 중앙 hitTest → 벽/바닥 3D 좌표 누적
   - 월드 좌표 고정 → 다시 비춰도 유지
4. **구글 PlaneRenderer 방식 바닥 오버레이**
   - plane centerPose를 model matrix로, boundary 복제+축소, 페이딩 엣지
5. **Flash 토치**: Config.FlashMode.TORCH (ARCore 내 제어)
6. **폰 기울기(pitch)**: PdrEngine에서 중력 Z로 벽/바닥 판단
7. **시작점 시스템**: 탭으로 설정, 1m 이내 복귀 감지
8. **중앙 게임 스타일 가이드**: 상태별 메시지 항상 표시
9. **벽 추적**: 기울기 전환 시 벽 선분 생성

## 시도했지만 실패한 접근 (다시 하지 말 것!)
1. **Flutter CustomPaint로 AR 오버레이** → GL 좌표계와 안 맞음
2. **ARCore 수직평면에만 의존** → 불안정, 흰벽 못 잡음
3. **바닥 폴리곤 꺾임점 = 코너** → 부정확
4. **폰 걷는 경로 = 벽 위치** → AR 개념과 어긋남 (제자리에서 비춰도 벽)
5. **Camera2 setTorchMode** → CAMERA_IN_USE 에러
6. **바닥 경계 직선 → 벽 법선 변환** → 우회적이고 부정확

## 미해결 — 다음 대화에서 해야 할 것

### 1. 3D 도면 완성 (최우선)
현재: 네이티브 GL에서 벽 quad만 그림. Flutter 도면/DXF와 연결 안 됨.

필요:
- 네이티브 RANSAC 결과(벽 quad 좌표)를 Flutter로 전송
- Flutter에서 벽-벽 교차 = 코너, 벽-바닥 교차 = 모서리
- 코너들로 2D 도면 생성 + 3D 벽 데이터 포함
- **DXF에 3D LINE/3DFACE로 벽 출력** → CAD/SketchUp 호환

### 2. 꺾이는 각도/사선 정확도
현재: RANSAC이 벽은 찾지만 실제 앱에서 가짜 코너가 많음.
- 벽이 15개, 코너 34개 나옴 (노이즈)
- Flash 추론 벽이 20개 이상 쌓임
- 해결: 네이티브에서 RANSAC 돌리고 결과만 Flutter로 보내기 (현재 양쪽에서 따로 돌림)

### 3. 단상/기둥 인식
테스트 공간: 단상(바닥 높이 다름), 기둥(수직 장애물), 창문
- ARCore는 다른 높이 수평 평면을 별도로 감지
- 기둥은 작은 수직 평면으로 감지
- 현재 코드는 바닥을 하나로만 봄 → 다른 높이 바닥 분리 필요

### 4. 짐이 많은 방 (벽 30% 가시)
시뮬 FAIL. 센서 보정 또는 FloorSP 방식 벽 추론 필요.
- FloorSP (ICCV 2019): 보이는 벽으로 그래프 → 최단경로로 안 보이는 벽 추론
- Manhattan 제약: 벽을 0/90도로 스냅 (WallConstraint에 이미 있음)

### 5. UX 개선
- 벽 색칠이 점 단위 → 연속 면으로
- 미니맵에 실시간 도면 표시
- 완료 버튼/자동 완성 흐름

## 기술 스택

### 네이티브 (Android)
- `ArCoreTexturePlugin.kt`: ARCore 1.46 + GL 렌더링 + hitTest + RANSAC + Flash
  - wallPaintPoints/floorPaintPoints: hitTest 누적 점
  - wallQuads: RANSAC으로 생성된 3D 벽 quad
  - buildWallQuads(): 2초마다 RANSAC 실행
  - ptProg 셰이더: 3D 월드 좌표 직접 렌더링
  - ovProg 셰이더: 구글 PlaneRenderer 방식 (plane centerPose 기반)
- `SonarRecorder.kt`, `ApkInstaller.kt`

### Flutter
- `core/utils/ransac_wall.dart`: RANSAC 벽 인식 (시뮬 검증)
  - findWallsRANSAC(): 점군 → 벽 평면 추출
  - findCorners(): 벽 교차점 → 코너
  - WallPlane.intersect(): 범위+근접 체크로 가짜 코너 제거
- `core/engines/arcore_view.dart`: ArCoreController + ArCenterHit + ArCameraState
- `core/engines/pdr_engine.dart`: PDR + pitch (벽/바닥 구분)
- `core/workers/flash_worker.dart`: FlashInferredWall (벽 추론)
- `mode_b/mode_b_screen.dart`: 전체 통합 + 중앙 가이드 UI

### AR → Flutter 이벤트
```
네이티브 ArCoreTexturePlugin
  → onPlaneDetected / onPlanesUpdated / onCameraPose
  → onCenterHit: 200ms마다 화면 중앙 hitTest (벽/바닥 3D 좌표)
  → onFlashEdges / onCornerCandidates / onPlaneTap
```

### 3D 도면 알고리즘 (조사 완료, 미적용)
- **Manhattan World RANSAC**: 현재 적용 중 (기본)
- **FloorSP** (ICCV 2019): 누락 벽 추론 → 짐 많은 방에 필요
- **MonteFloor** (ICCV 2021): 불완전 데이터 복구
- **RoomNet** (ICCV 2017): RGB에서 방 레이아웃 → 가벼움

## 테스트 환경
- SM-S901N (Galaxy S22), Android 16
- 테스트 공간: **다각형 + 사선 + 짐 많음 + 단상 + 기둥**
- adb: `/c/Users/HP/AppData/Local/Android/sdk/platform-tools/adb.exe`
- 기기 ID: R3CT40CHAXT

## 시뮬레이션 결과 (`test/wall_detection_sim_test.dart`)
| 테스트 | 코너 | 면적 오차 | 결과 |
|--------|------|----------|------|
| 4x3 직사각형 | 4/4 | 0.6% | PASS |
| L자 (6코너) | 6/6 | 0.1% | PASS |
| 오각형 사선 | 5/5 | 0.9% | PASS |
| T자 (8코너) | 8/8 | 0.1% | PASS |
| 정팔각형 | 8/8 | 0.7% | PASS |
| 짐 30% | 2/4 | 100% | FAIL |
| 실제 오각형 | 5/5 | 0.7% | PASS |
| 사선+직각 혼합 | 5/5 | 0.2% | PASS |
| 긴벽 10x3 | 4/4 | 0.4% | PASS |

## 주의사항
1. **명세서를 절대 변경하지 말 것**
2. **기존 기능을 빼지 말 것**
3. **AR만으로 해결하지 말 것** — 모든 센서 활용
4. **허락 묻지 말 것** — 바로 실행 (bypassPermissions 설정됨)
5. **실패한 접근을 다시 하지 말 것** — 위 목록 참고
6. **실기기 테스트 필수** — 빌드→설치→로그 확인
