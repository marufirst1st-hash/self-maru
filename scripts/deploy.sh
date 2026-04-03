#!/bin/bash
# Floor Measure 자동 배포 스크립트
# 사용법: ./scripts/deploy.sh "변경 내용 설명"
#
# 이 스크립트가 하는 일:
# 1. pubspec.yaml 버전 자동 증가 (build number +1)
# 2. git commit + push
# 3. GitHub Actions가 자동으로: APK 빌드 → Release 생성
# 4. 사용자 앱에서 자동 업데이트 감지

set -e

MESSAGE="${1:-Auto deploy}"

# 현재 버전 읽기
CURRENT=$(grep '^version:' pubspec.yaml | sed 's/version: //')
VERSION=$(echo "$CURRENT" | sed 's/+.*//')
BUILD=$(echo "$CURRENT" | sed 's/.*+//')

# Build number +1
NEW_BUILD=$((BUILD + 1))

# Minor version 자동 증가 (매 10번째 빌드마다)
IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"
if [ $((NEW_BUILD % 10)) -eq 0 ]; then
  MINOR=$((MINOR + 1))
  PATCH=0
else
  PATCH=$((PATCH + 1))
fi
NEW_VERSION="$MAJOR.$MINOR.$PATCH"
NEW_FULL="$NEW_VERSION+$NEW_BUILD"

echo "📦 Version: $CURRENT → $NEW_FULL"

# pubspec.yaml 업데이트
sed -i "s/^version: .*/version: $NEW_FULL/" pubspec.yaml

# Git commit + push
git add -A
git commit -m "release: v$NEW_VERSION - $MESSAGE

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"

git push origin main

echo ""
echo "✅ Pushed v$NEW_VERSION"
echo "   GitHub Actions가 자동으로 APK 빌드 + 릴리즈 생성합니다."
echo "   앱에서 자동 업데이트됩니다."
