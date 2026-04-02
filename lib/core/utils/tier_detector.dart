import 'dart:io';

/// 기기 성능 Tier 판별
/// Tier 1 (고사양): 모든 Worker ON
/// Tier 2 (중사양): Flash+Wall+Corner ON
/// Tier 3 (저사양): Wall만 ON
class TierDetector {
  TierDetector._();

  static int? _cachedTier;

  /// 기기 Tier 판별 (1/2/3)
  static int detectTier() {
    if (_cachedTier != null) return _cachedTier!;

    final cores = Platform.numberOfProcessors;

    // RAM 정보는 직접 접근 불가 → 코어 수 기반 추정
    if (cores >= 8) {
      _cachedTier = 1;
    } else if (cores >= 6) {
      _cachedTier = 2;
    } else {
      _cachedTier = 3;
    }

    return _cachedTier!;
  }

  /// 해당 Worker가 현재 Tier에서 활성화되는지
  static bool isWorkerEnabled(String workerName) {
    final tier = detectTier();
    switch (workerName) {
      case 'flash':
        return tier <= 2;
      case 'sonar':
        return tier <= 1;
      case 'wall_constraint':
        return true; // 모든 Tier
      case 'ps':
        return tier <= 1;
      case 'corner':
        return tier <= 2;
      default:
        return true;
    }
  }

  static String tierDescription(int tier) {
    switch (tier) {
      case 1:
        return 'High (All workers enabled)';
      case 2:
        return 'Medium (Flash+Wall+Corner)';
      default:
        return 'Low (Wall constraint only)';
    }
  }
}
