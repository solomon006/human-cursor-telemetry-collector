import json
import csv
import sys
import os
from typing import List, Dict, Any

def parse_evdev_csv(csv_path: str) -> List[Dict[str, Any]]:
    """
    Парсит сырой CSV от ОС и группирует события по миллисекундам.
    """
    events = []
    
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
                    'clicks': []
                }
            
            if row['event_type'] == 'MOVE':
                if row['axis'] == 'X': 
                    current_group['dx'] += float(row['value'])
                elif row['axis'] == 'Y': 
                    current_group['dy'] += float(row['value'])
            elif row['event_type'] == 'CLICK':
                current_group['clicks'].append((row['axis'], row['value']))
            
            last_ts = ts
            
        if current_group:
            events.append(current_group)
            
    return events

def create_event_json(evdev_event: Dict, trial_meta: Dict, event_index: int) -> Dict:
    """
    Создает объект события для фазы trial.
    """
    is_click = len(evdev_event['clicks']) > 0
    event_type = "mouse_button" if is_click else "mouse_motion"
    
    obj = {
        "kind": "event",
        "data": {
            "event_id": f"e_sys_{event_index}",
            "participant_id": trial_meta['p_id'],
            "session_id": trial_meta['s_id'],
            "trial_id": trial_meta['id'],
            "event_index_global": event_index,
            "event_index_trial": trial_meta['local_index'],
            "event_type": event_type,
            "t_us_abs": evdev_event['t_us_abs'],
            "t_us_trial": evdev_event['t_us_abs'] - trial_meta['start_t'],
            "t_ms_trial": (evdev_event['t_us_abs'] - trial_meta['start_t']) / 1000.0,
            "relative": {
                "dx": evdev_event['dx'],
                "dy": evdev_event['dy']
            },
            "position": {"x": 0.0, "y": 0.0}, # Абсолютная позиция недоступна из evdev напрямую
            "raw": {
                "source": "evdev_os_level"
            }
        }
    }
    return obj

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
                    injected_count = 0
                    
                    while hw_index < hw_total:
                        hw_ev = hardware_events[hw_index]
                        
                        if hw_ev['t_us_abs'] < active_trial['start_t']:
                            hw_index += 1
                            continue
                            
                        if hw_ev['t_us_abs'] > end_t_us:
                            break
                            
                        event_json = create_event_json(hw_ev, active_trial, global_event_counter)
                        outf.write(json.dumps(event_json) + '\n')
                        
                        global_event_counter += 1
                        active_trial['local_index'] += 1
                        hw_index += 1
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
                            'local_index': 1
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
