extends Control

@onready var email1_btn = $CenterContainer/VBoxContainer/Email1Container/Email1Btn
@onready var email2_btn = $CenterContainer/VBoxContainer/Email2Container/Email2Btn
@onready var country_option = $CenterContainer/VBoxContainer/CountryContainer/CountryOption
@onready var agree_check = $CenterContainer/VBoxContainer/AgreeContainer/AgreeCheck

@onready var captcha_placeholder = $CenterContainer/VBoxContainer/CaptchaWrapper/Placeholder
@onready var captcha_placeholder_label = $CenterContainer/VBoxContainer/CaptchaWrapper/Placeholder/Label
@onready var captcha_box = $CenterContainer/VBoxContainer/CaptchaWrapper/CaptchaBox
@onready var captcha_btn = $CenterContainer/VBoxContainer/CaptchaWrapper/CaptchaBox/HBox/CaptchaBtn

@onready var submit_btn = $CenterContainer/VBoxContainer/SubmitBtn

var is_email1_clicked = false
var is_email2_clicked = false
var is_captcha_verified = false
var is_captcha_showing = false
var captcha_timer: Timer = null

# --- Telemetry ---
var cursor_pos = Vector2()
var last_click_pos = Vector2()
var last_click_t_us = 0
var form_shown_t_us = 0
var event_index_form = 0
var form_click_index = 0
var pointer_down_pos = Vector2()
var pointer_down_t_us = 0
var interactive_elements: Dictionary = {}

func _ready():
	Input.use_accumulated_input = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	country_option.add_item("Кыргызстан", 0)
	country_option.add_item("Россия", 1)
	country_option.add_item("Казахстан", 2)
	country_option.add_item("Узбекистан", 3)
	
	email1_btn.pressed.connect(_on_email1_pressed)
	email2_btn.pressed.connect(_on_email2_pressed)
	agree_check.toggled.connect(_on_agree_toggled)
	captcha_btn.pressed.connect(_on_captcha_btn_pressed)
	captcha_box.gui_input.connect(_on_captcha_box_gui_input)
	submit_btn.pressed.connect(_on_submit_pressed)
	
	submit_btn.disabled = true
	
	# Apply styling
	_apply_styles()
	
	# Create timer
	captcha_timer = Timer.new()
	captcha_timer.one_shot = true
	captcha_timer.timeout.connect(_on_captcha_timer_timeout)
	add_child(captcha_timer)

	# --- Telemetry init ---
	cursor_pos = get_viewport().get_mouse_position()
	last_click_pos = cursor_pos
	form_shown_t_us = DataLogger.get_current_unix_us()

	interactive_elements = {
		"email1_btn": email1_btn,
		"email2_btn": email2_btn,
		"country_option": country_option,
		"agree_check": agree_check,
		"captcha_btn": captcha_btn,
		"captcha_box": captcha_box,
		"submit_btn": submit_btn
	}

	DataLogger.log_event("form_start", {
		"session_id": ParticipantConfig.session_id,
		"participant_id": ParticipantConfig.participant_id,
		"t_us": form_shown_t_us,
		"cursor_pos": _vec(cursor_pos),
		"viewport": {
			"width": get_viewport_rect().size.x,
			"height": get_viewport_rect().size.y
		},
		"elements": _snapshot_all_elements()
	})

func _input(event):
	if form_shown_t_us == 0:
		return

	if event is InputEventMouseMotion and not event.relative.is_zero_approx():
		cursor_pos = event.position
		_log_mouse_event(event, "mouse_motion", cursor_pos)

	elif event is InputEventMouseButton:
		cursor_pos = event.position
		var type_str = "mouse_button_down" if event.pressed else "mouse_button_up"
		_log_mouse_event(event, type_str, cursor_pos)

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				pointer_down_pos = cursor_pos
				pointer_down_t_us = DataLogger.get_current_unix_us()
			else:
				_log_form_click(cursor_pos)

func _log_mouse_event(event, type_str: String, pos: Vector2):
	var event_t_us = DataLogger.get_current_unix_us()
	event_index_form += 1
	DataLogger.event_index_global += 1

	# var data = ...
	# DataLogger.log_event("event", data)

func _log_form_click(pos: Vector2):
	var now = DataLogger.get_current_unix_us()
	form_click_index += 1
	var clicked_element_id = _find_element_at(pos)

	var element_data = null
	if clicked_element_id != "":
		var node = interactive_elements[clicked_element_id]
		var rect = node.get_global_rect()
		var center = rect.position + rect.size / 2.0
		var distance = last_click_pos.distance_to(center)
		var movement = center - last_click_pos
		var direction_rad = atan2(movement.y, movement.x)
		var effective_width = rect.size.x * abs(cos(direction_rad)) + rect.size.y * abs(sin(direction_rad))
		effective_width = max(effective_width, 1.0)

		element_data = {
			"element_id": clicked_element_id,
			"bbox": _rect_dict(rect),
			"center": _vec(center),
			"effective_width_px": effective_width,
			"id_shannon": log(distance / effective_width + 1.0) / log(2.0) if distance > 0 else 0.0,
		}

	var data = {
		"session_id": ParticipantConfig.session_id,
		"participant_id": ParticipantConfig.participant_id,
		"form_click_index": form_click_index,
		"context": "form",
		"t_us": now,
		"t_us_form": now - form_shown_t_us,
		"click_position": _vec(pos),
		"pointer_down_position": _vec(pointer_down_pos),
		"start_cursor": _vec(last_click_pos),
		"distance_from_last_click_px": last_click_pos.distance_to(pos),
		"time_since_last_click_ms": float(now - last_click_t_us) / 1000.0 if last_click_t_us > 0 else null,
		"click_hold_time_ms": float(now - pointer_down_t_us) / 1000.0 if pointer_down_t_us > 0 else null,
		"element": element_data,
		"all_elements": _snapshot_all_elements()
	}

	DataLogger.log_event("form_click", data)

	last_click_pos = pos
	last_click_t_us = now
	pointer_down_t_us = 0

func _find_element_at(pos: Vector2) -> String:
	for element_id in interactive_elements:
		var node = interactive_elements[element_id]
		if node.visible and node.get_global_rect().has_point(pos):
			return element_id
	return ""

func _snapshot_all_elements() -> Dictionary:
	var snapshot = {}
	for element_id in interactive_elements:
		var node = interactive_elements[element_id]
		var rect = node.get_global_rect()
		var info = {
			"bbox": _rect_dict(rect),
			"visible": node.visible
		}
		if node is Button:
			info["disabled"] = node.disabled
		snapshot[element_id] = info
	return snapshot

# --- Existing form logic (unchanged) ---

func _apply_styles():
	var empty_btn_style = StyleBoxFlat.new()
	empty_btn_style.bg_color = Color("#32353c")
	empty_btn_style.border_width_bottom = 1
	empty_btn_style.border_width_top = 1
	empty_btn_style.border_width_left = 1
	empty_btn_style.border_width_right = 1
	empty_btn_style.border_color = Color("#32353c")
	empty_btn_style.corner_radius_top_left = 2
	empty_btn_style.corner_radius_top_right = 2
	empty_btn_style.corner_radius_bottom_right = 2
	empty_btn_style.corner_radius_bottom_left = 2
	
	var filled_btn_style = empty_btn_style.duplicate()
	filled_btn_style.border_color = Color("#4b515a")
	
	email1_btn.add_theme_stylebox_override("normal", empty_btn_style)
	email1_btn.add_theme_stylebox_override("hover", empty_btn_style)
	email1_btn.add_theme_stylebox_override("pressed", filled_btn_style)
	
	email2_btn.add_theme_stylebox_override("normal", empty_btn_style)
	email2_btn.add_theme_stylebox_override("hover", empty_btn_style)
	email2_btn.add_theme_stylebox_override("pressed", filled_btn_style)
	
	country_option.add_theme_stylebox_override("normal", empty_btn_style)
	country_option.add_theme_stylebox_override("hover", empty_btn_style)
	country_option.add_theme_stylebox_override("pressed", filled_btn_style)

	var captcha_box_style = StyleBoxFlat.new()
	captcha_box_style.bg_color = Color("#ffffff")
	captcha_box_style.border_width_bottom = 1
	captcha_box_style.border_width_top = 1
	captcha_box_style.border_width_left = 1
	captcha_box_style.border_width_right = 1
	captcha_box_style.border_color = Color("#c1c1c1")
	captcha_box_style.corner_radius_top_left = 2
	captcha_box_style.corner_radius_top_right = 2
	captcha_box_style.corner_radius_bottom_right = 2
	captcha_box_style.corner_radius_bottom_left = 2
	
	captcha_btn.add_theme_stylebox_override("normal", captcha_box_style)
	captcha_btn.add_theme_stylebox_override("hover", captcha_box_style)
	captcha_btn.add_theme_stylebox_override("pressed", captcha_box_style)
	captcha_btn.add_theme_stylebox_override("disabled", captcha_box_style)

	var submit_style = StyleBoxFlat.new()
	submit_style.bg_color = Color("#1a44c2")
	submit_style.corner_radius_top_left = 2
	submit_style.corner_radius_top_right = 2
	submit_style.corner_radius_bottom_left = 2
	submit_style.corner_radius_bottom_right = 2
	submit_btn.add_theme_stylebox_override("normal", submit_style)
	
	var submit_hover = submit_style.duplicate()
	submit_hover.bg_color = Color("#2a55d4")
	submit_btn.add_theme_stylebox_override("hover", submit_hover)
	
	var submit_disabled = submit_style.duplicate()
	submit_disabled.bg_color = Color("#4d5257")
	submit_btn.add_theme_stylebox_override("disabled", submit_disabled)

func _on_email1_pressed():
	is_email1_clicked = true
	email1_btn.text = " user@example.com (имитация ввода)"
	email1_btn.add_theme_color_override("font_color", Color("#66c0f4"))
	check_progress()

func _on_email2_pressed():
	is_email2_clicked = true
	email2_btn.text = " user@example.com (имитация ввода)"
	email2_btn.add_theme_color_override("font_color", Color("#66c0f4"))
	check_progress()

func _on_agree_toggled(_toggled_on: bool):
	check_progress()

func _on_captcha_box_gui_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_captcha_btn_pressed()

func _on_captcha_btn_pressed():
	if is_captcha_showing and not is_captcha_verified:
		is_captcha_verified = true
		captcha_btn.text = "V"
		captcha_btn.add_theme_color_override("font_color", Color("#00838f"))
		update_submit_status()

func check_progress():
	var is_agreed = agree_check.button_pressed
	
	if is_email1_clicked and is_email2_clicked and is_agreed:
		if not is_captcha_showing and captcha_timer.is_stopped():
			captcha_placeholder_label.text = "Проверка данных..."
			captcha_placeholder_label.add_theme_color_override("font_color", Color("#8f98a0"))
			captcha_timer.start(2.0)
	else:
		captcha_timer.stop()
		is_captcha_verified = false
		is_captcha_showing = false
		captcha_btn.text = ""
		captcha_box.visible = false
		
		captcha_placeholder_label.text = "Ожидание заполнения данных..."
		captcha_placeholder_label.add_theme_color_override("font_color", Color("#4f535b"))
		captcha_placeholder.visible = true
	
	update_submit_status()

func _on_captcha_timer_timeout():
	captcha_placeholder.visible = false
	captcha_box.visible = true
	is_captcha_showing = true
	update_submit_status()

func update_submit_status():
	submit_btn.disabled = not (is_email1_clicked and is_email2_clicked and agree_check.button_pressed and is_captcha_verified)

func _on_submit_pressed():
	DataLogger.log_event("form_completed", {
		"session_id": ParticipantConfig.session_id,
		"participant_id": ParticipantConfig.participant_id,
		"t_us": DataLogger.get_current_unix_us(),
		"t_us_form": DataLogger.get_current_unix_us() - form_shown_t_us,
		"total_form_clicks": form_click_index,
		"total_form_events": event_index_form,
		"elements": _snapshot_all_elements()
	})
	SceneManager.goto_scene("thank_you")

# --- Telemetry helpers ---

func _vec(v: Vector2) -> Dictionary:
	return {"x": v.x, "y": v.y}

func _rect_dict(rect: Rect2) -> Dictionary:
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"width": rect.size.x,
		"height": rect.size.y
	}

func _buttons_to_dict(button_mask: int) -> Dictionary:
	return {
		"left": (button_mask & MOUSE_BUTTON_MASK_LEFT) != 0,
		"right": (button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0,
		"middle": (button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0,
		"button_mask_raw": button_mask
	}

func _button_name(button_index: int) -> String:
	match button_index:
		MOUSE_BUTTON_LEFT:
			return "left"
		MOUSE_BUTTON_RIGHT:
			return "right"
		MOUSE_BUTTON_MIDDLE:
			return "middle"
		MOUSE_BUTTON_WHEEL_UP:
			return "wheel_up"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "wheel_down"
		_:
			return "button_%d" % button_index
