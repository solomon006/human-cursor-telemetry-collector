import evdev
import csv
import sys
import os
import time
import signal

def handle_sigterm(*args):
    print("\nСбор данных остановлен (SIGTERM).")
    sys.exit(0)
signal.signal(signal.SIGTERM, handle_sigterm)

def find_mouse():
    """Ищет первую попавшуюся мышь в системе."""
    devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
    for device in devices:
        # Ищем устройство, в имени которого есть 'mouse', или которое имеет
        # возможности EV_REL (относительные смещения - признак мыши)
        if 'mouse' in device.name.lower() or evdev.ecodes.EV_REL in device.capabilities():
            return device
    return None

def main():
    try:
        device = find_mouse()
    except PermissionError:
        print("Ошибка: Нет прав доступа к /dev/input/. Добавьте пользователя в группу 'input' или запустите через sudo.")
        sys.exit(1)

    if not device:
        print("Ошибка: Мышь не найдена. Укажите путь вручную в коде.")
        sys.exit(1)

    print(f"Подключено устройство: {device.name} ({device.path})")
    
    time_offset = time.time() - time.monotonic()
    output_file = sys.argv[1] if len(sys.argv) > 1 else 'raw_mouse_data.csv'
    
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        # Заголовок CSV:
        # timestamp - время события в UNIX секундах от ОС
        # event_type - 'MOVE' или 'CLICK'
        # axis - 'X', 'Y' или код кнопки
        # value - дельта или состояние (1/0)
        writer.writerow(['timestamp', 'event_type', 'axis', 'value'])

        print(f"Начата запись в {output_file}. Нажмите Ctrl+C для остановки.")

        try:
            # Читаем события аппаратуры
            for event in device.read_loop():
                realtime_ts = event.timestamp() + time_offset
                
                if event.type == evdev.ecodes.EV_REL:
                    if event.code == evdev.ecodes.REL_X:
                        writer.writerow([realtime_ts, 'MOVE', 'X', event.value])
                    elif event.code == evdev.ecodes.REL_Y:
                        writer.writerow([realtime_ts, 'MOVE', 'Y', event.value])
                        
                elif event.type == evdev.ecodes.EV_KEY:
                    if event.code in (evdev.ecodes.BTN_LEFT, evdev.ecodes.BTN_RIGHT, evdev.ecodes.BTN_MIDDLE):
                         writer.writerow([realtime_ts, 'CLICK', event.code, event.value])
                         
        except KeyboardInterrupt:
            print("\nСбор данных остановлен.")

if __name__ == "__main__":
    main()
