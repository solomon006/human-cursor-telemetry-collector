import evdev
import csv
import sys
import os
import time
import signal
import ctypes

# Автоматически завершаем работу на Linux, если родительский процесс (Godot) завершился/упал
try:
    libc = ctypes.CDLL(None)
    # PR_SET_PDEATHSIG = 1, SIGTERM = 15
    libc.prctl(1, 15)
except Exception:
    pass

_running = True

def handle_sigterm(*args):
    global _running
    _running = False
    print("\nСбор данных остановлен (SIGTERM).")
signal.signal(signal.SIGTERM, handle_sigterm)
signal.signal(signal.SIGINT, handle_sigterm)

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
    
    # line_buffering=True — каждая строка немедленно сбрасывается на диск,
    # чтобы при SIGTERM не потерять данные в буфере.
    with open(output_file, 'w', newline='', buffering=1) as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp', 'event_type', 'axis', 'value'])
        f.flush()

        print(f"Начата запись в {output_file}. Нажмите Ctrl+C для остановки.")

        try:
            for event in device.read_loop():
                if not _running:
                    break
                    
                realtime_ts = event.timestamp() + time_offset
                
                if event.type == evdev.ecodes.EV_REL:
                    if event.code == evdev.ecodes.REL_X:
                        writer.writerow([realtime_ts, 'MOVE', 'X', event.value])
                    elif event.code == evdev.ecodes.REL_Y:
                        writer.writerow([realtime_ts, 'MOVE', 'Y', event.value])
                        
                elif event.type == evdev.ecodes.EV_KEY:
                    if event.code in (evdev.ecodes.BTN_LEFT, evdev.ecodes.BTN_RIGHT, evdev.ecodes.BTN_MIDDLE):
                         writer.writerow([realtime_ts, 'CLICK', event.code, event.value])
                         
        except (KeyboardInterrupt, OSError):
            pass
        
        f.flush()
        print(f"\nСбор данных завершён. Записано в {output_file}")

if __name__ == "__main__":
    main()
