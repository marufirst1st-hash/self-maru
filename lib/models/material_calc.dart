class FloorMaterial {
  final String id;
  final String name;
  final String category;
  final double widthM;
  final double lengthM;
  final double pricePerUnit;
  final String unit;
  final double wasteFactor;

  const FloorMaterial({
    required this.id,
    required this.name,
    required this.category,
    required this.widthM,
    required this.lengthM,
    required this.pricePerUnit,
    this.unit = 'm2',
    this.wasteFactor = 0.1,
  });
}

class MaterialEstimate {
  final FloorMaterial material;
  final double areaM2;
  final double requiredQuantity;
  final double wasteQuantity;
  final double totalQuantity;
  final double totalCost;

  MaterialEstimate({
    required this.material,
    required this.areaM2,
  }) : requiredQuantity = areaM2,
       wasteQuantity = areaM2 * material.wasteFactor,
       totalQuantity = areaM2 * (1 + material.wasteFactor),
       totalCost = areaM2 * (1 + material.wasteFactor) * material.pricePerUnit;
}

class DefaultMaterials {
  static const List<FloorMaterial> all = [
    FloorMaterial(
      id: 'lvt_standard',
      name: 'LVT Standard',
      category: 'LVT',
      widthM: 0.15,
      lengthM: 0.9,
      pricePerUnit: 25000,
      wasteFactor: 0.08,
    ),
    FloorMaterial(
      id: 'lvt_premium',
      name: 'LVT Premium',
      category: 'LVT',
      widthM: 0.18,
      lengthM: 1.2,
      pricePerUnit: 45000,
      wasteFactor: 0.08,
    ),
    FloorMaterial(
      id: 'laminate_8mm',
      name: 'Laminate 8mm',
      category: 'Laminate',
      widthM: 0.19,
      lengthM: 1.38,
      pricePerUnit: 18000,
      wasteFactor: 0.10,
    ),
    FloorMaterial(
      id: 'engineered_wood',
      name: 'Engineered Wood',
      category: 'Wood',
      widthM: 0.15,
      lengthM: 1.2,
      pricePerUnit: 65000,
      wasteFactor: 0.12,
    ),
    FloorMaterial(
      id: 'vinyl_sheet',
      name: 'Vinyl Sheet',
      category: 'Vinyl',
      widthM: 2.0,
      lengthM: 1.0,
      pricePerUnit: 15000,
      wasteFactor: 0.05,
    ),
    FloorMaterial(
      id: 'carpet_tile',
      name: 'Carpet Tile',
      category: 'Carpet',
      widthM: 0.5,
      lengthM: 0.5,
      pricePerUnit: 12000,
      wasteFactor: 0.07,
    ),
  ];
}
