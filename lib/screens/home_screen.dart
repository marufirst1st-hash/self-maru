import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/measurement.dart';
import '../providers/app_provider.dart';
import '../utils/app_colors.dart';
import '../widgets/common_widgets.dart';
import '../widgets/floor_plan_painter.dart';
import 'scan_screen.dart';
import 'result_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().loadDemoProjects();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: AppColors.bgDark,
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                // Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [AppColors.primaryDark, AppColors.accent],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.square_foot, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Floor Measure', style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                                Text('Spatial Measurement', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                              ],
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: () {},
                              icon: const Icon(Icons.notifications_outlined, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Mode Selector
                        MeasurementModeSelector(
                          isSystemA: provider.selectedSystem == MeasurementSystem.systemA,
                          onChanged: (isA) {
                            provider.selectSystem(isA ? MeasurementSystem.systemA : MeasurementSystem.systemB);
                          },
                        ),
                        const SizedBox(height: 16),

                        // Quick Stats
                        Row(
                          children: [
                            Expanded(
                              child: StatCard(
                                label: 'Total Projects',
                                value: '${provider.projects.length}',
                                icon: Icons.folder_outlined,
                                iconColor: AppColors.info,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: StatCard(
                                label: 'Total Area',
                                value: provider.projects.fold<double>(0, (sum, p) => sum + (p.totalArea ?? 0)).toStringAsFixed(1),
                                unit: 'm\u00B2',
                                icon: Icons.straighten,
                                iconColor: AppColors.accent,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: StatCard(
                                label: 'Completed',
                                value: '${provider.projects.where((p) => p.status == MeasurementStatus.completed).length}',
                                icon: Icons.check_circle_outline,
                                iconColor: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Start Scan Button
                        _buildStartScanButton(context, provider),
                        const SizedBox(height: 24),

                        const Text(
                          'Recent Projects',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),

                // Project List
                provider.projects.isEmpty
                    ? SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(40),
                            child: Column(
                              children: [
                                Icon(Icons.folder_open, size: 64, color: AppColors.textMuted.withValues(alpha: 0.3)),
                                const SizedBox(height: 16),
                                const Text('No projects yet', style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
                                const SizedBox(height: 8),
                                const Text('Start a new scan to create your first project',
                                    style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildProjectCard(context, provider, provider.projects[index]),
                            childCount: provider.projects.length,
                          ),
                        ),
                      ),

                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStartScanButton(BuildContext context, AppProvider provider) {
    final isSystemA = provider.selectedSystem == MeasurementSystem.systemA;
    final color = isSystemA ? AppColors.systemA : AppColors.systemB;
    final label = isSystemA ? 'Start Marker Scan' : 'Start Quick Scan';
    final subtitle = isSystemA ? 'AprilTag precision measurement (\u00B11~2%)' : 'Walk around the room (\u00B13%)';
    final icon = isSystemA ? Icons.qr_code_scanner : Icons.directions_walk;

    return GestureDetector(
      onTap: () => _showNewProjectDialog(context, provider),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectCard(BuildContext context, AppProvider provider, MeasurementProject project) {
    final isCompleted = project.status == MeasurementStatus.completed;

    return GestureDetector(
      onTap: () {
        if (isCompleted && project.rooms.isNotEmpty) {
          provider.setActiveProject(project);
          Navigator.push(context, MaterialPageRoute(builder: (_) => ResultScreen(project: project)));
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.bgElevated),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SystemBadge(isSystemA: project.system == MeasurementSystem.systemA),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    project.name,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildStatusChip(project.status),
              ],
            ),
            if (project.address != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(project.address!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12), overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ],
            if (isCompleted && project.rooms.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 100,
                child: CustomPaint(
                  size: const Size(double.infinity, 100),
                  painter: FloorPlanPainter(
                    corners: project.rooms.first.corners,
                    showDimensions: false,
                    showArea: false,
                    lineColor: AppColors.accent.withValues(alpha: 0.5),
                    fillColor: AppColors.accent.withValues(alpha: 0.08),
                    cornerColor: AppColors.accent.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (project.totalArea != null && project.totalArea! > 0) ...[
                  const Icon(Icons.square_foot, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text('${project.totalArea!.toStringAsFixed(1)} m\u00B2', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(width: 16),
                ],
                const Icon(Icons.meeting_room_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text('${project.rooms.length} rooms', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const Spacer(),
                if (isCompleted)
                  const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(MeasurementStatus status) {
    Color color;
    String label;
    switch (status) {
      case MeasurementStatus.completed:
        color = AppColors.success;
        label = 'Done';
      case MeasurementStatus.scanning:
        color = AppColors.warning;
        label = 'Scanning';
      case MeasurementStatus.processing:
        color = AppColors.info;
        label = 'Processing';
      case MeasurementStatus.error:
        color = AppColors.error;
        label = 'Error';
      case MeasurementStatus.idle:
        color = AppColors.textMuted;
        label = 'Pending';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  void _showNewProjectDialog(BuildContext context, AppProvider provider) {
    final nameCtrl = TextEditingController();
    final siteCtrl = TextEditingController();
    final addrCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          decoration: const BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 20),
              const Text('New Project', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              _buildTextField(nameCtrl, 'Project Name', Icons.edit_outlined, 'e.g. Samsung Apt 105-301'),
              const SizedBox(height: 12),
              _buildTextField(siteCtrl, 'Site Name (optional)', Icons.business_outlined, 'e.g. Samsung Renovation'),
              const SizedBox(height: 12),
              _buildTextField(addrCtrl, 'Address (optional)', Icons.location_on_outlined, 'e.g. Seoul Gangnam-gu ...'),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    provider.startNewProject(name, siteName: siteCtrl.text.trim().isEmpty ? null : siteCtrl.text.trim(), address: addrCtrl.text.trim().isEmpty ? null : addrCtrl.text.trim());
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
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

  Widget _buildTextField(TextEditingController ctrl, String label, IconData icon, String hint) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
        filled: true,
        fillColor: AppColors.bgCard,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.bgElevated)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.bgElevated)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent)),
      ),
    );
  }
}
