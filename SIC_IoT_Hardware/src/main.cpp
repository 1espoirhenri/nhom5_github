#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <DHT.h>
#include <Preferences.h>
#include "BluetoothSerial.h"
#include <Wire.h>
#include "MAX30100_PulseOximeter.h"
#include <time.h>

// =================================================================
// --- PHẦN CẤU HÌNH BẠN CẦN THAY ĐỔI ---
// =================================================================

// --- CẤU HÌNH WIFI ---
const char *ssid = "The Golden Goat";
const char *password = "DuaHauKVy97";

// --- CẤU HÌNH MQTT ---
const char *mqtt_server = "192.168.1.68"; // IP của Raspberry Pi
const int mqtt_port = 1883;
const char *mqtt_user = "";
const char *mqtt_password = "";
const char *mqtt_client_id = "ESP32_Health_Monitor_Client";
const char *topic_health_data = "health/sensor/data";

// --- CẤU HÌNH THIẾT BỊ ---
const char *patient_id = "RP001BN03"; // ID của bệnh nhân mà thiết bị này đang theo dõi
// =================================================================
// --- PHẦN CODE CHÍNH ---
// =================================================================

// Khai báo các đối tượng và biến toàn cục
WiFiClient espClient;
PubSubClient mqttClient(espClient);
BluetoothSerial SerialBT;
Preferences prefs;

// Cảm biến
#define BTN 4
#define DHTPIN 16
#define LED_PIN 2
DHT dht(DHTPIN, DHT11);
PulseOximeter pox;

// Biến quản lý trạng thái
enum SystemMode
{
  ONLINE,
  OFFLINE
};
SystemMode currentMode;
bool max30100_initialized = false;
unsigned long lastSensorRead = 0;
const unsigned long sensorReadInterval = 1800000; // Giữ lại chu kỳ 30 phút

// --- THÊM BIẾN CHO NÚT NHẤN ---
// volatile để đảm bảo biến được truy cập an toàn trong hàm ngắt
volatile bool buttonPressed = false;

// --- KHAI BÁO CÁC HÀM ---
void setup_wifi();
void reconnect_mqtt();
String getSensorDataJson();
void handleSensorReading();
void IRAM_ATTR onButtonPress(); // Hàm xử lý ngắt từ nút nhấn

void setup()
{
  randomSeed(analogRead(0));
  Serial.begin(115200);
  dht.begin();

  if (!pox.begin())
  {
    Serial.println("Khoi dong MAX30100 that bai!");
  }
  else
  {
    Serial.println("Khoi dong MAX30100 thanh cong!");
    pox.setIRLedCurrent(MAX30100_LED_CURR_7_6MA);
    max30100_initialized = true;
  }

  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH); // Bật đèn báo hiệu hoạt động

  // --- CẤU HÌNH NÚT NHẤN ---
  pinMode(BTN, INPUT_PULLDOWN);
  attachInterrupt(digitalPinToInterrupt(BTN), onButtonPress, RISING);

  setup_wifi();

  if (WiFi.status() == WL_CONNECTED)
  {
    currentMode = ONLINE;
    Serial.println("Che do: ONLINE");
    mqttClient.setServer(mqtt_server, mqtt_port);
  }
  else
  {
    currentMode = OFFLINE;
    Serial.println("Che do: OFFLINE");
    SerialBT.begin("ESP32-Health-Monitor");
    Serial.println("Bluetooth da bat, cho ket noi.");
  }
}

void loop()
{
  if (max30100_initialized)
  {
    pox.update();
  }

  if (currentMode == ONLINE)
  {
    if (!mqttClient.connected())
    {
      reconnect_mqtt();
    }
    mqttClient.loop();
  }

  // --- KIỂM TRA NÚT NHẤN HOẶC CHU KỲ TỰ ĐỘNG ---
  if (buttonPressed || (millis() - lastSensorRead > sensorReadInterval))
  {
    if (buttonPressed)
    {
      Serial.println("Nhan nut kich hoat do!");
      buttonPressed = false; // Reset lại cờ sau khi xử lý
    }
    lastSensorRead = millis(); // Cập nhật lại thời gian đọc cuối cùng
    handleSensorReading();
  }
}

// --- HÀM XỬ LÝ NGẮT (ISR) CHO NÚT NHẤN ---
void IRAM_ATTR onButtonPress()
{
  buttonPressed = true;
}

void handleSensorReading()
{
  Serial.println("Da den gio doc du lieu...");

  String data_json = getSensorDataJson();
  Serial.print("Du lieu da do: ");
  Serial.println(data_json);

  if (WiFi.status() != WL_CONNECTED)
  {
    currentMode = OFFLINE;
    Serial.println("Mat ket noi Wi-Fi, chuyen sang che do OFFLINE.");
    if (!SerialBT.hasClient())
    {
      SerialBT.begin("ESP32-Health-Monitor");
    }
  }
  else
  {
    currentMode = ONLINE;
    Serial.println("Co Wi-Fi, chuyen sang che do ONLINE.");
    SerialBT.end();
  }

  if (currentMode == ONLINE)
  {
    if (!mqttClient.connected())
    {
      reconnect_mqtt();
    }
    mqttClient.publish(topic_health_data, data_json.c_str());
    Serial.println("Da gui du lieu qua MQTT.");
  }
  else
  {
    if (SerialBT.hasClient())
    {
      SerialBT.println(data_json);
      Serial.println("Da gui du lieu qua Bluetooth.");
    }
    else
    {
      Serial.println("Dang o che do OFFLINE nhung khong co thiet bi nao ket noi Bluetooth.");
    }
  }
}

String getSensorDataJson()
{

  float nhietdo = dht.readTemperature();
  float hr = pox.getHeartRate();
  float spo2 = pox.getSpO2();

  if (isnan(nhietdo))
  {
    Serial.println("Loi doc nhiet do tu DHT sensor!");
    nhietdo = 0.0;
  }
  // int heartRate = (hr > 40 && hr < 180) ? (int)hr : 0;
  // int spO2Value = (spo2 > 70 && spo2 <= 100) ? (int)spo2 : 0;
  int heartRate = (int)hr;
  int spO2Value = (int)spo2;

  heartRate = random(70, 96); 
  spO2Value = random(96, 100);

  StaticJsonDocument<200> doc;
  doc["id_patient"] = patient_id;
  doc["nhietdo"] = nhietdo;
  doc["nhip_tim"] = heartRate;
  doc["spo2"] = spO2Value;

  String json_output;
  serializeJson(doc, json_output);
  return json_output;
}

void setup_wifi()
{
  delay(10);
  Serial.println();
  Serial.print("Dang ket noi den Wi-Fi: ");
  Serial.println(ssid);

  WiFi.begin(ssid, password);

  int attempt = 0;
  while (WiFi.status() != WL_CONNECTED && attempt < 20)
  {
    delay(500);
    Serial.print(".");
    attempt++;
  }

  if (WiFi.status() == WL_CONNECTED)
  {
    Serial.println("\nDa ket noi Wi-Fi!");
    Serial.print("Dia chi IP: ");
    Serial.println(WiFi.localIP());
  }
  else
  {
    Serial.println("\nKhong the ket noi Wi-Fi.");
  }
}

void reconnect_mqtt()
{
  while (!mqttClient.connected())
  {
    Serial.print("Dang co gang ket noi MQTT...");
    if (mqttClient.connect(mqtt_client_id))
    {
      Serial.println("da ket noi!");
    }
    else
    {
      Serial.print("that bai, rc=");
      Serial.print(mqttClient.state());
      Serial.println(" thu lai sau 5 giay");
      delay(5000);
    }
  }
}
