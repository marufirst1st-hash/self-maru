# Floor Measure - 프로젝트 인수인계 문서

## 1. 프로젝트 개요

**앱 이름**: Floor Measure  
**목적**: 바닥재 시공 전문가용 스마트 공간 측정 앱  
**플랫폼**: Android (주), Web Preview 지원  
**언어/프레임워크**: Flutter 3.35.4 / Dart 3.9.2  
**GitHub**: https://github.com/marufirst1st-hash/self-maru  
**패키지명**: `com.floormeasure.floor_measure`

---

## 2. 핵심 비즈니스 로직

### 앱의 전체 흐름
```
현장 도착
  → 새 프로젝트 생성 (현장명, 주소 입력)
  → 측정 방식 선택 (System A or B)
  → 스캔 실행 (모든 연산은 기기 로컬에서 처리)
  → 결과 확인 (도면 + 면적 데이터)
  → S3 업로드 (DXF 도면 + 현장 사진)
  → ERP 주문서에 데이터 입력
      - 텍스트: 면적, 방별 데이터 직접 입력
      - 링크: S3 URL (사진, DXF 도면)
```

### 측정 시스템 2종
| 항목 | System A (Marker Precision) | System B (Quick Scan) |
|------|-----------------------------|-----------------------|
| 방식 | AprilTag 마커 기반 | 4-Layer 센서 퓨전 |
| 정확도 | ±1~2% | ±3% |
| 특징 | 마커를 코너에 배치 후 촬영 | 방 주위를 걸으며 스캔 |
| 레이어 | 없음 | AR Base / PDR / Flash / Corner |

### 중요: 연산 위치
- **모든 측정 연산은 기기 로컬에서 처리** (서버 연산 없음)
- 서버(AWS)는 저장/전송 역할만 담당
- 면적 계산: Shoelace formula (lib/models/measurement.dart)
- DXF 도면 생성: 로컬에서 텍스트 파일로 직접 생성 (lib/services/dxf_service.dart)

---

## 3. API 키 및 환경 설정

### AWS S3 (현재 사용 중)
```
Access Key ID     : → SECRETS.md 파일 참조 (별도 전달)
Secret Access Key : → SECRETS.md 파일 참조 (별도 전달)
Region            : ap-northeast-2 (서울)
Bucket            : floor-measure-storage
Base URL          : https://floor-measure-storage.s3.ap-northeast-2.amazonaws.com
```

### S3 폴더 구조
```
floor-measure-storage/
└── projects/
    └── {project_id}/
        ├── photos/
        │   ├── photo_001.jpg
        │   └── photo_002.jpg
        └── drawings/
            └── {project_name}_{timestamp}.dxf
```

### 빌드 시 키 주입 방법 (dart-define)
```bash
# APK 빌드
flutter build apk --release \
  --dart-define=AWS_ACCESS_KEY={SECRETS.md 참조} \
  --dart-define=AWS_SECRET_KEY={SECRETS.md 참조} \
  --dart-define=AWS_REGION=ap-northeast-2 \
  --dart-define=AWS_BUCKET=floor-measure-storage

# Web 빌드
flutter build web --release \
  --dart-define=AWS_ACCESS_KEY={SECRETS.md 참조} \
  --dart-define=AWS_SECRET_KEY={SECRETS.md 참조} \
  --dart-define=AWS_REGION=ap-northeast-2 \
  --dart-define=AWS_BUCKET=floor-measure-storage
```

### ERP 시스템 (개발 중 - 미연동)
```
플랫폼  : AWS 기반 (동일 계정)
연동 방식: Floor Measure → ERP 주문서 특정 필드에 데이터 삽입
전송 데이터:
  - 텍스트: 총면적, 방별면적, 측정방식, 측정일
  - 링크: 사진 S3 URL들, DXF 도면 S3 URL
현재 상태: ERP API 엔드포인트 미정 (ERP 개발 완료 후 연동 예정)
```

---

## 4. 프로젝트 파일 구조

```
lib/
├── main.dart                    # 앱 진입점, FloorMeasureApp, 다크테마
├── models/
│   ├── measurement.dart         # 핵심 데이터 모델
│   │   ├── Point3D              # 3D 좌표
│   │   ├── Corner               # 코너 (위치 + 신뢰도)
│   │   ├── Wall                 # 벽 (시작~끝 코너)
│   │   ├── Marker               # AprilTag 마커
│   │   ├── FloorPlan            # 방 도면 (코너 목록 + 면적)
│   │   └── MeasurementProject   # 프로젝트 (방 목록 + 메타데이터)
│   └── material_calc.dart       # 자재 계산 모델
│       ├── FloorMaterial        # 자재 정보 (LVT, 라미네이트, 합판 등)
│       ├── MaterialEstimate     # 자재 수량/비용 계산
│       └── DefaultMaterials     # 기본 자재 목록 6종
├── providers/
│   └── app_provider.dart        # 전체 상태 관리 (Provider)
│       ├── 프로젝트 CRUD
│       ├── 스캔 상태 관리
│       ├── 코너/마커 감지 상태
│       └── 데모 데이터 로드
├── screens/
│   ├── home_screen.dart         # 홈 - 프로젝트 목록, 통계, 새 스캔
│   ├── scan_screen.dart         # 스캔 - 뷰파인더, 진행률, 코너 감지
│   └── result_screen.dart       # 결과 - 도면뷰어 / 측정데이터 / ERP전송
├── services/
│   ├── aws_s3_service.dart      # S3 업로드 (AWS Signature V4)
│   ├── dxf_service.dart         # DXF 파일 로컬 생성
│   └── upload_service.dart      # 업로드 통합 + ERP 데이터 포맷
├── utils/
│   └── app_colors.dart          # 전체 색상 시스템 (다크테마)
└── widgets/
    ├── common_widgets.dart      # StatCard, SystemBadge, LayerIndicator, MeasurementModeSelector
    └── floor_plan_painter.dart  # CustomPainter - 도면 렌더링 (벽/치수/면적)
```

---

## 5. 주요 데이터 모델

### MeasurementProject (핵심)
```dart
MeasurementProject {
  id: String (UUID)
  name: String               // 프로젝트명
  siteName: String?          // 현장명
  address: String?           // 주소
  system: MeasurementSystem  // systemA or systemB
  status: MeasurementStatus  // idle/scanning/processing/completed/error
  rooms: List<FloorPlan>     // 방 목록
  markers: List<Marker>      // 감지된 마커 목록
  totalArea: double?         // 총 면적 (m²)
  createdAt: DateTime
  updatedAt: DateTime
}
```

### ERP 전송 데이터 포맷 (upload_service.dart)
```
[Floor Measure 측정 데이터]
총 면적: 33.48 m²
방 수: 2개
방별 면적: 거실: 21.32m² / 침실: 12.16m²
측정 방식: Marker Precision (±1~2%)
측정일: 2025-04-01

[현장 사진]
사진1: https://floor-measure-storage.s3.ap-northeast-2.amazonaws.com/projects/{id}/photos/photo_001.jpg

[도면]
DXF 도면: https://floor-measure-storage.s3.ap-northeast-2.amazonaws.com/projects/{id}/drawings/{name}.dxf
```

---

## 6. 현재 구현 상태

### 완료 ✅
- [x] 전체 UI/UX (다크테마, Material Design 3)
- [x] 프로젝트 CRUD (생성/조회/삭제)
- [x] 측정 시뮬레이션 (코너 감지, 면적 계산, 진행률)
- [x] FloorPlanPainter (도면 렌더링 - 벽/치수/면적표시)
- [x] DXF 파일 로컬 생성 (WALLS / DIMENSIONS / TEXT 레이어)
- [x] AWS S3 업로드 (Signature V4 인증)
- [x] ERP 데이터 포맷 + 클립보드 복사
- [x] 자재 계산 모델 (6종 자재)
- [x] 데모 프로젝트 3개 (앱 첫 실행 시 자동 로드)

### 미완료 ❌ (다음 작업 필요)
- [ ] **실제 카메라 연동** - image_picker 패키지 설치됨, 실제 촬영 UI 없음
- [ ] **AprilTag 실제 감지** - 현재 시뮬레이션만 구현됨 (opencv_dart or ML Kit 필요)
- [ ] **현장 사진 업로드 UI** - S3 서비스는 완성, 사진 선택/촬영 UI 없음
- [ ] **ERP API 실제 연동** - ERP 개발 완료 후 API 엔드포인트 연결 필요
- [ ] **로컬 저장 (Hive)** - 패키지 설치됨, 오프라인 저장 로직 미구현
- [ ] **자재 계산 화면** - 모델은 완성, UI 화면 없음
- [ ] **사용자 인증** - AWS Cognito 미연동
- [ ] **프로젝트 편집** - 생성/삭제만 있고 수정 없음
- [ ] **PDF 리포트** - 고객 배포용 리포트 없음

---

## 7. 디자인 시스템

### 색상 (app_colors.dart)
```dart
bgDark      = 0xFF0D1117  // 최하단 배경
bgCard      = 0xFF161B22  // 카드 배경
bgSurface   = 0xFF1C2333  // 시트/서피스
bgElevated  = 0xFF232D3F  // 경계선/구분선

textPrimary   = 0xFFE6EDF3
textSecondary = 0xFF8B949E
textMuted     = 0xFF6E7681

accent      = 0xFF00BFA5  // 메인 강조색 (틸)
systemA     = 0xFF7C4DFF  // System A 색 (보라)
systemB     = 0xFF00BFA5  // System B 색 (틸, accent와 동일)

success = 0xFF4CAF50
warning = 0xFFFF9800
error   = 0xFFEF5350
info    = 0xFF42A5F5
```

---

## 8. 패키지 의존성

```yaml
provider: 6.1.5+1        # 상태 관리
hive: 2.2.3              # 로컬 DB (설치됨, 미구현)
hive_flutter: 1.1.0      # Hive Flutter 통합
shared_preferences: 2.5.3 # 간단한 키-값 저장
http: 1.5.0              # HTTP 클라이언트
crypto: ^3.0.3           # AWS Signature V4 HMAC-SHA256
path_provider: ^2.1.1    # 파일 시스템 경로
image_picker: ^1.1.2     # 카메라/갤러리 (설치됨, UI 미구현)
uuid: ^4.2.1             # UUID 생성
intl: ^0.20.1            # 날짜 포맷
vector_math: ^2.1.4      # 수학 연산
```

---

## 9. Android 설정

```
패키지명    : com.floormeasure.floor_measure
minSdk     : flutter.minSdkVersion (기본값)
targetSdk  : flutter.targetSdkVersion (기본값)
compileSdk : flutter.compileSdkVersion (기본값)
```

---

## 10. 즉시 이어서 작업 가능한 항목

### 우선순위 HIGH
1. **현장 사진 촬영/업로드 UI 구현**
   - `image_picker` 이미 설치됨
   - `AwsS3Service.uploadFile()` 이미 완성
   - ResultScreen ERP 탭에 사진 선택 버튼 추가하면 됨

2. **Hive 로컬 저장 구현**
   - `hive`, `hive_flutter` 이미 설치됨
   - AppProvider에 loadProjects() / saveProject() 추가
   - MeasurementProject에 toMap() / fromMap() 추가 필요

3. **자재 계산 화면 추가**
   - DefaultMaterials, MaterialEstimate 모델 완성됨
   - 새 screen 추가만 하면 됨

### 우선순위 MEDIUM
4. **ERP API 연동**
   - ERP 개발팀에서 API 엔드포인트 제공 시
   - upload_service.dart의 formatForErp() 수정
   - HTTP POST로 ERP API 호출 추가

5. **사용자 인증 (AWS Cognito)**
   - 팀 계정 관리
   - 프로젝트 소유자 구분

---

## 11. Git 정보

```
Repository  : https://github.com/marufirst1st-hash/self-maru
Branch      : main
Last Commit : feat: Floor Measure - AWS S3 연동 완성
```

---

*이 문서는 AI 간 인수인계용으로 작성됨. 2025-04-01 기준.*
