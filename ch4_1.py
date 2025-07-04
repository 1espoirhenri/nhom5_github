import psutil
from gpiozero import LED
import time
import os
from datetime import datetime

# --- Cài đặt ---
# Đặt đúng số chân GPIO bạn đã nối đèn LED
RED_LED_PIN = 14
YELLOW_LED_PIN = 15

# Ngưỡng cảnh báo (%)
YELLOW_THRESHOLD = 30.0
RED_THRESHOLD = 60.0

# Đường dẫn đến tệp nhật ký
LOG_DIR = "/home/pi/Unit_Practice"
LOG_FILE = os.path.join(LOG_DIR, "disk_usage_log.txt")

# Thời gian nghỉ giữa mỗi lần kiểm tra (giây)
CHECK_INTERVAL = 60

# --- Khởi tạo phần cứng và tệp ---
print("Khởi động chương trình theo dõi dung lượng...")

# Khởi tạo đèn LED
red_led = LED(RED_LED_PIN)
yellow_led = LED(YELLOW_LED_PIN)

# Tạo thư mục chứa tệp nhật ký nếu nó chưa tồn tại
# exist_ok=True sẽ không báo lỗi nếu thư mục đã có sẵn
os.makedirs(LOG_DIR, exist_ok=True)

print(f"Sẽ ghi nhật ký vào: {LOG_FILE}")
print("Nhấn CTRL+C để dừng chương trình.")

# --- Vòng lặp chính ---
try:
    while True:
        # Lấy phần trăm dung lượng đĩa đã sử dụng
        disk_usage = psutil.disk_usage('/').percent

        print(f"Dung lượng đã sử dụng: {disk_usage}%")

        # Kịch bản 1: Mức sử dụng vượt quá 60%
        if disk_usage > RED_THRESHOLD:
            print(f"CẢNH BÁO: Dung lượng vượt quá {RED_THRESHOLD}%. Bật đèn LED Đỏ.")
            red_led.on()
            yellow_led.off()

        # Kịch bản 2: Mức sử dụng vượt quá 30% (nhưng không quá 60%)
        elif disk_usage > YELLOW_THRESHOLD:
            print(f"LƯU Ý: Dung lượng vượt quá {YELLOW_THRESHOLD}%. Bật đèn LED Vàng.")
            yellow_led.on()
            red_led.off()

            # Ghi nhật ký vào tệp
            try:
                with open(LOG_FILE, 'a') as f:
                    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    log_entry = f"{timestamp} - Mức sử dụng: {disk_usage}%\n"
                    f.write(log_entry)
            except IOError as e:
                print(f"Lỗi: Không thể ghi vào tệp nhật ký: {e}")

        # Kịch bản 3: Mức sử dụng bình thường (dưới 30%)
        else:
            print("Mức sử dụng bình thường. Tắt tất cả đèn LED.")
            red_led.off()
            yellow_led.off()

        # Tạm dừng trước khi kiểm tra lại
        time.sleep(CHECK_INTERVAL)

except KeyboardInterrupt:
    # Xử lý khi người dùng nhấn Ctrl+C để thoát
    print("\nĐang dừng chương trình...")
    red_led.off()
    yellow_led.off()
    print("Đã tắt đèn LED. Tạm biệt!")