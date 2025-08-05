import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../api/api_service.dart';
import 'storage_service.dart';
import '../models/health_data.dart';

class BluetoothService {
  static const String ESP32_DEVICE_NAME = "ESP32-Health-Monitor";

  BluetoothConnection? _connection;
  StreamSubscription<BluetoothDiscoveryResult>? _discoveryStreamSubscription;
  bool _isConnecting = false;
  Timer? _reconnectTimer;

  final ValueNotifier<String> connectionStatus = ValueNotifier("Đã ngắt kết nối");
  // SỬA LẠI: Notifier sẽ gửi đi đối tượng HealthData mới
  final ValueNotifier<HealthData?> newDataNotifier = ValueNotifier(null);

  String _buffer = '';

  Future<void> startScanAndConnect() async {
    if (_isConnecting || (_connection?.isConnected ?? false)) {
      return;
    }
    _isConnecting = true;
    connectionStatus.value = "Đang quét...";

    _discoveryStreamSubscription = FlutterBluetoothSerial.instance.startDiscovery().listen((result) {
      if (result.device.name == ESP32_DEVICE_NAME) {
        connectionStatus.value = "Đã tìm thấy thiết bị...";
        _discoveryStreamSubscription?.cancel();
        _connectToDevice(result.device);
      }
    });

    _discoveryStreamSubscription?.onDone(() {
      if (_isConnecting) {
        _isConnecting = false;
        connectionStatus.value = "Không tìm thấy thiết bị";
        _scheduleReconnect();
      }
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    connectionStatus.value = "Đang kết nối...";
    try {
      _connection = await BluetoothConnection.toAddress(device.address);
      connectionStatus.value = "Đã kết nối, chờ dữ liệu...";
      _isConnecting = false;
      _reconnectTimer?.cancel();

      _connection?.input?.listen((Uint8List data) {
        _buffer += utf8.decode(data);
        while (_buffer.contains('\n')) {
          int newlineIndex = _buffer.indexOf('\n');
          String jsonString = _buffer.substring(0, newlineIndex).trim();
          _buffer = _buffer.substring(newlineIndex + 1);
          if (jsonString.isNotEmpty) {
            _onDataReceived(jsonString);
          }
        }
      }).onDone(() {
        connectionStatus.value = "Đã ngắt kết nối";
        _connection = null;
        _scheduleReconnect();
      });

    } catch (exception) {
      connectionStatus.value = "Kết nối thất bại";
      _isConnecting = false;
      _scheduleReconnect();
    }
  }

  void _onDataReceived(String jsonString) async {
    print("Nhan duoc du lieu tu ESP32: $jsonString");

    try {
      var jsonData = jsonDecode(jsonString) as Map<String, dynamic>;

      HealthData healthData = HealthData(
        idPi: jsonData['idpi'] as String,
        maBenhNhan: jsonData['id_patient'] as String,
        hoVaTen: jsonData['hoVaTen'] as String,
        namSinh: jsonData['namsinh'] as int,
        nhietdo: (jsonData['nhietdo'] as num).toDouble(),
        nhipTim: jsonData['nhip_tim'] as int,
        spo2: jsonData['spo2'] as int,
        thoiGianDo: DateTime.now().toUtc().toIso8601String(),
      );

      var connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult.contains(ConnectivityResult.wifi)) {
        print("Co WiFi. Dang gui du lieu len server...");
        bool success = await ApiService.sendHealthData(healthData);
        if(success) {
          print("Gui du lieu thanh cong.");
          // Thông báo cho UI để tải lại từ DB
          newDataNotifier.value = null; // Gửi tín hiệu refresh
        } else {
          print("Gui du lieu that bai.");
        }
      } else {
        print("Khong co WiFi. Dang luu du lieu vao bo nho tam...");
        await StorageService.saveHealthData(healthData);
        print("Da luu du lieu vao bo nho tam.");
        // Thông báo cho UI để cập nhật ngay lập tức
        newDataNotifier.value = healthData;
      }

    } catch (e) {
      print("Loi xu ly du lieu tu ESP32: $e");
    }
  }

  void _scheduleReconnect() {
    print("Len lich ket noi lai sau 10 giay...");
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      startScanAndConnect();
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _discoveryStreamSubscription?.cancel();
    _connection?.dispose();
    _connection = null;
    _isConnecting = false;
    connectionStatus.value = "Đã ngắt kết nối";
  }
}
