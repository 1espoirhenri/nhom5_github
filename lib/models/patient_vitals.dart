class PatientVitals {
  final String maBenhNhan;
  final String hoVaTen;
  final int namSinh;
  final String idPi;
  // Giả định API trả về các trường này, bạn có thể thêm/bớt nếu cần
  final double? nhietdo;
  final int? nhipTim;
  final int? spo2;
  final String? thoiGianDo;

  PatientVitals({
    required this.maBenhNhan,
    required this.hoVaTen,
    required this.namSinh,
    required this.idPi,
    this.nhietdo,
    this.nhipTim,
    this.spo2,
    this.thoiGianDo,
  });

  factory PatientVitals.fromJson(Map<String, dynamic> json) {
    return PatientVitals(
      maBenhNhan: json['MaBenhNhan'] as String? ?? 'N/A',
      hoVaTen: json['HoVaTen'] as String? ?? 'Không rõ tên',
      namSinh: json['NamSinh'] as int? ?? 0,
      idPi: json['IDPi'] as String? ?? 'N/A',
      nhietdo: (json['nhietdo'] as num?)?.toDouble(),
      nhipTim: json['nhip_tim'] as int?,
      spo2: json['spo2'] as int?,
      thoiGianDo: json['thoi_gian_do'] as String?,
    );
  }
}