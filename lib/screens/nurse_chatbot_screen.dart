// lib/screens/nurse_chatbot_screen.dart

import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_generative_ai/google_generative_ai.dart' as gemini;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:chat_bubbles/chat_bubbles.dart';
import '../api/api_service_fastapi.dart'; // Sử dụng service gọi API trung gian
import '../models/patient_info.dart';
import '../models/patient_vitals.dart';

// --- CẤU HÌNH ---
const String GEMINI_API_KEY = 'AIzaSyBnN3ZrDBkWeOmoVE6rPcHVxgkBFJEzgEk';
const String DIALOGFLOW_PROJECT_ID = 'newagent-oisg';

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isTyping;
  ChatMessage({required this.text, required this.isUser, this.isTyping = false});
}

class NurseChatbotScreen extends StatefulWidget {
  const NurseChatbotScreen({super.key});
  @override
  State<NurseChatbotScreen> createState() => _NurseChatbotScreenState();
}

class _NurseChatbotScreenState extends State<NurseChatbotScreen> {
  final TextEditingController _textController = TextEditingController();
  final List<ChatMessage> _messages = [];
  late final gemini.GenerativeModel _geminiModel;
  http.Client? _dialogflowClient;
  bool _isBotReplying = false;

  @override
  void initState() {
    super.initState();
    _geminiModel = gemini.GenerativeModel(model: 'gemini-1.5-flash', apiKey: GEMINI_API_KEY);
    _initializeDialogflowClient();
    _messages.insert(0, ChatMessage(text: "Xin chào, tôi là trợ lý giám sát. Tôi có thể giúp gì cho bạn?", isUser: false));
  }

  Future<void> _initializeDialogflowClient() async {
    try {
      final jsonCredentials = await rootBundle.loadString('assets/dialogflow_credentials.json');
      final credentials = auth.ServiceAccountCredentials.fromJson(jsonCredentials);
      final scopes = ['https://www.googleapis.com/auth/cloud-platform'];
      _dialogflowClient = await auth.clientViaServiceAccount(credentials, scopes);
    } catch (e) {
      print("Lỗi khởi tạo Dialogflow client: $e");
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _dialogflowClient?.close();
    super.dispose();
  }

  void _sendMessage(String text) async {
    if (_isBotReplying || text.trim().isEmpty) return;
    final messageText = text.trim();
    _textController.clear();

    setState(() {
      _isBotReplying = true;
      _messages.insert(0, ChatMessage(text: messageText, isUser: true));
      _messages.insert(0, ChatMessage(text: "...", isUser: false, isTyping: true));
    });

    try {
      String botResponse;
      final dialogflowResult = await _getResponseFromDialogflow(messageText);

      switch (dialogflowResult['action']) {
        case 'list_all_patients_action':
          botResponse = await _handleListAllPatients();
          break;
        case 'list_patients_by_pi_action':
          final rpId = dialogflowResult['parameters']['raspberry_pi_id'] as String?;
          if (rpId != null && rpId.isNotEmpty) {
            botResponse = await _handleListPatientsByPi(rpId);
          } else {
            botResponse = "Vui lòng cung cấp mã Raspberry Pi cụ thể.";
          }
          break;
        case 'get_patient_vitals_action':
          final patientId = dialogflowResult['parameters']['patient_id'] as String?;
          if (patientId != null && patientId.isNotEmpty) {
            botResponse = await _handleGetPatientVitals(patientId);
          } else {
            botResponse = "Vui lòng cung cấp mã bệnh nhân cụ thể.";
          }
          break;
        case 'rename_patient_action':
          final patientId = dialogflowResult['parameters']['patient_id'] as String?;
          final newName = dialogflowResult['parameters']['new_name'] as String?;
          if (patientId != null && patientId.isNotEmpty && newName != null && newName.isNotEmpty) {
            botResponse = await _handleRenamePatient(patientId, newName);
          } else {
            botResponse = "Để đổi tên, vui lòng cung cấp mã bệnh nhân và tên mới.";
          }
          break;
        default:
          if (dialogflowResult['fulfillmentText'].isNotEmpty) {
            botResponse = dialogflowResult['fulfillmentText'];
          } else {
            setState(() { _messages[0] = ChatMessage(text: "Trợ lý AI đang suy nghĩ...", isUser: false, isTyping: true); });
            botResponse = await _getResponseFromGemini(messageText);
          }
      }

      setState(() { _messages[0] = ChatMessage(text: botResponse, isUser: false); });

    } catch (e) {
      setState(() { _messages[0] = ChatMessage(text: "Đã có lỗi xảy ra, vui lòng thử lại.", isUser: false); });
    } finally {
      if (mounted) { setState(() { _isBotReplying = false; }); }
    }
  }

  Future<String> _handleGetPatientVitals(String rawPatientId) async {
    RegExp regex = RegExp(r'(RP\d+BN\d+|BN\d+)', caseSensitive: false);
    Match? match = regex.firstMatch(rawPatientId);

    if (match == null) {
      return "Không thể nhận dạng được mã bệnh nhân từ câu hỏi của bạn.";
    }
    String finalPatientId = match.group(0)!.toUpperCase();

    final PatientVitals? vitals = await ApiServiceNurse.getVitalsForPatient(finalPatientId);

    if (vitals == null) {
      return "Không tìm thấy hoặc không thể lấy dữ liệu cho bệnh nhân có mã $finalPatientId.";
    }

    final int age = DateTime.now().year - vitals.namSinh;
    final String timeString = vitals.thoiGianDo != null && vitals.thoiGianDo!.isNotEmpty
        ? vitals.thoiGianDo!
        : DateTime.now().toIso8601String();

    final measuredTime = DateTime.parse(timeString);
    final formattedTime = "${measuredTime.hour.toString().padLeft(2, '0')}:${measuredTime.minute.toString().padLeft(2, '0')} ngày ${measuredTime.day}/${measuredTime.month}/${measuredTime.year}";

    return "Thông tin bệnh nhân:\n"
        "👤 Tên: ${vitals.hoVaTen}\n"
        "🎂 Tuổi: $age\n\n"
        "Chỉ số sức khỏe đo lúc $formattedTime:\n"
        "🌡️ Nhiệt độ: ${vitals.nhietdo ?? 'N/A'}°C\n"
        "❤️ Nhịp tim: ${vitals.nhipTim ?? 'N/A'} bpm\n"
        "💨 SpO2: ${vitals.spo2 ?? 'N/A'}%";
  }

  Future<String> _handleListAllPatients() async {
    final List<PatientInfo>? allPatients = await ApiServiceNurse.getAllPatients();

    if (allPatients == null) {
      return "Lỗi kết nối: Không thể lấy danh sách bệnh nhân từ server.";
    }
    if (allPatients.isEmpty) {
      return "Không tìm thấy bệnh nhân nào trong hệ thống.";
    }

    String botResponse = "Tổng hợp danh sách tất cả bệnh nhân:\n";
    Map<String, List<PatientInfo>> groupedPatients = {};
    for (var patient in allPatients) {
      (groupedPatients[patient.idPi] ??= []).add(patient);
    }

    groupedPatients.forEach((piId, patientList) {
      botResponse += "\n--- Raspberry Pi: $piId ---\n";
      for (var patient in patientList) {
        botResponse += "- ${patient.hoVaTen} (ID: ${patient.maBenhNhan})\n";
      }
    });

    return botResponse.trim();
  }

  Future<String> _handleListPatientsByPi(String rpId) async {
    final List<PatientInfo>? patients = await ApiServiceNurse.getPatientsByRaspberryId(rpId);
    if (patients == null) {
      return "Lỗi kết nối: Không thể lấy dữ liệu cho Pi có mã $rpId.";
    }
    if (patients.isEmpty) {
      return "Không tìm thấy bệnh nhân nào trong Raspberry Pi có mã $rpId.";
    }
    String response = "Danh sách bệnh nhân trong $rpId:\n";
    for (var patient in patients) {
      response += "- ${patient.hoVaTen} (ID: ${patient.maBenhNhan})\n";
    }
    return response.trim();
  }

  Future<String> _handleRenamePatient(String patientId, String newName) async {
    final success = await ApiServiceNurse.renamePatient(patientId, newName);
    if (success) {
      return "Đã đổi tên bệnh nhân $patientId thành công thành: $newName.";
    } else {
      return "Không thể đổi tên cho bệnh nhân $patientId. Vui lòng kiểm tra lại mã bệnh nhân.";
    }
  }

  Future<Map<String, dynamic>> _getResponseFromDialogflow(String query) async {
    if (_dialogflowClient == null) {
      return {'fulfillmentText': "Lỗi kết nối chatbot.", 'isFallback': true, 'action': '', 'parameters': {}};
    }
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final url = Uri.parse('https://dialogflow.googleapis.com/v2/projects/$DIALOGFLOW_PROJECT_ID/agent/sessions/$sessionId:detectIntent');
    final headers = {'Content-Type': 'application/json; charset=utf-8'};
    final body = jsonEncode({'queryInput': {'text': {'text': query, 'languageCode': 'vi-VN'}}});

    try {
      final response = await _dialogflowClient!.post(url, headers: headers, body: body);
      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(utf8.decode(response.bodyBytes));
        final queryResult = decodedResponse['queryResult'];
        return {
          'fulfillmentText': queryResult['fulfillmentText'] as String? ?? '',
          'action': queryResult['action'] as String? ?? '',
          'parameters': queryResult['parameters'] as Map<String, dynamic>? ?? {},
          'isFallback': queryResult['intent']['isFallback'] as bool? ?? false,
        };
      }
    } catch (e) {
      print("Ngoại lệ khi gọi Dialogflow: $e");
    }
    return {'fulfillmentText': '', 'isFallback': true, 'action': '', 'parameters': {}};
  }

  Future<String> _getResponseFromGemini(String text) async {
    try {
      final prompt = 'Hãy trả lời câu hỏi sau bằng tiếng Việt một cách ngắn gọn và thân thiện: "$text"';
      final response = await _geminiModel.generateContent([gemini.Content.text(prompt)]);
      return response.text ?? "Xin lỗi, tôi không thể trả lời câu hỏi này.";
    } catch (e) {
      return "Đã xảy ra lỗi với dịch vụ AI, vui lòng thử lại.";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80.0),
        child: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          flexibleSpace: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('assets/hcmute_logo.png', height: 50),
                  const Text('HEALTHCARE APP - ADMINISTRATION ONLY',
                    style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  Image.asset('assets/samsung_logo.png', height: 50),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildActionButtons(),
          const Divider(height: 1.0),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (_, int index) => _buildMessageBubble(_messages[index]),
            ),
          ),
          const Divider(height: 1.0),
          _buildTextComposer(),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(12.0),
      color: Colors.grey[100],
      child: Wrap(
        spacing: 8.0,
        runSpacing: 8.0,
        alignment: WrapAlignment.center,
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.print_sharp, size: 18),
            label: const Text("In DS Tất Cả Bệnh Nhân"),
            onPressed: _isBotReplying ? null : () => _sendMessage("In danh sách tất cả bệnh nhân"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
          FutureBuilder<List<String>?>(
            future: ApiServiceNurse.getAllRaspberryIds(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Chip(label: Text("Đang tải DS Pi..."));
              }
              if (!snapshot.hasData || snapshot.data == null || snapshot.data!.isEmpty) {
                return const SizedBox.shrink();
              }
              final rpIds = snapshot.data!;
              return PopupMenuButton<String>(
                onSelected: (String piId) {
                  _sendMessage("danh sách bệnh nhân của $piId");
                },
                enabled: !_isBotReplying,
                itemBuilder: (BuildContext context) {
                  return rpIds.map((String id) {
                    return PopupMenuItem<String>(
                      value: id,
                      child: Text("DS Bệnh nhân $id"),
                    );
                  }).toList();
                },
                child: Chip(
                  avatar: const Icon(Icons.memory, size: 16),
                  label: const Text("In DS theo từng Pi"),
                  backgroundColor: Colors.blue[100],
                ),
              );
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.edit, size: 18),
            label: const Text("Sửa Tên Bệnh Nhân"),
            onPressed: _isBotReplying ? null : _showRenamePatientDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenamePatientDialog() async {
    final patientIdController = TextEditingController();
    final newNameController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<void>(
      context: context,
      barrierDismissible: !_isBotReplying,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Sửa Tên Bệnh Nhân'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  TextFormField(
                    controller: patientIdController,
                    decoration: const InputDecoration(hintText: "Nhập mã bệnh nhân (vd: RP001BN01)"),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Vui lòng không để trống';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: newNameController,
                    decoration: const InputDecoration(hintText: "Nhập tên mới"),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Vui lòng không để trống';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Hủy'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: const Text('Xác nhận'),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  final patientId = patientIdController.text.trim();
                  final newName = newNameController.text.trim();
                  _sendMessage("đổi tên bệnh nhân $patientId thành $newName");
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!message.isUser)
            Padding(
              padding: const EdgeInsets.only(right: 8.0, top: 5.0),
              child: CircleAvatar(backgroundImage: AssetImage('assets/bot_avatar.png')),
            ),
          Flexible(
            child: message.isTyping
                ? BubbleNormal(
              text: message.text,
              isSender: false,
              color: const Color(0xFFE8E8EE),
              tail: true,
              textStyle: const TextStyle(
                fontSize: 16,
                color: Colors.black,
                fontStyle: FontStyle.italic,
              ),
            )
                : BubbleSpecialThree(
              text: message.text,
              color: message.isUser ? const Color(0xFF1B97F3) : const Color(0xFFE8E8EE),
              tail: true,
              isSender: message.isUser,
              textStyle: TextStyle(
                color: message.isUser ? Colors.white : Colors.black,
                fontSize: 16,
              ),
            ),
          ),
          if (message.isUser)
            Padding(
              padding: const EdgeInsets.only(left: 8.0, top: 5.0),
              child: CircleAvatar(backgroundImage: AssetImage('assets/user_avatar.png')),
            ),
        ],
      ),
    );
  }

  Widget _buildTextComposer() {
    return IconTheme(
      data: IconThemeData(color: Theme.of(context).colorScheme.secondary),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        child: Row(
          children: [
            Flexible(
              child: TextField(
                controller: _textController,
                enabled: !_isBotReplying,
                onSubmitted: _isBotReplying ? null : (text) => _sendMessage(text),
                decoration: InputDecoration.collapsed(
                    hintText: _isBotReplying ? "Đang xử lý..." : "Nhập câu hỏi..."
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4.0),
              child: IconButton(
                icon: const Icon(Icons.send),
                onPressed: _isBotReplying ? null : () => _sendMessage(_textController.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}