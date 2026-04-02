/// Worker가 생산하는 보정값
/// Merger가 이걸 가중 병합하여 코너 위치를 갱신
class Correction {
  final String cornerId;
  final double dx; // x 보정량 (미터)
  final double dy; // y 보정량 (미터)
  final double confidence; // 0~1
  final String source; // 'flash','sonar','wall','ps','corner','marker'

  const Correction({
    required this.cornerId,
    required this.dx,
    required this.dy,
    required this.confidence,
    required this.source,
  });

  Map<String, dynamic> toMap() => {
        'cornerId': cornerId,
        'dx': dx,
        'dy': dy,
        'confidence': confidence,
        'source': source,
      };

  factory Correction.fromMap(Map<String, dynamic> map) {
    return Correction(
      cornerId: map['cornerId'] as String,
      dx: (map['dx'] as num).toDouble(),
      dy: (map['dy'] as num).toDouble(),
      confidence: (map['confidence'] as num).toDouble(),
      source: map['source'] as String,
    );
  }
}
