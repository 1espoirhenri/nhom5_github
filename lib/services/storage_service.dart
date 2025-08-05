import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/health_data.dart';

class StorageService {
  static const _storageKey = 'offline_health_data';

  // Lưu một bản ghi HealthData vào danh sách chờ
  static Future<void> saveHealthData(HealthData data) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Lấy danh sách hiện có
    final List<String> dataList = prefs.getStringList(_storageKey) ?? [];
    
    // Thêm bản ghi mới (dưới dạng chuỗi JSON)
    dataList.add(jsonEncode(data.toJson()));
    
    // Lưu lại danh sách
    await prefs.setStringList(_storageKey, dataList);
  }

  // Lấy tất cả dữ liệu đang chờ và xóa chúng khỏi bộ nhớ
  static Future<List<HealthData>> getAndClearAllHealthData() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> dataList = prefs.getStringList(_storageKey) ?? [];
    
    if (dataList.isEmpty) {
      return [];
    }

    // Chuyển đổi chuỗi JSON trở lại thành đối tượng HealthData
    final List<HealthData> healthDataObjects = dataList
        .map((jsonString) => HealthData.fromJson(jsonDecode(jsonString)))
        .toList();

    // Xóa dữ liệu đã lấy
    await prefs.remove(_storageKey);
    
    return healthDataObjects;
  }
}