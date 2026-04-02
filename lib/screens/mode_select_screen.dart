import 'dart:io';
import 'package:flutter/material.dart';
import '../mode_a/mode_a_screen.dart';
import '../mode_b/mode_b_screen.dart';
import '../mode_c/mode_c_screen.dart';

/// 모드 선택 + 프로젝트 생성 화면
class ModeSelectScreen extends StatelessWidget {
  const ModeSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isIOS = Platform.isIOS;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // 헤더
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1A237E), Color(0xFF4FC3F7)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.square_foot, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Floor Measure',
                                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                            Text('Spatial Measurement',
                                style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const Text('측정 방식 선택',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text('현장 상황에 맞는 측정 방식을 선택하세요',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // 모드 카드 목록
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _ModeCard(
                    mode: 'A',
                    title: '마커 정밀 측정',
                    subtitle: 'AprilTag 마커 배치 후 촬영',
                    accuracy: '±1%',
                    color: const Color(0xFFFF6B35),
                    icon: Icons.qr_code_scanner,
                    features: const [
                      '큐브/스티커 마커 사용',
                      '카메라 촬영으로 자동 인식',
                      '가장 높은 정확도',
                    ],
                    onTap: () => _showNewProjectDialog(context, 'A'),
                  ),
                  const SizedBox(height: 16),
                  _ModeCard(
                    mode: 'B',
                    title: '스마트 측정',
                    subtitle: '장비 없이 걸으면 자동 측정',
                    accuracy: '±3%',
                    color: const Color(0xFF26C6DA),
                    icon: Icons.directions_walk,
                    features: const [
                      '특별한 장비 불필요',
                      'AR + 센서 퓨전',
                      '가장 빠른 측정',
                    ],
                    onTap: () => _showNewProjectDialog(context, 'B'),
                  ),
                  const SizedBox(height: 16),
                  if (isIOS)
                    _ModeCard(
                      mode: 'C',
                      title: 'LiDAR 측정',
                      subtitle: 'iPhone/iPad Pro 전용',
                      accuracy: '±1%',
                      color: const Color(0xFF7C4DFF),
                      icon: Icons.radar,
                      features: const [
                        'LiDAR 센서 활용',
                        '3D 포인트 클라우드',
                        '높은 정확도 + 빠른 속도',
                      ],
                      onTap: () => _showNewProjectDialog(context, 'C'),
                    )
                  else
                    _ModeCard(
                      mode: 'C',
                      title: 'LiDAR 측정',
                      subtitle: 'iPhone/iPad Pro 전용',
                      accuracy: '±1%',
                      color: const Color(0xFF7C4DFF),
                      icon: Icons.radar,
                      features: const [
                        'LiDAR 센서 활용',
                        '3D 포인트 클라우드',
                        'iOS 기기에서만 사용 가능',
                      ],
                      disabled: true,
                      onTap: () {},
                    ),
                  const SizedBox(height: 100),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewProjectDialog(BuildContext context, String mode) {
    final nameCtrl = TextEditingController();
    final siteCtrl = TextEditingController();
    final addrCtrl = TextEditingController();

    final modeColors = {
      'A': const Color(0xFFFF6B35),
      'B': const Color(0xFF26C6DA),
      'C': const Color(0xFF7C4DFF),
    };
    final color = modeColors[mode]!;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          decoration: const BoxDecoration(
            color: Color(0xFF151926),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(mode, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 10),
                  const Text('New Project',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),
              _buildField(nameCtrl, 'Project Name', Icons.edit_outlined, 'e.g. Samsung Apt 105-301'),
              const SizedBox(height: 12),
              _buildField(siteCtrl, 'Site Name (optional)', Icons.business_outlined, 'e.g. Samsung Renovation'),
              const SizedBox(height: 12),
              _buildField(addrCtrl, 'Address (optional)', Icons.location_on_outlined, 'e.g. Seoul Gangnam-gu...'),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    Navigator.pop(ctx);

                    final site = siteCtrl.text.trim().isEmpty ? null : siteCtrl.text.trim();
                    final addr = addrCtrl.text.trim().isEmpty ? null : addrCtrl.text.trim();

                    Widget screen;
                    switch (mode) {
                      case 'A':
                        screen = ModeAScreen(projectName: name, siteName: site, address: addr);
                      case 'C':
                        screen = ModeCScreen(projectName: name, siteName: site, address: addr);
                      default:
                        screen = ModeBScreen(projectName: name, siteName: site, address: addr);
                    }

                    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Start Measurement', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, IconData icon, String hint) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5), fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.grey, size: 20),
        filled: true,
        fillColor: const Color(0xFF1E2235),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2A2F45))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2A2F45))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4FC3F7))),
      ),
    );
  }
}

/// 모드 카드 위젯
class _ModeCard extends StatelessWidget {
  final String mode;
  final String title;
  final String subtitle;
  final String accuracy;
  final Color color;
  final IconData icon;
  final List<String> features;
  final VoidCallback onTap;
  final bool disabled;

  const _ModeCard({
    required this.mode,
    required this.title,
    required this.subtitle,
    required this.accuracy,
    required this.color,
    required this.icon,
    required this.features,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = disabled ? Colors.grey : color;

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF151926),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: effectiveColor.withValues(alpha: disabled ? 0.1 : 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: effectiveColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: effectiveColor, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: effectiveColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(mode, style: TextStyle(color: effectiveColor, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          Text(title, style: TextStyle(color: disabled ? Colors.grey : Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: effectiveColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(accuracy, style: TextStyle(color: effectiveColor, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...features.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, size: 14, color: effectiveColor.withValues(alpha: 0.7)),
                      const SizedBox(width: 8),
                      Text(f, style: TextStyle(color: disabled ? Colors.grey : const Color(0xFFB0B8C8), fontSize: 13)),
                    ],
                  ),
                )),
            if (disabled)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('이 기기에서는 사용할 수 없습니다',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
