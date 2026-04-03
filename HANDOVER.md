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

### 미해결 (다음에 해야 할 것)

#### 1. 기준점 설정
바닥 감지 후 기준점을 잡는 로직이 없음. 기준점에서부터 도면 시작해야 함.

#### 2. AR 카메라 위 실시간 도면 (핵심!)
- 바닥 감지 → 바닥에 반투명 색칠
- 벽 감지 → 벽에 반투명 색칠
- 모서리에 선 표시
- 사용자가 돌아다니면 색칠 영역이 실시간으로 늘어남
- 상단 미니맵에 도면 전체 모양

현재 `_PlaneOverlayPainter`가 있지만 하단/상단에 바만 그림. 실제 바닥/벽 영역 색칠 안 함.
ARCore 평면 폴리곤을 화면 좌표로 투영하려면 카메라 projection/view 행렬이 필요.

#### 3. 도면 그리기 개념 (사용자가 설명, 반드시 따를 것)
```
1. 바닥 감지 → 기준면 (평면 개념)
2. 벽 감지 → 수직면 (평면 개념) → 바닥+벽 만남 = 모서리 → 그림 시작 + 크기 측정 시작
3. 꺾이는 벽 감지 → 연결된 면 추가 → 수치 자동 보정
4. 다시 바닥 이어짐 → 모양 확정 → 보정
5. 반복 → 한 바퀴 돌아오면 도면 완성
```
- AR은 면의 종류(바닥/벽)를 **판별**. 거리 계산이 목적이 아님
- 크기는 AR로 대략 잡고, 센서(Flash/Sonar)로 보정
- 면이 추가될 때마다 기존 수치가 보정됨

#### 4. Flash Worker 역할 (사용자가 설명, 반드시 따를 것)
- 플래시 깜박임 → 벽마다 밝기가 다름 (각도/거리) → 면 구분 → 경계 = 모서리
- **AR이 벽 못 찾을 때 Flash가 벽을 찾아줘야 함** (현재 보정만 함)
- 역제곱 거리는 부가, 핵심은 명암 차이로 면을 구분하는 것

#### 5. 센서 실활용 문제
- Flash/Sonar/Corner Worker가 연결만 되고 실제 보정 효과 미미
- 코너가 있어야 Worker가 동작하는 닭-달걀 문제
- Flash가 코너 없이도 면 경계를 찾아서 벽을 추론하는 로직 필요

#### 6. 벽 교차점 계산 문제
- 현재: ARCore 수직평면 방향으로 교차점 계산
- 마주보는 벽 병합 방지는 수정됨 (수직 거리 체크)
- 하지만 ARCore 벽 감지가 느리고 불안정 → 센서 보조 필수

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
