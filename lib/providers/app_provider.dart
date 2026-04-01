import 'package:flutter/foundation.dart';
import '../models/measurement.dart';
import '../models/material_calc.dart';

class AppProvider extends ChangeNotifier {
  // Navigation
  int _currentIndex = 0;
  int get currentIndex => _currentIndex;

  void setCurrentIndex(int index) {
    _currentIndex = index;
    notifyListeners();
  }

  // Projects
  final List<MeasurementProject> _projects = [];
  List<MeasurementProject> get projects => List.unmodifiable(_projects);

  MeasurementProject? _activeProject;
  MeasurementProject? get activeProject => _activeProject;

  // Measurement state
  MeasurementSystem _selectedSystem = MeasurementSystem.systemA;
  MeasurementSystem get selectedSystem => _selectedSystem;

  MeasurementStatus _measurementStatus = MeasurementStatus.idle;
  MeasurementStatus get measurementStatus => _measurementStatus;

  // System A state
  final List<Marker> _detectedMarkers = [];
  List<Marker> get detectedMarkers => List.unmodifiable(_detectedMarkers);

  // System B state
  double _scanProgress = 0.0;
  double get scanProgress => _scanProgress;

  int _layerActive = 1;
  int get layerActive => _layerActive;

  double _confidenceLevel = 0.0;
  double get confidenceLevel => _confidenceLevel;

  // Current scan data
  final List<Corner> _detectedCorners = [];
  List<Corner> get detectedCorners => List.unmodifiable(_detectedCorners);

  double _currentArea = 0.0;
  double get currentArea => _currentArea;

  double _currentPerimeter = 0.0;
  double get currentPerimeter => _currentPerimeter;

  // Material calculation
  FloorMaterial? _selectedMaterial;
  FloorMaterial? get selectedMaterial => _selectedMaterial;

  void selectSystem(MeasurementSystem system) {
    _selectedSystem = system;
    notifyListeners();
  }

  void startNewProject(String name, {String? siteName, String? address}) {
    final project = MeasurementProject(
      name: name,
      siteName: siteName,
      address: address,
      system: _selectedSystem,
      status: MeasurementStatus.idle,
    );
    _projects.insert(0, project);
    _activeProject = project;
    _resetScanState();
    notifyListeners();
  }

  void setActiveProject(MeasurementProject project) {
    _activeProject = project;
    notifyListeners();
  }

  void deleteProject(String id) {
    _projects.removeWhere((p) => p.id == id);
    if (_activeProject?.id == id) {
      _activeProject = null;
    }
    notifyListeners();
  }

  // Scanning
  void startScanning() {
    _measurementStatus = MeasurementStatus.scanning;
    _scanProgress = 0.0;
    _confidenceLevel = 0.0;
    _layerActive = 1;
    notifyListeners();
  }

  void updateScanProgress(double progress) {
    _scanProgress = progress.clamp(0.0, 1.0);
    _layerActive = progress < 0.25 ? 1 : progress < 0.5 ? 2 : progress < 0.75 ? 3 : 4;
    _confidenceLevel = (progress * 100).clamp(0.0, 99.0);
    notifyListeners();
  }

  void addDetectedCorner(Corner corner) {
    _detectedCorners.add(corner);
    _recalculate();
    notifyListeners();
  }

  void addDetectedMarker(Marker marker) {
    _detectedMarkers.add(marker);
    notifyListeners();
  }

  void completeScan() {
    _measurementStatus = MeasurementStatus.completed;
    _scanProgress = 1.0;
    _confidenceLevel = 95.0 + (5.0 * _detectedCorners.length / 10).clamp(0.0, 5.0);

    if (_activeProject != null && _detectedCorners.isNotEmpty) {
      final walls = <Wall>[];
      for (int i = 0; i < _detectedCorners.length; i++) {
        final j = (i + 1) % _detectedCorners.length;
        walls.add(Wall(start: _detectedCorners[i], end: _detectedCorners[j]));
      }

      final floorPlan = FloorPlan(
        name: '${_activeProject!.name} - Room ${_activeProject!.rooms.length + 1}',
        corners: List.from(_detectedCorners),
        walls: walls,
        area: _currentArea,
        perimeter: _currentPerimeter,
      );

      _activeProject = _activeProject!.copyWith(
        status: MeasurementStatus.completed,
        rooms: [..._activeProject!.rooms, floorPlan],
        totalArea: (_activeProject!.totalArea ?? 0) + _currentArea,
      );

      final idx = _projects.indexWhere((p) => p.id == _activeProject!.id);
      if (idx >= 0) {
        _projects[idx] = _activeProject!;
      }
    }
    notifyListeners();
  }

  void cancelScan() {
    _measurementStatus = MeasurementStatus.idle;
    _resetScanState();
    notifyListeners();
  }

  void _resetScanState() {
    _scanProgress = 0.0;
    _confidenceLevel = 0.0;
    _layerActive = 1;
    _detectedCorners.clear();
    _detectedMarkers.clear();
    _currentArea = 0.0;
    _currentPerimeter = 0.0;
  }

  void _recalculate() {
    if (_detectedCorners.length < 3) {
      _currentArea = 0;
      _currentPerimeter = 0;
      return;
    }
    // Shoelace formula
    double area = 0;
    double perimeter = 0;
    for (int i = 0; i < _detectedCorners.length; i++) {
      final j = (i + 1) % _detectedCorners.length;
      final pi = _detectedCorners[i].position;
      final pj = _detectedCorners[j].position;
      area += pi.x * pj.y - pj.x * pi.y;
      perimeter += pi.distanceTo(pj);
    }
    _currentArea = area.abs() / 2.0;
    _currentPerimeter = perimeter;
  }

  // Material
  void selectMaterial(FloorMaterial material) {
    _selectedMaterial = material;
    notifyListeners();
  }

  MaterialEstimate? getEstimate(double area) {
    if (_selectedMaterial == null) return null;
    return MaterialEstimate(material: _selectedMaterial!, areaM2: area);
  }

  // Demo data
  void loadDemoProjects() {
    if (_projects.isNotEmpty) return;

    final demoCorners = [
      Corner(position: const Point3D(x: 0, y: 0), confidence: 97),
      Corner(position: const Point3D(x: 5.2, y: 0), confidence: 96),
      Corner(position: const Point3D(x: 5.2, y: 4.1), confidence: 95),
      Corner(position: const Point3D(x: 0, y: 4.1), confidence: 98),
    ];
    final demoWalls = <Wall>[];
    for (int i = 0; i < demoCorners.length; i++) {
      final j = (i + 1) % demoCorners.length;
      demoWalls.add(Wall(start: demoCorners[i], end: demoCorners[j]));
    }

    final demoCorners2 = [
      Corner(position: const Point3D(x: 0, y: 0), confidence: 94),
      Corner(position: const Point3D(x: 3.8, y: 0), confidence: 93),
      Corner(position: const Point3D(x: 3.8, y: 3.2), confidence: 92),
      Corner(position: const Point3D(x: 0, y: 3.2), confidence: 95),
    ];
    final demoWalls2 = <Wall>[];
    for (int i = 0; i < demoCorners2.length; i++) {
      final j = (i + 1) % demoCorners2.length;
      demoWalls2.add(Wall(start: demoCorners2[i], end: demoCorners2[j]));
    }

    final lCorners = [
      Corner(position: const Point3D(x: 0, y: 0), confidence: 96),
      Corner(position: const Point3D(x: 6.0, y: 0), confidence: 95),
      Corner(position: const Point3D(x: 6.0, y: 2.5), confidence: 94),
      Corner(position: const Point3D(x: 3.0, y: 2.5), confidence: 93),
      Corner(position: const Point3D(x: 3.0, y: 5.0), confidence: 95),
      Corner(position: const Point3D(x: 0, y: 5.0), confidence: 97),
    ];
    final lWalls = <Wall>[];
    for (int i = 0; i < lCorners.length; i++) {
      final j = (i + 1) % lCorners.length;
      lWalls.add(Wall(start: lCorners[i], end: lCorners[j]));
    }

    _projects.addAll([
      MeasurementProject(
        name: 'Samsung Apt 105-301',
        siteName: 'Samsung Renovation',
        address: 'Seoul Gangnam-gu Samsung-dong 105-301',
        system: MeasurementSystem.systemA,
        status: MeasurementStatus.completed,
        rooms: [
          FloorPlan(name: 'Living Room', corners: demoCorners, walls: demoWalls, area: 21.32, perimeter: 18.6),
          FloorPlan(name: 'Master Bedroom', corners: demoCorners2, walls: demoWalls2, area: 12.16, perimeter: 14.0),
        ],
        totalArea: 33.48,
      ),
      MeasurementProject(
        name: 'Lotte Castle B-1204',
        siteName: 'Lotte Castle Remodel',
        address: 'Seoul Songpa-gu Jamsil-dong B-1204',
        system: MeasurementSystem.systemB,
        status: MeasurementStatus.completed,
        rooms: [
          FloorPlan(name: 'L-Shaped Hall', corners: lCorners, walls: lWalls, area: 22.5, perimeter: 23.0),
        ],
        totalArea: 22.5,
      ),
      MeasurementProject(
        name: 'Hyundai Apt 203-502',
        siteName: 'Hyundai Apt Flooring',
        address: 'Seoul Seocho-gu Banpo-dong 203-502',
        system: MeasurementSystem.systemA,
        status: MeasurementStatus.idle,
        totalArea: 0,
      ),
    ]);
    notifyListeners();
  }
}
