class PatientInfo {
  final String maBenhNhan;
  final String hoVaTen;
  final int namSinh;
  final String idPi;

  PatientInfo({
    required this.maBenhNhan,
    required this.hoVaTen,
    required this.namSinh,
    required this.idPi,
  });

  factory PatientInfo.fromJson(Map<String, dynamic> json) {
    return PatientInfo(
      maBenhNhan: json['MaBenhNhan'] as String? ?? 'N/A',
      hoVaTen: json['HoVaTen'] as String? ?? 'Không rõ tên',
      namSinh: json['NamSinh'] as int? ?? 0,
      idPi: json['IDPi'] as String? ?? 'N/A',
    );
  }
}