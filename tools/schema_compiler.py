import json
import csv
import sys
import os
from typing import List, Dict, Any

def parse_evdev_csv(csv_path: str) -> List[Dict[str, Any]]:
    """
    Парсит сырой CSV от ОС и группирует события по миллисекундам с отслеживанием состояния кнопок.
    """
    events = []
    
    # Состояние кнопок в реальном времени
    btn_state = {
        'left': False,
        'right': False,
        'middle': False
    }
    
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        current_group = {}
        last_ts = 0.0
        
        for row in reader:
            ts = float(row['timestamp'])
            
            # Группируем события, произошедшие в окне 1 мс
            if ts - last_ts > 0.001 and current_group:
                events.append(current_group)
                current_group = {}
            
            if not current_group:
                current_group = {
                    't_us_abs': int(ts * 1_000_000),
                    'dx': 0.0,
                    'dy': 0.0,
                    'clicks': [],
                    'buttons_state': dict(btn_state)
                }
            
            if row['event_type'] == 'MOVE':
                if row['axis'] == 'X': 
                    current_group['dx'] += float(row['value'])
                elif row['axis'] == 'Y': 
                    current_group['dy'] += float(row['value'])
            elif row['event_type'] == 'CLICK':
                code = int(row['axis'])
                val = int(row['value'])
                current_group['clicks'].append((code, val))
                
                # Обновляем состояние кнопки
                pressed = (val == 1)
                if code == 272: # BTN_LEFT
                    btn_state['left'] = pressed
                elif code == 273: # BTN_RIGHT
                    btn_state['right'] = pressed
                elif code == 274: # BTN_MIDDLE
                    btn_state['middle'] = pressed
                
                current_group['buttons_state'] = dict(btn_state)
            
            last_ts = ts
            
        if current_group:
            events.append(current_group)
            
    return events

def create_event_json(evdev_event: Dict, trial_meta: Dict, event_index: int, pos_x: float, pos_y: float) -> Dict:
    """
    Создает объект события для фазы trial в строгом соответствии с docs/data_schema.md.
    """
    clicks = evdev_event['clicks']
    is_click = len(clicks) > 0
    
    if is_click:
        code, val = clicks[0]
        event_type = "mouse_button_down" if val == 1 else "mouse_button_up"
    else:
        event_type = "mouse_motion"
    
    data = {
        "event_id": f"e_sys_{event_index}",
        "participant_id": trial_meta['p_id'],
        "session_id": trial_meta['s_id'],
        "trial_id": trial_meta['id'],
        "event_index_global": event_index,
        "event_index_trial": trial_meta['local_index'],
        "event_type": event_type,
        "phase": "movement",
        "t_us_abs": evdev_event['t_us_abs'],
        "t_us_trial": evdev_event['t_us_abs'] - trial_meta['start_t'],
        "t_ms_trial": (evdev_event['t_us_abs'] - trial_meta['start_t']) / 1000.0,
        "position": {"x": round(pos_x, 2), "y": round(pos_y, 2)},
        "relative": {
            "dx": evdev_event['dx'],
            "dy": evdev_event['dy']
        },
        "state": {
            "cursor_inside_target": False,
            "target_visible": True,
            "left_viewport": False
        },
        "raw": {
            "source": "evdev_os_level"
        }
    }
    
    if is_click:
        code, val = clicks[0]
        btn_index = 0
        btn_name = "unknown"
        if code == 272:
            btn_index = 1
            btn_name = "left"
        elif code == 273:
            btn_index = 2
            btn_name = "right"
        elif code == 274:
            btn_index = 3
            btn_name = "middle"
            
        data["button"] = {
            "button_index": btn_index,
            "button_name": btn_name,
            "pressed": (val == 1)
        }
    else:
        btn_state = evdev_event['buttons_state']
        mask = 0
        if btn_state['left']: mask |= 1
        if btn_state['right']: mask |= 2
        if btn_state['middle']: mask |= 4
        data["buttons"] = {
            "left": btn_state['left'],
            "right": btn_state['right'],
            "middle": btn_state['middle'],
            "button_mask_raw": mask
        }
        
    return {
        "kind": "event",
        "data": data
    }

def merge_logs(godot_jsonl_path: str, evdev_csv_path: str, output_path: str):
    """
    Склеивает логи Godot и evdev.
    """
    print("Чтение аппаратных данных (evdev)...")
    try:
        hardware_events = parse_evdev_csv(evdev_csv_path)
        print(f"Сформировано {len(hardware_events)} аппаратных фреймов.")
    except Exception as e:
         print(f"Ошибка чтения {evdev_csv_path}: {e}")
         return

    hw_index = 0
    hw_total = len(hardware_events)
    global_event_counter = 1

    print("Слияние с логом Godot...")
    
    try:
        with open(godot_jsonl_path, 'r', encoding='utf-8') as gf, open(output_path, 'w', encoding='utf-8') as outf:
            active_trial = None
            
            for line in gf:
                try:
                    obj = json.loads(line.strip())
                except json.JSONDecodeError:
                    continue 
                
                kind = obj.get('kind')
                data = obj.get('data', {})
                
                if kind == 'trial_end':
                    if not active_trial:
                        outf.write(line)
                        continue
                        
                    end_t_us = data.get('t_us')
                    trial_hw_events = []
                    
                    while hw_index < hw_total:
                        hw_ev = hardware_events[hw_index]
                        
                        if hw_ev['t_us_abs'] < active_trial['start_t']:
                            hw_index += 1
                            continue
                            
                        if hw_ev['t_us_abs'] > end_t_us:
                            break
                            
                        trial_hw_events.append(hw_ev)
                        hw_index += 1
                    
                    # Интегрируем относительные координаты с endpoint-scaling сжатием/растяжением
                    sum_dx = sum(ev['dx'] for ev in trial_hw_events)
                    sum_dy = sum(ev['dy'] for ev in trial_hw_events)
                    
                    start_x = active_trial.get('start_x', 0.0)
                    start_y = active_trial.get('start_y', 0.0)
                    
                    result_data = data.get('result', {})
                    final_x = result_data.get('final_cursor_x', start_x)
                    final_y = result_data.get('final_cursor_y', start_y)
                    
                    actual_dx = final_x - start_x
                    actual_dy = final_y - start_y
                    
                    scale_x = actual_dx / sum_dx if abs(sum_dx) > 0.01 else 1.0
                    scale_y = actual_dy / sum_dy if abs(sum_dy) > 0.01 else 1.0
                    
                    curr_x = start_x
                    curr_y = start_y
                    injected_count = 0
                    
                    for hw_ev in trial_hw_events:
                        curr_x += hw_ev['dx'] * scale_x
                        curr_y += hw_ev['dy'] * scale_y
                        
                        event_json = create_event_json(hw_ev, active_trial, global_event_counter, curr_x, curr_y)
                        outf.write(json.dumps(event_json) + '\n')
                        
                        global_event_counter += 1
                        active_trial['local_index'] += 1
                        injected_count += 1
                    
                    # Записываем trial_end ТОЛЬКО ПОСЛЕ вставки движений
                    outf.write(line)
                    print(f"Trial {active_trial['id']} завершен. Инжектировано {injected_count} ОС-событий.")
                    active_trial = None
                else:
                    outf.write(line)
                    if kind == 'trial_start':
                        active_trial = {
                            'id': data.get('trial_id'),
                            'start_t': data.get('t_us'),
                            'p_id': data.get('participant_id', 'unknown'),
                            's_id': data.get('session_id', 'unknown'),
                            'local_index': 1,
                            'start_x': data.get('start_cursor', {}).get('x', 0.0),
                            'start_y': data.get('start_cursor', {}).get('y', 0.0)
                        }

        print(f"\nГотово! Финальный датасет сохранен в {output_path}")
    except Exception as e:
        print(f"Ошибка при слиянии файлов: {e}")

if __name__ == "__main__":
    if len(sys.argv) >= 4:
        godot_log = sys.argv[1]
        os_log = sys.argv[2]
        output = sys.argv[3]
    else:
        godot_log = "s_0001_godot_ui_only.jsonl" 
        os_log = "raw_mouse_data.csv"
        output = "s_0001_raw.jsonl"
    
    if not os.path.exists(godot_log) or not os.path.exists(os_log):
        print(f"Внимание: Для работы скрипта убедитесь, что файлы '{godot_log}' и '{os_log}' существуют.")
        sys.exit(1)
    else:
        merge_logs(godot_log, os_log, output)
