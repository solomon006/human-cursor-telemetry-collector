from evdev import UInput, ecodes as e
import time
import sys
import os

# ПРЕДУПРЕЖДЕНИЕ: Скрипт нужно запускать с правами sudo!

def create_virtual_mouse():
    """Создает виртуальное устройство мыши."""
    capabilities = {
        e.EV_REL: (e.REL_X, e.REL_Y),
        e.EV_KEY: (e.BTN_LEFT,)
    }
    
    try:
        ui = UInput(events=capabilities, name="AI_Ghost_Mouse")
        print("Виртуальная мышь создана. Даем ОС 1 сек на инициализацию...")
        time.sleep(1) 
        return ui
    except PermissionError:
         print("Ошибка: Нет прав для создания виртуального устройства. Запустите через sudo.")
         sys.exit(1)

def inject_trajectory(ui, trajectory_data):
    """
    Отправляет массив сгенерированных данных в систему.
    """
    print("Начинаем инъекцию движений...")
    
    for dx, dy, dt in trajectory_data:
        time.sleep(dt)
        
        if dx != 0:
            ui.write(e.EV_REL, e.REL_X, int(dx))
        if dy != 0:
            ui.write(e.EV_REL, e.REL_Y, int(dy))
        
        ui.syn()

def perform_click(ui):
    """Имитирует левый клик."""
    print("Выполняем клик...")
    ui.write(e.EV_KEY, e.BTN_LEFT, 1) # Нажали
    ui.syn()
    
    time.sleep(0.06) # Задержка удержания
    
    ui.write(e.EV_KEY, e.BTN_LEFT, 0) # Отпустили
    ui.syn()

def main():
    if os.geteuid() != 0:
        print("Ошибка: Скрипт требует прав суперпользователя. Запустите через sudo.")
        sys.exit(1)

    ui = create_virtual_mouse()
    
    # Заглушка. Сюда нужно будет передавать вывод твоей ML модели.
    mock_ai_output = [
        (2, 0, 0.008),
        (3, 1, 0.008),
        (5, 2, 0.008),
        (8, 4, 0.008),
        (5, 1, 0.008),
        (2, 0, 0.008),
        (1, 0, 0.012), 
        (0, 0, 0.016)
    ]
    
    try:
        inject_trajectory(ui, mock_ai_output)
        time.sleep(0.1) 
        perform_click(ui)
    finally:
        ui.close()
        print("Инъекция завершена, виртуальная мышь отключена.")

if __name__ == "__main__":
    main()
