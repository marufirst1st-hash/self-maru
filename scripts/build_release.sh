#!/bin/bash
# Floor Measure 릴리즈 빌드 스크립트
# 사용법: ./scripts/build_release.sh
#
# 환경변수 또는 SECRETS.md에서 키를 읽어 dart-define으로 주입
# AWS 키가 없으면 빌드는 되지만 S3 업로드가 작동하지 않음

# AWS 키 (환경변수에서 읽기)
AWS_ACCESS_KEY="${AWS_ACCESS_KEY:-}"
AWS_SECRET_KEY="${AWS_SECRET_KEY:-}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
AWS_BUCKET="${AWS_BUCKET:-floor-measure-storage}"

# 키가 없으면 경고
if [ -z "$AWS_ACCESS_KEY" ] || [ -z "$AWS_SECRET_KEY" ]; then
  echo "⚠ AWS 키가 설정되지 않았습니다."
  echo "  export AWS_ACCESS_KEY=your_key"
  echo "  export AWS_SECRET_KEY=your_secret"
  echo "  S3 업로드 없이 빌드를 계속합니다."
  echo ""
fi

echo "🔨 Building Floor Measure release APK..."
echo "  Region: $AWS_REGION"
echo "  Bucket: $AWS_BUCKET"
echo ""

flutter build apk --release \
  --dart-define=AWS_ACCESS_KEY="$AWS_ACCESS_KEY" \
  --dart-define=AWS_SECRET_KEY="$AWS_SECRET_KEY" \
  --dart-define=AWS_REGION="$AWS_REGION" \
  --dart-define=AWS_BUCKET="$AWS_BUCKET"

if [ $? -eq 0 ]; then
  APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
  SIZE=$(du -h "$APK_PATH" 2>/dev/null | cut -f1)
  echo ""
  echo "✅ 빌드 성공!"
  echo "  APK: $APK_PATH"
  echo "  크기: $SIZE"
else
  echo ""
  echo "❌ 빌드 실패"
  exit 1
fi
