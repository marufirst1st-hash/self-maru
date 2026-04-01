import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData icon;
  final Color? iconColor;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    required this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.bgElevated, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor ?? AppColors.accent, size: 20),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(unit!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class SystemBadge extends StatelessWidget {
  final bool isSystemA;
  final bool isLarge;

  const SystemBadge({super.key, required this.isSystemA, this.isLarge = false});

  @override
  Widget build(BuildContext context) {
    final color = isSystemA ? AppColors.systemA : AppColors.systemB;
    final text = isSystemA ? 'A' : 'B';
    final label = isSystemA ? 'Marker' : 'Quick';
    final size = isLarge ? 36.0 : 24.0;
    final fontSize = isLarge ? 14.0 : 10.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(size / 4),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Center(
            child: Text(text, style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.bold)),
          ),
        ),
        if (isLarge) ...[
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}

class LayerIndicator extends StatelessWidget {
  final int activeLayer;
  final double confidence;

  const LayerIndicator({super.key, required this.activeLayer, required this.confidence});

  @override
  Widget build(BuildContext context) {
    final layers = [
      ('L1', 'AR Base', Icons.view_in_ar),
      ('L2', 'PDR', Icons.directions_walk),
      ('L3', 'Flash', Icons.flash_on),
      ('L4', 'Corner', Icons.crop_square),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.bgElevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('4-Layer Engine', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${confidence.toStringAsFixed(1)}%', style: const TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(4, (i) {
              final isActive = i < activeLayer;
              final isCurrent = i == activeLayer - 1;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                  child: Column(
                    children: [
                      Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? AppColors.accent.withValues(alpha: 0.2)
                              : isActive
                                  ? AppColors.accent.withValues(alpha: 0.1)
                                  : AppColors.bgSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isCurrent ? AppColors.accent : isActive ? AppColors.accent.withValues(alpha: 0.3) : Colors.transparent,
                            width: isCurrent ? 1.5 : 1,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            layers[i].$3,
                            size: 16,
                            color: isCurrent ? AppColors.accent : isActive ? AppColors.accent.withValues(alpha: 0.6) : AppColors.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        layers[i].$1,
                        style: TextStyle(
                          color: isCurrent ? AppColors.accent : AppColors.textMuted,
                          fontSize: 9,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class MeasurementModeSelector extends StatelessWidget {
  final bool isSystemA;
  final ValueChanged<bool> onChanged;

  const MeasurementModeSelector({super.key, required this.isSystemA, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.bgElevated),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isSystemA ? AppColors.systemA.withValues(alpha: 0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  border: isSystemA ? Border.all(color: AppColors.systemA.withValues(alpha: 0.5)) : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_2, size: 16, color: isSystemA ? AppColors.systemA : AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      'Marker Precision',
                      style: TextStyle(
                        color: isSystemA ? AppColors.systemALight : AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: isSystemA ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: !isSystemA ? AppColors.systemB.withValues(alpha: 0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  border: !isSystemA ? Border.all(color: AppColors.systemB.withValues(alpha: 0.5)) : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.directions_walk, size: 16, color: !isSystemA ? AppColors.systemB : AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      'Quick Scan',
                      style: TextStyle(
                        color: !isSystemA ? AppColors.systemBLight : AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: !isSystemA ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
