// File: lib/models/health_data.dart

class HealthData {
  final String idPi;
  final String maBenhNhan;
  final String hoVaTen;
  final int namSinh;
  final double nhietdo;
  final int nhipTim;
  final int spo2;
  final String thoiGianDo;

  HealthData({
    required this.idPi,
    required this.maBenhNhan,
    required this.hoVaTen,
    required this.namSinh,
    required this.nhietdo,
    required this.nhipTim,
    required this.spo2,
    required this.thoiGianDo,
  });

  // --- HÀM fromJson ĐÃ ĐƯỢC SỬA LẠI ---
  factory HealthData.fromJson(Map<String, dynamic> json) {
    return HealthData(
      // Sử dụng .toString() để chuyển đổi an toàn, tránh lỗi ép kiểu
      idPi: json['id_pi']?.toString() ?? 'N/A',
      maBenhNhan: json['ma_benh_nhan']?.toString() ?? 'N/A',
      hoVaTen: json['ho_va_ten']?.toString() ?? 'Không rõ tên',

      // Các kiểu số và ngày tháng giữ nguyên cách xử lý an toàn
      namSinh: json['nam_sinh'] as int? ?? 0,
      nhietdo: (json['nhietdo'] as num? ?? 0).toDouble(),
      nhipTim: json['nhip_tim'] as int? ?? 0,
      spo2: json['spo2'] as int? ?? 0,
      thoiGianDo: (json['thoi_gian_do'] ?? DateTime(0)).toString(),
    );
  }

  // Hàm toJson để đảm bảo tính nhất quán
  Map<String, dynamic> toJson() {
    return {
      'id_pi': idPi,
      'ma_benh_nhan': maBenhNhan,
      'ho_va_ten': hoVaTen,
      'nam_sinh': namSinh,
      'nhietdo': nhietdo,
      'nhip_tim': nhipTim,
      'spo2': spo2,
      'thoi_gian_do': thoiGianDo,
    };
  }
}