import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../api/api_service.dart';
import '../models/health_data.dart';
import '../services/storage_service.dart';
import '../services/bluetooth_service.dart';
import 'chatbot_screen.dart';

class HomeScreen extends StatefulWidget {
  final String rpId;
  const HomeScreen({super.key, required this.rpId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<HealthData>? _healthData;
  bool _isLoading = true;
  final BluetoothService _bluetoothService = BluetoothService();

  @override
  void initState() {
    super.initState();
    _initialize();
    _bluetoothService.newDataNotifier.addListener(_onNewDataReceived);
  }

  // --- HÀM LẮNG NGHE ĐÃ SỬA ---
  void _onNewDataReceived() {
    final newData = _bluetoothService.newDataNotifier.value;
    if (newData != null) {
      // Nếu có dữ liệu mới (offline), thêm ngay vào đầu danh sách
      print("HomeScreen: Hien thi ngay du lieu offline.");
      setState(() {
        _healthData?.insert(0, newData);
      });
    } else {
      // Nếu tín hiệu là null (online), tải lại toàn bộ từ DB
      print("HomeScreen: Tai lai du lieu tu database.");
      _refreshData();
    }
  }

  Future<void> _initialize() async {
    await _requestPermissions();
    _bluetoothService.startScanAndConnect();
    _refreshData();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
  }

  @override
  void dispose() {
    _bluetoothService.newDataNotifier.removeListener(_onNewDataReceived);
    _bluetoothService.disconnect();
    super.dispose();
  }

  Future<void> _refreshData() async {
    setStateIfMounted(() => _isLoading = true);
    await _syncOfflineData();
    final data = await ApiService.getAllPatientDataByRpId(widget.rpId);
    setStateIfMounted(() {
      _healthData = data;
      _isLoading = false;
    });
  }

  // Helper để tránh lỗi setState sau khi dispose
  void setStateIfMounted(f) {
    if (mounted) setState(f);
  }

  Future<void> _syncOfflineData() async {
    final offlineData = await StorageService.getAndClearAllHealthData();
    if (offlineData.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đang đồng bộ ${offlineData.length} bản ghi...')),
      );

      int successCount = 0;
      for (var data in offlineData) {
        if (await ApiService.sendHealthData(data)) successCount++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đồng bộ thành công $successCount/${offlineData.length} bản ghi.')),
        );
      }
    }
  }

  // --- CODE HOÀN CHỈNH CHO _buildBluetoothStatus ---
  Widget _buildBluetoothStatus() {
    return ValueListenableBuilder<String>(
      valueListenable: _bluetoothService.connectionStatus,
      builder: (context, status, child) {
        IconData icon;
        Color color;
        switch (status) {
          case "Đã kết nối":
          case "Đã kết nối, chờ dữ liệu...":
            icon = Icons.bluetooth_connected;
            color = Colors.lightBlueAccent;
            break;
          case "Đang kết nối...":
          case "Đang quét...":
          case "Đã tìm thấy thiết bị...":
            icon = Icons.bluetooth_searching;
            color = Colors.orangeAccent;
            break;
          default: // Đã ngắt kết nối, Không tìm thấy, Thất bại
            icon = Icons.bluetooth_disabled;
            color = Colors.grey;
        }
        return Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 4),
              Text(status, style: const TextStyle(fontSize: 12)),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dữ liệu sức khỏe'),
        actions: [
          _buildBluetoothStatus(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _healthData == null || _healthData!.isEmpty
          ? const Center(child: Text('Không có dữ liệu'))
          : ListView.builder(
        itemCount: _healthData!.length,
        itemBuilder: (context, index) {
          final data = _healthData![index];
          return ListTile(
              title: Text('Bệnh nhân: ${data.maBenhNhan}'),
            subtitle: Text('Thời gian: ${data.thoiGianDo}'),
            trailing: Text(
                '❤️ ${data.nhipTim} | 🌡️ ${data.nhietdo}°C | O₂ ${data.spo2}%'),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ChatbotScreen()),
          );
        },
        child: const Icon(Icons.chat),
      ),
    );
  }
}