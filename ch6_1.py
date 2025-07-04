from gpiozero import LED
import bluetooth
import time

# --- Cài đặt phần cứng ---
# Đã cập nhật để sử dụng đúng chân GPIO của bạn
led1 = LED(14)
led2 = LED(15)

# --- Cài đặt Bluetooth ---
# Tên dịch vụ sẽ xuất hiện khi bạn tìm kiếm thiết bị Bluetooth
service_name = "Pi LED Control"
# UUID (Mã định danh duy nhất cho dịch vụ)
uuid = "94f39d29-7d6d-437d-973b-fba39e49d4ee"

# Khởi tạo socket Bluetooth
server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
server_sock.bind(("", bluetooth.PORT_ANY))
server_sock.listen(1)

# Lấy cổng mà dịch vụ đang lắng nghe
port = server_sock.getsockname()[1]

# Quảng bá dịch vụ Bluetooth
bluetooth.advertise_service(server_sock, service_name,
                            service_id=uuid,
                            service_classes=[uuid, bluetooth.SERIAL_PORT_CLASS],
                            profiles=[bluetooth.SERIAL_PORT_PROFILE],
                            )

# --- Vòng lặp chính ---
try:
    while True:
        print(f"Đang chờ kết nối trên kênh RFCOMM ở cổng {port}...")
        # Chấp nhận kết nối từ một thiết bị khác (ví dụ: điện thoại)
        client_sock, client_info = server_sock.accept()
        print(f"Đã chấp nhận kết nối từ: {client_info}")

        try:
            while True:
                # Nhận dữ liệu từ client
                data = client_sock.recv(1024)
                if not data:
                    break

                # Chuyển dữ liệu sang string và xử lý
                command = data.decode('utf-8').strip().upper()
                print(f"Đã nhận lệnh: '{command}'")

                parts = command.split()

                if len(parts) == 2:
                    led_num, action = parts
                    target_led = None

                    # Xác định đèn LED mục tiêu
                    if led_num == '1':
                        target_led = led1
                    elif led_num == '2':
                        target_led = led2

                    # Thực hiện hành động
                    if target_led:
                        if action == 'ON':
                            target_led.on()
                            print(f"=> Đã BẬT đèn {led_num} (GPIO{target_led.pin})")
                        elif action == 'OFF':
                            target_led.off()
                            print(f"=> Đã TẮT đèn {led_num} (GPIO{target_led.pin})")
                        else:
                            print("=> Lỗi: Hành động không xác định. Dùng 'ON' hoặc 'OFF'.")
                    else:
                        print("=> Lỗi: Số đèn không xác định. Dùng '1' hoặc '2'.")
                else:
                    print("=> Lỗi: Sai định dạng lệnh. Dùng 'số_đèn hành_động' (ví dụ: '1 ON').")

        except IOError:
            print("Kết nối đã bị ngắt.")

        finally:
            print("Đóng kết nối client.")
            client_sock.close()

except KeyboardInterrupt:
    print("\nĐang dừng chương trình...")

finally:
    print("Dọn dẹp GPIO và đóng server socket.")
    led1.off()
    led2.off()
    server_sock.close()