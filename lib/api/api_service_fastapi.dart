import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/patient_info.dart';
import '../models/patient_vitals.dart';

class ApiServiceNurse {
  // Đảm bảo đây là địa chỉ server FastAPI của bạn
  static const String _baseUrl = "YOUR_FASTAPI_URL_SERVER";

  /// Lấy danh sách ID của tất cả Raspberry Pi đang hoạt động
  static Future<List<String>?> getAllRaspberryIds() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/pis/')).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        List<dynamic> body = jsonDecode(utf8.decode(response.bodyBytes));
        // Đảm bảo mỗi ID là một chuỗi và không rỗng
        return body.map((dynamic item) => item['IDPi'].toString()).where((id) => id.isNotEmpty).toList();
      }
      return [];
    } catch (e) {
      print("Lỗi khi lấy danh sách Raspberry Pi: $e");
      return null;
    }
  }

  /// Lấy danh sách bệnh nhân từ một Pi cụ thể
  static Future<List<PatientInfo>?> getPatientsByRaspberryId(String rpId) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/pis/$rpId/patients/')).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        List<dynamic> body = jsonDecode(utf8.decode(response.bodyBytes));
        return body.map((dynamic item) => PatientInfo.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      print("Lỗi khi lấy danh sách bệnh nhân từ $rpId: $e");
      return null;
    }
  }

  /// Lấy danh sách TẤT CẢ bệnh nhân trong toàn hệ thống
  static Future<List<PatientInfo>?> getAllPatients() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/patients/all')).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        List<dynamic> body = jsonDecode(utf8.decode(response.bodyBytes));
        return body.map((dynamic item) => PatientInfo.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      print("Lỗi khi lấy tất cả bệnh nhân: $e");
      return null;
    }
  }

  static Future<bool> renamePatient(String patientId, String newName) async {
    try {
      // Giả sử server có endpoint PUT là /patients/{patient_id}/rename
      final url = Uri.parse('$_baseUrl/patients/$patientId/rename');
      final response = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'HoVaTen': newName}),
      ).timeout(const Duration(seconds: 15));

      // Nếu server trả về 200 OK, nghĩa là thành công
      return response.statusCode == 200;
    } catch (e) {
      print("Lỗi khi đổi tên bệnh nhân $patientId: $e");
      return false;
    }
  }

  /// Lấy dữ liệu chi tiết và chỉ số của một bệnh nhân cụ thể
  static Future<PatientVitals?> getVitalsForPatient(String patientId) async {
    try {
      // SỬA LỖI: Cập nhật endpoint để khớp với tài liệu API của bạn
      final url = Uri.parse('$_baseUrl/lookup/patient/$patientId');

      print("Đang gọi API: $url"); // Thêm dòng log để kiểm tra

      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return PatientVitals.fromJson(data);
      } else {
        print("Lỗi server khi lấy chỉ số cho BN $patientId: ${response.statusCode} ${response.body}");
        return null;
      }
    } catch (e) {
      print("Lỗi kết nối khi lấy dữ liệu chi tiết cho $patientId: $e");
      return null;
    }
  }

}
