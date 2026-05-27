class AdbDevice {
  const AdbDevice({
    required this.id,
    required this.status,
    this.model,
    this.product,
    this.transportId,
  });

  final String id;
  final String status;
  final String? model;
  final String? product;
  final String? transportId;

  bool get isOnline => status == 'device';

  String get displayName {
    if (model != null && model!.isNotEmpty) {
      return model!.replaceAll('_', ' ');
    }
    return id;
  }
}
