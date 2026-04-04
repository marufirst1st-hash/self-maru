# Floor Measure - 개발 인수인계 (다음 대화용)

## 프로젝트 정보
- **앱**: Floor Measure - 바닥재 시공용 공간 측정
- **GitHub**: marufirst1st-hash/self-maru
- **Flutter**: 3.35.4 / Dart 3.9.2
- **명세서**: `C:\Users\HP\Downloads\Floor_Measure_개발명세서_ABC_전체.md`

## 프로그램 목적
사용자가 본인이 가진 스펙을 이용해서 **빠르고 쉽게, 정확하게 도면을 그리는 것**
- A안: 마커 + B안
- B안: 스마트폰 센서만
- C안: LiDAR + B안

## 나(AI)의 역할
- 명세서를 변경하지 않고 그대로 구현
- 각 기능을 더 잘 활용해서 100% 이상을 뽑아내는 것
- 기존 기능을 빼면 안 됨, 항상 발전시키는 방향

## 현재 상태

### 완료된 것
- 코드 구조: 명세서 100% 일치 (55+ Dart 파일)
- ARCore 네이티브 구현: 카메라 프리뷰 + 평면 감지 (Sceneform 없이 직접 GL 렌더링)
  - `ArCoreTexturePlugin.kt`: Flutter TextureRegistry에 ARCore 카메라 렌더링
  - `arcore_view.dart`: Flutter Texture 위젯 + MethodChannel
- 모든 센서 코드 연결: AR + PDR + Flash + Sonar + Corner + WallConstraint + Merger
- Flash: 네이티브에서 토치 ON/OFF → 4x4 그리드 밝기 차분 → 면 경계 감지
- Sonar: 네이티브 SonarRecorder → SonarBridge → FMCW 처리
- Corner: 네이티브 Sobel gradient → Flutter
- Wall Constraint: 코너 변경 시 즉시 직각/폐합 보정
- Merger: 모든 보정값 실시간 가중 병합
- Tier 시스템: 기기 성능별 Worker 활성화
- PDR: 가속도+자이로 걸음 추적 (보폭 상한 1.2m, 최소 임계값 1.5m/s²)
- 가혹 테스트 3라운드 통과 (OOB, 크래시, 메모리, 라이프사이클 등)
- 자동 업데이트 (GitHub Actions + Releases)
- Hive 로컬 저장 + 이력 화면
- DXF 출력 + S3 업로드 + ERP 전송
- 스캔 로그 자동 기록 (ScanLogger)
- 디버그 패널 (센서 상태 실시간 표시)

### 이전 대화에서 완료한 것 (2026-04-03~04)
- 기준점 설정 (첫 바닥 평면 중심)
- AR GL 오버레이: 구글 PlaneRenderer 방식 (바닥 초록, 벽 파랑)
- hitTest 점 누적 → 월드 좌표 고정 색칠 (다시 비춰도 유지)
- Flash: Config.FlashMode.TORCH로 ARCore 내 토치 제어 (CAMERA_IN_USE 해결)
- ARCore 1.44 → 1.46 업그레이드
- 폰 기울기(pitch) 기반 벽/바닥 구분
- 시작점 탭 설정 + 시작점 복귀 감지
- 중앙 알림 UI (벽/바닥 전환 시 게임 스타일)

### 시도했지만 실패한 접근들 (다시 하지 말 것!)
1. **Flutter CustomPaint로 AR 오버레이** → 좌표계 안 맞음. 네이티브 GL에서 직접 그려야 함
2. **ARCore 수직평면에 의존한 벽 감지** → 불안정, 흰벽 못 잡음
3. **바닥 폴리곤 꺾임점 = 코너** → ARCore 폴리곤이 벽 위치를 정확히 반영 안 함
4. **폰 걷는 경로 = 벽 위치** → 완전히 틀림. 제자리에서 벽을 비춰도 벽 길이가 나와야 함
5. **Camera2 setTorchMode** → ARCore가 카메라 점유해서 CAMERA_IN_USE 에러

### 미해결 — 핵심 (다음 대화에서 반드시 해야 할 것)

#### 1. hitTest 3D 점군 → RANSAC → 벽 평면 → 코너 → 도면 (최우선!)
현재 hitTest로 3D 점을 누적하고 색칠까지는 됨. 하지만 **이 점들을 분석해서 벽을 찾는 로직이 없음**.

필요한 파이프라인:
```
hitTest 벽 점군 (wallPaintPoints: List<float[3]>)
  → RANSAC으로 수직 평면 피팅 (벽 1개 = 평면 1개)
  → 수직 평면 2개의 교차 = 코너 (수직선)
  → 코너의 바닥 높이 XZ 좌표 = 도면 코너 점
  → 코너들 연결 = 2D 도면
```

바닥 도면을 그리려면 벽의 위치를 알아야 하고, 벽을 알려면 3D 점군 분석이 필수.
렌더링이 아니라 **3D 기하 분석**이 필요한 것.

RANSAC 참고: Open3D (Python), 또는 직접 구현 (Kotlin/Dart):
- 무작위 3점 → 평면 피팅
- 법선이 수직(ny≈0)인 평면만 = 벽
- inlier 점이 많은 평면 = 확실한 벽

#### 2. 벽 색칠 개선
현재: 0.04m 사각형 점으로 색칠 → 듬성듬성
필요: 인접 점들을 연결해서 **연속 면**으로 색칠
벽을 따라 비추면 파란 면이 자연스럽게 늘어나야 함

#### 3. 도면 그리기 개념 (사용자가 설명, 반드시 따를 것)
```
1. 바닥 감지 → 기준면
2. 벽 비추기 → hitTest로 벽 표면 3D 좌표 수집
3. 점군 분석 → 벽 평면 추출 → 벽-벽 교차 = 코너
4. 벽-바닥 교차 = 모서리 (도면 선분)
5. 한 바퀴 → 시작점 복귀 → 도면 닫기 → 면적
```

#### 4. 센서 보조
Flash/Sonar/Corner Worker가 코드상 연결됨. 벽이 제대로 잡히면 보정 효과가 나올 것.
현재는 벽 자체가 안 잡혀서 보정할 대상이 없는 상태.

## 기술 스택

### 네이티브 (Android)
- `ArCoreTexturePlugin.kt`: ARCore Session + GL 렌더링 + Flash 명암 + Corner Sobel
- `SonarRecorder.kt`: 네이티브 AudioRecord (48kHz)
- `ApkInstaller.kt`: PackageInstaller API (OTA)
- `ArCoreNativeView.kt`: 이전 PlatformView 방식 (미사용, 참고용)
- ARCore SDK 1.44.0 (build.gradle.kts에 직접 의존)
- `android/app/src/main/res/xml/file_paths.xml`: FileProvider

### Flutter
- `core/engines/arcore_view.dart`: ArCoreNativeView + ArCoreController (MethodChannel)
- `core/engines/pdr_engine.dart`: 가속도+자이로 → 걸음+위치+방향
- `core/engines/sensor_bridge.dart`: sensors_plus → PdrEngine
- `core/workers/`: FlashWorker, SonarWorker, WallConstraint, CornerWorker, Merger
- `core/workers/sonar_bridge.dart`: 네이티브 녹음 → SonarWorker
- `core/utils/scan_logger.dart`: 테스트용 로그 기록
- `mode_b/mode_b_screen.dart`: Mode B 메인 화면 (모든 센서 연결)

### AR → Flutter 이벤트 흐름
```
네이티브 ArCoreTexturePlugin
  → MethodChannel "com.floormeasure/arcore"
    → onPlaneDetected: 평면 첫 감지
    → onPlanesUpdated: 매 500ms 모든 평면 데이터 (type/center/normal/extent/polygon)
    → onCameraPose: 카메라 위치 (x,y,z)
    → onFlashEdges: Flash 명암 경계 (edges + gridDiff)
    → onCornerCandidates: Sobel gradient 피크 위치
    → onPlaneTap: 화면 중앙 hitTest 결과
```

## 테스트 환경
- SM-S901N (Galaxy S22), Android 16
- USB 디버깅 가능
- adb: `/c/Users/HP/AppData/Local/Android/sdk/platform-tools/adb.exe`
- `flutter run -d R3CT40CHAXT` (기기 ID)
- 로그: `adb logcat -d | grep "ArCorePlugin"`
- 스캔 로그: `adb shell ls /sdcard/Android/data/com.floormeasure.floor_measure/files/`

## 주의사항
1. **명세서를 절대 변경하지 말 것** - 명세서대로 구현
2. **기존 기능을 빼지 말 것** - 항상 발전시키는 방향
3. **AR만으로 해결하려 하지 말 것** - 모든 센서를 활용
4. **사용자에게 떠넘기지 말 것** - 자동 감지가 핵심
5. **테스트 없이 코드만 바꾸지 말 것** - 실기기 테스트 필수
