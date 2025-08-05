import 'package:mysql1/mysql1.dart';
import '../models/health_data.dart'; // Đảm bảo model HealthData đã được cập nhật

class ApiService {
  // --- CẤU HÌNH KẾT NỐI DATABASE ---
  // !!! THAY THẾ BẰNG ĐỊA CHỈ IP CỦA RASPBERRY PI TRONG MẠNG CỦA BẠN !!!
  static const String _host = 'YOUR_RASP_PI_IP_ADDRESS'; // VÍ DỤ: điền IP của Pi vào đây
  static const int _port = 3306;
  static const String _dbName = 'YOUR_DB_NAME_ON_PI';
  static const String _user = 'YOUR_DB_USER_NAME';      // Tên người dùng DB
  static const String _password = 'YOUR_DB_USER_PASSWORD';  // Mật khẩu DB

  // Hàm helper để tạo và mở kết nối
  static Future<MySqlConnection> _getConnection() async {
    final settings = ConnectionSettings(
      host: _host,
      port: _port,
      db: _dbName,
      user: _user,
      password: _password,
      timeout: const Duration(seconds: 10), // Tăng timeout để kết nối ổn định hơn
    );
    return await MySqlConnection.connect(settings);
  }

  /// Kiểm tra kết nối đến cơ sở dữ liệu.
  static Future<bool> checkDatabaseConnection() async {
    MySqlConnection? conn;
    try {
      conn = await _getConnection();
      await conn.query('SELECT 1');
      print("Kiem tra ket noi database thanh cong.");
      return true;
    } catch (e) {
      print('Khong the ket noi den database: $e');
      return false;
    } finally {
      await conn?.close();
    }
  }

  /// Lấy chỉ số mới nhất của một bệnh nhân cụ thể cho chatbot.
  static Future<HealthData?> getLatestVitals(String patientId) async {
    MySqlConnection? conn;
    try {
      conn = await _getConnection();
      // Câu lệnh SQL JOIN lấy tất cả các trường cần thiết với alias (AS)
      // để khớp chính xác với key trong hàm fromJson của model HealthData
      final results = await conn.query(
        '''
        SELECT
            bn.IDPi AS id_pi,
            cs.MaBenhNhan AS ma_benh_nhan,
            bn.HoVaTen AS ho_va_ten,
            bn.NamSinh AS nam_sinh,
            cs.NhietDo AS nhietdo,
            cs.NhipTim AS nhip_tim,
            cs.SPO2 AS spo2,
            cs.ThoiGianDo AS thoi_gian_do
        FROM ChiSo AS cs
        JOIN BenhNhan AS bn ON cs.MaBenhNhan = bn.MaBenhNhan
        WHERE cs.MaBenhNhan = ?
        ORDER BY cs.ThoiGianDo DESC
        LIMIT 1
        ''',
        [patientId],
      );

      if (results.isNotEmpty) {
        // results.first.fields là một Map<String, dynamic>
        return HealthData.fromJson(results.first.fields);
      }
      return null; // Trả về null nếu không tìm thấy bệnh nhân
    } catch (e) {
      print('Lỗi khi lấy chỉ số mới nhất: $e');
      return null;
    } finally {
      await conn?.close();
    }
  }

  /// Lấy danh sách tất cả dữ liệu đo được của các bệnh nhân thuộc một Pi.
  /// (Dùng cho màn hình chính hoặc các tính năng khác)
  static Future<List<HealthData>> getAllPatientDataByRpId(String rpId) async {
    MySqlConnection? conn;
    try {
      conn = await _getConnection();
      final results = await conn.query(
        '''
        SELECT
            bn.IDPi AS id_pi,
            cs.MaBenhNhan AS ma_benh_nhan,
            bn.HoVaTen AS ho_va_ten,
            bn.NamSinh AS nam_sinh,
            cs.NhietDo AS nhietdo,
            cs.NhipTim AS nhip_tim,
            cs.SPO2 AS spo2,
            cs.ThoiGianDo AS thoi_gian_do
        FROM ChiSo AS cs
        JOIN BenhNhan AS bn ON cs.MaBenhNhan = bn.MaBenhNhan
        WHERE bn.IDPi = ?
        ORDER BY cs.ThoiGianDo DESC
        ''',
        [rpId],
      );
      // Chuyển đổi mỗi hàng kết quả thành một đối tượng HealthData
      return results.map((row) => HealthData.fromJson(row.fields)).toList();
    } catch (e) {
      print('Lỗi khi lấy danh sách dữ liệu: $e');
      return []; // Trả về danh sách rỗng nếu có lỗi
    } finally {
      await conn?.close();
    }
  }

  /// Gửi dữ liệu đo được từ thiết bị (ví dụ: Bluetooth) lên database.
  static Future<bool> sendHealthData(HealthData data) async {
    MySqlConnection? conn;
    try {
      conn = await _getConnection();
      await conn.query(
        'INSERT INTO ChiSo (MaBenhNhan, NhietDo, NhipTim, SPO2, ThoiGianDo) VALUES (?, ?, ?, ?, ?)',
        [
          data.maBenhNhan, // Dùng đúng thuộc tính từ model
          data.nhietdo,
          data.nhipTim,
          data.spo2,
          DateTime.parse(data.thoiGianDo),
        ],
      );
      print("Gửi dữ liệu thành công cho bệnh nhân: ${data.maBenhNhan}");
      return true;
    } catch (e) {
      print('Lỗi khi gửi dữ liệu: $e');
      return false;
    } finally {
      await conn?.close();
    }
  }

}
