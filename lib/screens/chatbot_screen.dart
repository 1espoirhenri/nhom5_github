// lib/screens/chatbot_screen.dart

import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_generative_ai/google_generative_ai.dart' as gemini;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:chat_bubbles/chat_bubbles.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../api/api_service.dart'; // Sử dụng service kết nối DB trực tiếp
import '../models/health_data.dart';

// --- CẤU HÌNH ---
const String GEMINI_API_KEY = 'YOUR_GEMINI_APIKEY';
const String DIALOGFLOW_PROJECT_ID = 'YOUR_DIALOGFLOW_PROJECT_ID';

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isTyping;
  final bool isWarning;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.isTyping = false,
    this.isWarning = false,
  });
}

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});
  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
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
    _displayWelcomeMessageIfNeeded();
  }

  Future<void> _displayWelcomeMessageIfNeeded() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.wifi)) {
      bool isDbConnected = await ApiService.checkDatabaseConnection();
      if (isDbConnected && mounted) {
        setState(() {
          _messages.insert(0, ChatMessage(
              text: "Tôi là trợ lý hỗ trợ sức khỏe! Tôi có thể hỗ trợ gì cho bạn?",
              isUser: false
          ));
        });
      }
    }
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
      ChatMessage botResponse;
      final dialogflowResult = await _getResponseFromDialogflow(messageText);

      if (dialogflowResult['action'] == 'get_patient_vitals_action') {
        final patientId = dialogflowResult['parameters']['patient_id'] as String?;
        if (patientId != null && patientId.isNotEmpty) {
          botResponse = await _handleGetPatientVitals(patientId);
        } else {
          botResponse = ChatMessage(text: "Vui lòng cung cấp mã bệnh nhân.", isUser: false);
        }
      } else {
        String responseText;
        if (dialogflowResult['fulfillmentText'].isNotEmpty) {
          responseText = dialogflowResult['fulfillmentText'];
        } else {
          setState(() { _messages[0] = ChatMessage(text: "Trợ lý AI đang suy nghĩ...", isUser: false, isTyping: true); });
          responseText = await _getResponseFromGemini(messageText);
        }
        // Làm sạch Markdown cho các câu trả lời chung
        final cleanText = responseText.replaceAll('**', '').replaceAll('*', '• ').trim();
        botResponse = ChatMessage(text: cleanText, isUser: false);
      }

      setState(() { _messages[0] = botResponse; });

    } catch (e) {
      setState(() { _messages[0] = ChatMessage(text: "Đã có lỗi xảy ra.", isUser: false, isWarning: true); });
    } finally {
      if (mounted) { setState(() { _isBotReplying = false; }); }
    }
  }

  Future<ChatMessage> _handleGetPatientVitals(String rawPatientId) async {
    RegExp regex = RegExp(r'(RP\d+BN\d+|BN\d+)', caseSensitive: false);
    Match? match = regex.firstMatch(rawPatientId);
    if (match == null) {
      return ChatMessage(text: "Không thể nhận dạng được mã bệnh nhân.", isUser: false, isWarning: true);
    }
    String finalPatientId = match.group(0)!.toUpperCase();

    final HealthData? latestVitals = await ApiService.getLatestVitals(finalPatientId);

    if (latestVitals == null) {
      return ChatMessage(text: "Không tìm thấy dữ liệu cho bệnh nhân có mã $finalPatientId.", isUser: false, isWarning: true);
    }

    bool isWarning = false;
    const double tempLower = 36.5; const double tempUpper = 37.5;
    const int spo2Lower = 95;
    const int hrLower = 60; const int hrUpper = 100;

    if (latestVitals.nhietdo < tempLower || latestVitals.nhietdo > tempUpper) isWarning = true;
    if (latestVitals.spo2 < spo2Lower) isWarning = true;
    if (latestVitals.nhipTim < hrLower || latestVitals.nhipTim > hrUpper) isWarning = true;

    final int age = DateTime.now().year - latestVitals.namSinh;
    final measuredTime = DateTime.parse(latestVitals.thoiGianDo);
    final formattedTime = "${measuredTime.hour.toString().padLeft(2, '0')}:${measuredTime.minute.toString().padLeft(2, '0')} ngày ${measuredTime.day}/${measuredTime.month}/${measuredTime.year}";

    final String responseText = "Thông tin bệnh nhân:\n"
        "👤 Tên: ${latestVitals.hoVaTen}\n"
        "🎂 Tuổi: $age\n\n"
        "Chỉ số sức khỏe đo lúc $formattedTime:\n"
        "🌡️ Nhiệt độ: ${latestVitals.nhietdo}°C\n"
        "❤️ Nhịp tim: ${latestVitals.nhipTim} bpm\n"
        "💨 SpO2: ${latestVitals.spo2}%";

    return ChatMessage(text: responseText, isUser: false, isWarning: isWarning);
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
      final prompt = 'Hãy trả lời câu hỏi sau bằng tiếng Việt một cách đầy đủ và thân thiện: "$text"';
      final response = await _geminiModel.generateContent([gemini.Content.text(prompt)]);
      return response.text ?? "Xin lỗi, tôi không thể trả lời câu hỏi này.";
    } catch (e) {
      return "Đã xảy ra lỗi với dịch vụ AI, vui lòng thử lại.";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Image.asset('assets/hcmute_logo.png', height: 30),
          const Spacer(),
          const Text('HEALTHCARE APP '),
          const Spacer(),
          Image.asset('assets/samsung_logo.png', height: 30),
        ]),
      ),
      body: Column(
        children: [
          _buildSuggestedQuestions(),
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

  Widget _buildMessageBubble(ChatMessage message) {
    final bubbleColor = message.isUser
        ? const Color(0xFF1B97F3)
        : message.isWarning
        ? Colors.orange.shade200
        : const Color(0xFFE8E8EE);

    final textColor = message.isUser
        ? Colors.white
        : message.isWarning
        ? Colors.red.shade900
        : Colors.black;

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
              color: bubbleColor,
              tail: true,
              isSender: message.isUser,
              textStyle: TextStyle(
                color: textColor,
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

  final List<String> _suggestedQuestions = [
    "Cách xử lý khi bị bỏng",
    "Khi bị sốt thì làm gì?",
    "chỉ số SpO2 thấp có nguy hiểm không?",
  ];

  Widget _buildSuggestedQuestions() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _suggestedQuestions.map((question) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: ActionChip(
              avatar: const Icon(Icons.message_outlined, size: 16),
              label: Text(question),
              onPressed: _isBotReplying ? null : () => _sendMessage(question),
            ),
          )).toList(),
        ),
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
