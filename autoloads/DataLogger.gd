extends Node

var log_file: FileAccess
var raw_session_path: String = ""
var session_active: bool = false
var session_started_t_us: int = 0
var events_since_flush: int = 0
var flush_interval: int = 200

# Глобальные счетчики сессии
var event_index_global: int = 0
var trial_index_session: int = 0

# Управление внешними Python процессами
var data_collector_pid: int = -1
var evdev_csv_path: String = ""

# Session-level quality tracking
var lost_focus_count: int = 0
var window_resize_count: int = 0
var total_trials_in_session: int = 0
var valid_trials_in_session: int = 0

func _ready():
	_extract_tools()

func get_current_unix_us() -> int:
	return int(Time.get_unix_time_from_system() * 1_000_000.0)

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		end_session()

func start_session():
	if session_active and log_file != null:
		return

	if ParticipantConfig.session_id == "":
		ParticipantConfig.generate_session_id()

	# Создаем папку в user:// если её нет
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("raw_sessions"):
		dir.make_dir("raw_sessions")
	
	raw_session_path = "user://raw_sessions/" + ParticipantConfig.session_id + "_raw.jsonl"
	evdev_csv_path = "user://raw_sessions/" + ParticipantConfig.session_id + "_evdev.csv"
	log_file = FileAccess.open(raw_session_path, FileAccess.WRITE)
	
	if log_file:
		var python_script = ProjectSettings.globalize_path("user://tools/data_collector.py")
		var csv_out = ProjectSettings.globalize_path(evdev_csv_path)
		data_collector_pid = OS.create_process("python3", [python_script, csv_out])
		print("Started data collector with PID: ", data_collector_pid)
		
		session_active = true
		session_started_t_us = get_current_unix_us()
		event_index_global = 0
		trial_index_session = 0
		events_since_flush = 0
		lost_focus_count = 0
		window_resize_count = 0
		total_trials_in_session = 0
		valid_trials_in_session = 0

		# Сохраняем стартовые данные
		log_event("session_start", {
			"session_id": ParticipantConfig.session_id,
			"participant_id": ParticipantConfig.participant_id,
			"t_us": session_started_t_us,
			"started_at_utc": Time.get_datetime_string_from_system(true, true),
			"participant_info": ParticipantConfig.get_participant_dict(),
			"app": {
				"app_name": "MotorCursor",
				"app_version": "0.1.0",
				"schema_version": "1.0.0",
				"engine": "Godot",
				"godot_version": Engine.get_version_info().get("string", "unknown")
			},
			"system": {
				"os_name": OS.get_name(),
				"os_version": OS.get_version(),
				"processor_arch": Engine.get_architecture_name()
			},
			"display": _get_display_info(),
			"input": {
				"input_source": "mouse",
				"mouse_mode": Input.mouse_mode,
				"mouse_mode_name": _mouse_mode_name(Input.mouse_mode),
				"position_source": "InputEventMouse.position",
				"relative_source": "InputEventMouseMotion.relative",
				"timestamp_source": "Time.get_unix_time_from_system() * 1_000_000",
				"record_motion_events": false,
				"record_button_events": false,
				"accumulated_input_disabled": not Input.use_accumulated_input,
				"coordinate_system": {
					"space": "viewport_pixels",
					"origin": "top_left",
					"x_axis": "right_positive",
					"y_axis": "down_positive",
					"units": "pixels"
				}
			},
			"experiment": AppConfig.get_plan_summary(),
			"quality": {
				"lost_focus_count": 0,
				"window_resize_count": 0,
				"total_trials": 0,
				"valid_trials": 0,
				"session_completed": false,
				"valid_session": true
			}
		})
		log_file.flush()

func log_event(kind: String, data: Dictionary):
	if log_file == null:
		return
		
	var entry = {
		"kind": kind,
		"data": data
	}
	log_file.store_line(JSON.stringify(entry))
	events_since_flush += 1
	if events_since_flush >= flush_interval:
		flush()

func flush():
	if log_file != null:
		log_file.flush()
		events_since_flush = 0

func next_trial_index() -> int:
	trial_index_session += 1
	return trial_index_session

func end_session():
	if not session_active:
		return

	var is_completed = ParticipantConfig.total_completed_trials >= AppConfig.total_trials
	log_event("session_end", {
		"session_id": ParticipantConfig.session_id,
		"participant_id": ParticipantConfig.participant_id,
		"t_us": get_current_unix_us(),
		"ended_at_utc": Time.get_datetime_string_from_system(true, true),
		"duration_us": get_current_unix_us() - session_started_t_us,
		"session_completed": is_completed,
		"quality": {
			"lost_focus_count": lost_focus_count,
			"window_resize_count": window_resize_count,
			"total_trials": total_trials_in_session,
			"valid_trials": valid_trials_in_session,
			"session_completed": is_completed,
			"valid_session": is_completed and lost_focus_count == 0
		}
	})
	if log_file:
		log_file.flush()
		log_file.close()
		log_file = null
	session_active = false
	
	if data_collector_pid > 0:
		OS.kill(data_collector_pid)
		print("Killed data collector (PID: ", data_collector_pid, ")")
		data_collector_pid = -1
		
		var compiler_script = ProjectSettings.globalize_path("user://tools/schema_compiler.py")
		var godot_log = ProjectSettings.globalize_path(raw_session_path)
		var os_log = ProjectSettings.globalize_path(evdev_csv_path)
		var final_out = godot_log.replace("_raw.jsonl", "_fused.jsonl")
		
		print("Running schema compiler...")
		var output = []
		OS.execute("python3", [compiler_script, godot_log, os_log, final_out], output, true)
		for line in output:
			print(line)
		print("Fusion complete! Saved to ", final_out)
		
func export_to_desktop():
	if raw_session_path == "":
		push_error("Нет файла сессии для экспорта!")
		return

	flush()
	
	var desktop_path = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if desktop_path == "":
		push_error("Не удалось найти путь к рабочему столу")
		return
	
	var file_name = raw_session_path.get_file()
	var zip_name = file_name.replace(".jsonl", ".zip")
	var dest_path = desktop_path + "/" + zip_name
	
	var zipper = ZIPPacker.new()
	var err = zipper.open(dest_path)
	if err == OK:
		zipper.start_file(file_name)
		var f = FileAccess.open(raw_session_path, FileAccess.READ)
		if f:
			zipper.write_file(f.get_buffer(f.get_length()))
			f.close()
		zipper.close_file()
		zipper.close()
		print("Файл успешно заархивирован на рабочий стол: ", dest_path)
	else:
		push_error("Ошибка при создании ZIP-архива: ", err)

func _get_display_info() -> Dictionary:
	var screen_index = DisplayServer.window_get_current_screen()
	var screen_dpi = DisplayServer.screen_get_dpi(screen_index)
	var screen_size_px = DisplayServer.screen_get_size(screen_index)
	
	var diagonal_inches = 0.0
	if screen_dpi > 0:
		var w_in = float(screen_size_px.x) / float(screen_dpi)
		var h_in = float(screen_size_px.y) / float(screen_dpi)
		diagonal_inches = sqrt(w_in * w_in + h_in * h_in)
		
	return {
		"window_width_px": get_viewport().size.x,
		"window_height_px": get_viewport().size.y,
		"viewport_width_px": get_viewport().size.x,
		"viewport_height_px": get_viewport().size.y,
		"screen_index": screen_index,
		"window_mode": DisplayServer.window_get_mode(),
		"screen_width_px": screen_size_px.x,
		"screen_height_px": screen_size_px.y,
		"screen_dpi": screen_dpi,
		"screen_diagonal_inches": snapped(diagonal_inches, 0.01)
	}

func _mouse_mode_name(mouse_mode: int) -> String:
	match mouse_mode:
		Input.MOUSE_MODE_VISIBLE:
			return "visible"
		Input.MOUSE_MODE_HIDDEN:
			return "hidden"
		Input.MOUSE_MODE_CAPTURED:
			return "captured"
		Input.MOUSE_MODE_CONFINED:
			return "confined"
		Input.MOUSE_MODE_CONFINED_HIDDEN:
			return "confined_hidden"
		_:
			return "unknown"

func _extract_tools():
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("tools"):
		dir.make_dir("tools")
	
	for script in ["data_collector.py", "schema_compiler.py", "normalize_raw_sessions.py"]:
		var res_path = "res://tools/" + script
		var user_path = "user://tools/" + script
		var file_in = FileAccess.open(res_path, FileAccess.READ)
		if file_in:
			var content = file_in.get_as_text()
			file_in.close()
			var file_out = FileAccess.open(user_path, FileAccess.WRITE)
			if file_out:
				file_out.store_string(content)
				file_out.close()
