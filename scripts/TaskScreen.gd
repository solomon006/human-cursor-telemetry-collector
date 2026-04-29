extends Control

@onready var target = $Target
@onready var progress_label = $ProgressLabel
@onready var background = $Background

var completed_trials_in_block = 0
var current_trial_index = 0
var block_index = 1
var block_start_t_us = 0
var block_started = false

var cursor_pos = Vector2()

var target_shape = "square"
var target_rect = Rect2()
var target_center = Vector2()
var planned_target_center = Vector2()
var target_placement_clamped = false
var target_placement_adjusted_for_min_distance = false

var start_cursor_pos = Vector2()
var prev_click_pos = Vector2(-1, -1)
var target_shown_t_us = 0
var first_motion_t_us = 0
var target_enter_t_us = 0
var pointer_down_t_us = 0
var pointer_up_t_us = 0
var pointer_down_pos = Vector2()
var pointer_down_inside = false

var event_index_trial = 0
var num_motion_events = 0
var num_button_events = 0
var last_event_t_us = 0
var max_event_gap_us = 0
var event_gaps_us = []

var is_practice = true
var practice_trials_left = 10
var practice_trials_completed = 0

var screen_size = Vector2()
var active_trial_id = ""
var planned_condition = {}
var trial_invalid_reasons = []

var lost_focus_during_trial = false
var window_resized_during_trial = false
var left_viewport = false
var non_left_button_used = false
var button_held_during_movement = false
var was_inside_target = false
var entered_target_count = 0
var left_target_after_enter = false

func _ready():
	Input.use_accumulated_input = false
	screen_size = get_viewport_rect().size
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	cursor_pos = get_viewport().get_mouse_position()
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	target.hide()
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.custom_minimum_size = Vector2.ZERO
	target.clip_text = true
	target.text = ""
	var target_style = StyleBoxFlat.new()
	target_style.bg_color = Color(0.2, 0.8, 0.3)
	target_style.border_width_bottom = 2
	target_style.border_width_top = 2
	target_style.border_width_left = 2
	target_style.border_width_right = 2
	target_style.border_color = Color(1.0, 1.0, 1.0)
	target_style.corner_radius_bottom_left = 4
	target_style.corner_radius_bottom_right = 4
	target_style.corner_radius_top_left = 4
	target_style.corner_radius_top_right = 4
	target.add_theme_stylebox_override("normal", target_style)
	
	var hover_style = target_style.duplicate()
	hover_style.bg_color = Color(0.3, 0.9, 0.4)
	target.add_theme_stylebox_override("hover", hover_style)
	
	var pressed_style = target_style.duplicate()
	pressed_style.bg_color = Color(0.1, 0.6, 0.2)
	target.add_theme_stylebox_override("pressed", pressed_style)

	if ParticipantConfig.total_completed_trials >= AppConfig.total_trials:
		DataLogger.end_session()
		SceneManager.goto_scene("pre_form")
		return

	is_practice = ParticipantConfig.total_completed_trials == 0
	practice_trials_left = AppConfig.practice_trials if is_practice else 0
	completed_trials_in_block = ParticipantConfig.total_completed_trials % max(1, AppConfig.trials_per_block)

	DataLogger.start_session()

	if is_practice:
		DataLogger.log_event("practice_start", {
			"session_id": ParticipantConfig.session_id,
			"participant_id": ParticipantConfig.participant_id,
			"t_us": Time.get_ticks_usec(),
			"planned_practice_trials": AppConfig.practice_trials
		})
	else:
		_start_block()

	# Небольшая задержка перед спавном, чтобы не засчитать двойной клик с прошлого экрана.
	await get_tree().create_timer(0.2).timeout
	spawn_target()

func _exit_tree():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func spawn_target():
	if not is_practice and ParticipantConfig.total_completed_trials >= AppConfig.total_trials:
		_finish_experiment()
		return

	screen_size = get_viewport_rect().size
	cursor_pos = get_viewport().get_mouse_position()
	start_cursor_pos = cursor_pos
	var condition_index = practice_trials_completed if is_practice else ParticipantConfig.total_completed_trials
	planned_condition = AppConfig.get_condition(condition_index)

	target_shape = str(planned_condition.get("target_shape", "square"))
	var target_dimensions = _dimensions_for_shape(target_shape, float(planned_condition.get("target_size_level_px", 48.0)))
	var placement = _place_target(start_cursor_pos, target_dimensions, planned_condition)
	target_center = placement["center"]
	planned_target_center = placement["planned_center"]
	target_placement_clamped = placement["clamped"]
	target_placement_adjusted_for_min_distance = placement["adjusted_for_min_distance"]
	target_rect = Rect2(target_center - target_dimensions / 2.0, target_dimensions)

	target.position = target_rect.position
	target.size = target_rect.size
	target.show()
	_update_progress_label()

	target_shown_t_us = Time.get_ticks_usec()
	current_trial_index = DataLogger.next_trial_index()
	event_index_trial = 0
	num_motion_events = 0
	num_button_events = 0
	last_event_t_us = 0
	max_event_gap_us = 0
	event_gaps_us.clear()
	first_motion_t_us = 0
	target_enter_t_us = 0
	pointer_down_t_us = 0
	pointer_up_t_us = 0
	pointer_down_pos = Vector2()
	pointer_down_inside = false
	trial_invalid_reasons.clear()
	lost_focus_during_trial = false
	window_resized_during_trial = false
	left_viewport = false
	non_left_button_used = false
	button_held_during_movement = false
	was_inside_target = target_rect.has_point(start_cursor_pos)
	entered_target_count = 1 if was_inside_target else 0
	left_target_after_enter = false

	active_trial_id = "t_%s_%04d" % [ParticipantConfig.session_id, current_trial_index]
	var experiment_trial_index = 0 if is_practice else ParticipantConfig.total_completed_trials + 1

	var data = {
		"trial_id": active_trial_id,
		"session_id": ParticipantConfig.session_id,
		"participant_id": ParticipantConfig.participant_id,
		"trial_index_session": current_trial_index,
		"trial_index_experiment": experiment_trial_index,
		"block_index": block_index,
		"is_practice": is_practice,
		"trial_type": "point_and_click",
		"t_us": target_shown_t_us,
		"start_cursor": _vector_to_dict(start_cursor_pos),
		"condition": planned_condition.duplicate(true),
		"target_acquisition_rule": {
			"success_requires_pointer_down_inside": true,
			"success_requires_pointer_up_inside": true,
			"success_requires_left_button": true,
			"allowed_buttons": ["left"]
		},
		"target": {
			"shape": target_shape,
			"center_x": target_center.x,
			"center_y": target_center.y,
			"bbox": _rect_to_dict(target_rect),
			"radius": null
		},
		"placement": {
			"planned_center": _vector_to_dict(planned_target_center),
			"clamped_to_viewport": target_placement_clamped,
			"adjusted_for_min_distance": target_placement_adjusted_for_min_distance
		},
		"task_geometry": _compute_geometry(start_cursor_pos, target_center, target_rect.size),
		"timing": {
			"target_shown_t_us": target_shown_t_us
		}
	}

	if prev_click_pos.x >= 0:
		data["previous_target_click"] = _vector_to_dict(prev_click_pos)

	DataLogger.log_event("trial_start", data)

func _input(event):
	# Если цель еще не показана, игнорируем ввод.
	if target_shown_t_us == 0:
		return

	if event is InputEventMouseMotion and not event.relative.is_zero_approx():
		cursor_pos = event.position
		log_mouse_event(event, "mouse_motion", cursor_pos)

	elif event is InputEventMouseButton:
		cursor_pos = event.position
		var event_type = "mouse_button_down" if event.pressed else "mouse_button_up"
		if event.button_index != MOUSE_BUTTON_LEFT:
			non_left_button_used = true
			_add_invalid_reason("non_left_button")

		log_mouse_event(event, event_type, cursor_pos)

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				pointer_down_pos = cursor_pos
				pointer_down_t_us = Time.get_ticks_usec()
				pointer_down_inside = target_rect.has_point(cursor_pos)
			else:
				if pointer_down_t_us == 0:
					_add_invalid_reason("missing_pointer_down")
					
				# Расширяем зону попадания на 3 пикселя для учета микродвижений при отпускании кнопки
				var padded_rect = target_rect.grow(3.0)
				var pointer_up_inside = padded_rect.has_point(cursor_pos)
				var pointer_down_inside_padded = padded_rect.has_point(pointer_down_pos)
				
				var success = pointer_down_inside_padded and pointer_up_inside
				if success:
					finish_trial(true, cursor_pos)
				else:
					# Записываем промах, показываем фидбек, но не завершаем попытку
					_flash_miss()
					DataLogger.log_event("quality_event", {
						"session_id": ParticipantConfig.session_id,
						"participant_id": ParticipantConfig.participant_id,
						"trial_id": active_trial_id,
						"event_type": "missed_click",
						"t_us": Time.get_ticks_usec(),
						"position": _vector_to_dict(cursor_pos)
					})
					pointer_down_t_us = 0
					pointer_down_inside = false

func log_mouse_event(event, type_str: String, pos: Vector2):
	var event_t_us = Time.get_ticks_usec()
	_update_event_quality(event, event_t_us, pos)
	_update_target_crossing(pos, event_t_us)

	event_index_trial += 1
	DataLogger.event_index_global += 1

	var phase = _phase_for_event(event, type_str, pos)
	var data = {
		"event_id": "e_%08d" % DataLogger.event_index_global,
		"participant_id": ParticipantConfig.participant_id,
		"session_id": ParticipantConfig.session_id,
		"trial_id": active_trial_id,
		"event_index_global": DataLogger.event_index_global,
		"event_index_trial": event_index_trial,
		"event_type": type_str,
		"phase": phase,
		"t_us_abs": event_t_us,
		"t_us_trial": event_t_us - target_shown_t_us,
		"t_ms_trial": float(event_t_us - target_shown_t_us) / 1000.0,
		"position": _vector_to_dict(pos),
		"buttons": _buttons_to_dict(event.button_mask),
		"state": {
			"cursor_inside_target": target_rect.has_point(pos),
			"target_visible": true,
			"left_viewport": left_viewport
		},
		"raw": {
			"godot_event_class": event.get_class(),
			"event_position_x": event.position.x,
			"event_position_y": event.position.y
		}
	}

	if event is InputEventMouseMotion:
		data["relative"] = {"dx": event.relative.x, "dy": event.relative.y}
		data["raw"]["event_relative_x"] = event.relative.x
		data["raw"]["event_relative_y"] = event.relative.y
		data["raw"]["event_velocity_x"] = event.velocity.x
		data["raw"]["event_velocity_y"] = event.velocity.y

	if event is InputEventMouseButton:
		data["button"] = {
			"button_index": event.button_index,
			"button_name": _button_name(event.button_index),
			"pressed": event.pressed
		}

	DataLogger.log_event("event", data)

func finish_trial(success: bool, pointer_up_pos: Vector2):
	target.hide()
	target_shown_t_us = 0 # Блокируем ввод до спавна следующей цели.
	pointer_up_t_us = Time.get_ticks_usec()

	if not success:
		_add_invalid_reason("target_acquisition_failed")
	if num_motion_events == 0:
		_add_invalid_reason("no_motion_events")
	if max_event_gap_us > 500000:
		_add_invalid_reason("large_event_gap")

	var valid_trial = success and trial_invalid_reasons.is_empty()
	var geometry = _compute_geometry(start_cursor_pos, target_center, target_rect.size)

	DataLogger.log_event("trial_end", {
		"trial_id": active_trial_id,
		"session_id": ParticipantConfig.session_id,
		"participant_id": ParticipantConfig.participant_id,
		"trial_index_session": current_trial_index,
		"trial_index_experiment": 0 if is_practice else ParticipantConfig.total_completed_trials + 1,
		"block_index": block_index,
		"is_practice": is_practice,
		"t_us": pointer_up_t_us,
		"success": success,
		"condition": planned_condition.duplicate(true),
		"start_cursor": _vector_to_dict(start_cursor_pos),
		"target": {
			"shape": target_shape,
			"center_x": target_center.x,
			"center_y": target_center.y,
			"bbox": _rect_to_dict(target_rect)
		},
		"task_geometry": geometry,
		"timing": _trial_timing(pointer_up_t_us),
		"result": {
			"success": success,
			"pointer_down_x": pointer_down_pos.x,
			"pointer_down_y": pointer_down_pos.y,
			"pointer_up_x": pointer_up_pos.x,
			"pointer_up_y": pointer_up_pos.y,
			"final_cursor_x": pointer_up_pos.x,
			"final_cursor_y": pointer_up_pos.y,
			"endpoint_error_px": pointer_up_pos.distance_to(target_center),
			"pointer_down_inside_target": pointer_down_inside,
			"pointer_up_inside_target": target_rect.has_point(pointer_up_pos),
			"click_inside_target": success,
			"entered_target_count": entered_target_count,
			"left_target_after_enter": left_target_after_enter
		},
		"quality": {
			"num_events": event_index_trial,
			"num_motion_events": num_motion_events,
			"num_button_events": num_button_events,
			"max_event_gap_ms": float(max_event_gap_us) / 1000.0,
			"median_event_gap_ms": _median_gap_ms(),
			"button_held_during_movement": button_held_during_movement,
			"non_left_button_used": non_left_button_used,
			"lost_focus_during_trial": lost_focus_during_trial,
			"window_resized_during_trial": window_resized_during_trial,
			"left_viewport": left_viewport,
			"valid_trial": valid_trial,
			"invalid_reasons": trial_invalid_reasons.duplicate()
		}
	})

	DataLogger.total_trials_in_session += 1
	if valid_trial:
		DataLogger.valid_trials_in_session += 1

	prev_click_pos = pointer_up_pos

	if is_practice:
		practice_trials_left -= 1
		practice_trials_completed += 1
		if practice_trials_left <= 0:
			is_practice = false
			DataLogger.log_event("practice_end", {
				"session_id": ParticipantConfig.session_id,
				"participant_id": ParticipantConfig.participant_id,
				"t_us": pointer_up_t_us,
				"completed_practice_trials": practice_trials_completed
			})
			_start_block()
	else:
		completed_trials_in_block += 1
		ParticipantConfig.total_completed_trials += 1
		ParticipantConfig.save_state()

		if ParticipantConfig.total_completed_trials >= AppConfig.total_trials:
			_finish_experiment()
			return

		if completed_trials_in_block >= AppConfig.trials_per_block:
			_end_current_block("scheduled_break")
			completed_trials_in_block = 0
			DataLogger.flush()
			SceneManager.goto_scene("break")
			return

	spawn_target()

func _start_block():
	if block_started:
		return

	block_index = int(ParticipantConfig.total_completed_trials / max(1, AppConfig.trials_per_block)) + 1
	block_start_t_us = Time.get_ticks_usec()
	block_started = true
	DataLogger.log_event("block_start", {
		"session_id": ParticipantConfig.session_id,
		"participant_id": ParticipantConfig.participant_id,
		"block_index": block_index,
		"t_us": block_start_t_us,
		"completed_trials_before_block": ParticipantConfig.total_completed_trials,
		"trials_per_block": AppConfig.trials_per_block
	})

func _end_current_block(reason: String):
	if not block_started:
		return

	DataLogger.log_event("block_end", {
		"session_id": ParticipantConfig.session_id,
		"participant_id": ParticipantConfig.participant_id,
		"block_index": block_index,
		"t_us": Time.get_ticks_usec(),
		"duration_us": Time.get_ticks_usec() - block_start_t_us,
		"completed_trials_total": ParticipantConfig.total_completed_trials,
		"reason": reason
	})
	block_started = false

func _place_target(origin: Vector2, target_dimensions: Vector2, condition: Dictionary) -> Dictionary:
	var distance = max(float(condition.get("distance_level_px", 300.0)), AppConfig.min_target_distance_px)
	var direction_deg = float(condition.get("direction_level_deg", 0.0))
	var direction = Vector2(cos(deg_to_rad(direction_deg)), sin(deg_to_rad(direction_deg)))
	var planned_center = origin + direction * distance
	var clamped_center = _clamp_center_to_screen(planned_center, target_dimensions)
	var clamped = planned_center.distance_to(clamped_center) > 0.01

	if origin.distance_to(clamped_center) >= AppConfig.min_target_distance_px:
		return {
			"center": clamped_center,
			"planned_center": planned_center,
			"clamped": clamped,
			"adjusted_for_min_distance": false
		}

	var best_center = clamped_center
	var best_planned_center = planned_center
	var best_distance = origin.distance_to(clamped_center)
	var offsets = [45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]
	for offset in offsets:
		var adjusted_direction = Vector2(cos(deg_to_rad(direction_deg + offset)), sin(deg_to_rad(direction_deg + offset)))
		var candidate_planned = origin + adjusted_direction * distance
		var candidate_center = _clamp_center_to_screen(candidate_planned, target_dimensions)
		var candidate_distance = origin.distance_to(candidate_center)
		if candidate_distance > best_distance:
			best_center = candidate_center
			best_planned_center = candidate_planned
			best_distance = candidate_distance
		if candidate_distance >= AppConfig.min_target_distance_px:
			break

	return {
		"center": best_center,
		"planned_center": best_planned_center,
		"clamped": best_planned_center.distance_to(best_center) > 0.01,
		"adjusted_for_min_distance": true
	}

func _clamp_center_to_screen(center: Vector2, target_dimensions: Vector2) -> Vector2:
	var half = target_dimensions / 2.0
	var margin = AppConfig.target_margin_px
	var min_x = margin + half.x
	var max_x = screen_size.x - margin - half.x
	var min_y = margin + half.y
	var max_y = screen_size.y - margin - half.y

	if max_x < min_x:
		min_x = half.x
		max_x = screen_size.x - half.x
	if max_y < min_y:
		min_y = half.y
		max_y = screen_size.y - half.y

	return Vector2(clamp(center.x, min_x, max_x), clamp(center.y, min_y, max_y))

func _dimensions_for_shape(shape: String, nominal_size: float) -> Vector2:
	match shape:
		"rectangle_wide":
			return Vector2(nominal_size * 2.0, nominal_size)
		"rectangle_tall":
			return Vector2(nominal_size, nominal_size * 2.0)
		_:
			return Vector2(nominal_size, nominal_size)

func _compute_geometry(origin: Vector2, center: Vector2, target_dimensions: Vector2) -> Dictionary:
	var movement = center - origin
	var distance = movement.length()
	var direction_rad = atan2(movement.y, movement.x)
	var effective_width = target_dimensions.x * abs(cos(direction_rad)) + target_dimensions.y * abs(sin(direction_rad))
	effective_width = max(effective_width, 1.0)
	return {
		"distance_px": distance,
		"direction_rad": direction_rad,
		"direction_deg": rad_to_deg(direction_rad),
		"target_width_raw_px": target_dimensions.x,
		"target_height_raw_px": target_dimensions.y,
		"target_width_effective_px": effective_width,
		"id_shannon": log(distance / effective_width + 1.0) / log(2.0),
		"id_classic": log(max((2.0 * distance) / effective_width, 1.0)) / log(2.0)
	}

func _trial_timing(trial_end_t_us: int) -> Dictionary:
	var dict = {
		"target_shown_t_us": target_shown_t_us,
		"movement_start_t_us": null,
		"target_enter_t_us": null,
		"pointer_down_t_us": null,
		"pointer_up_t_us": pointer_up_t_us,
		"trial_end_t_us": trial_end_t_us,
		"reaction_time_ms": null,
		"movement_time_ms": null,
		"click_hold_time_ms": null,
		"total_trial_time_ms": float(trial_end_t_us - target_shown_t_us) / 1000.0
	}
	if first_motion_t_us > 0:
		dict["movement_start_t_us"] = first_motion_t_us
		dict["reaction_time_ms"] = float(first_motion_t_us - target_shown_t_us) / 1000.0
	if target_enter_t_us > 0:
		dict["target_enter_t_us"] = target_enter_t_us
	if pointer_down_t_us > 0:
		dict["pointer_down_t_us"] = pointer_down_t_us
		dict["click_hold_time_ms"] = float(pointer_up_t_us - pointer_down_t_us) / 1000.0
	if first_motion_t_us > 0 and pointer_down_t_us > 0:
		dict["movement_time_ms"] = float(pointer_down_t_us - first_motion_t_us) / 1000.0
	return dict

func _update_event_quality(event, event_t_us: int, pos: Vector2):
	if last_event_t_us > 0:
		var gap = event_t_us - last_event_t_us
		event_gaps_us.append(gap)
		max_event_gap_us = max(max_event_gap_us, gap)
	last_event_t_us = event_t_us

	if event is InputEventMouseMotion:
		num_motion_events += 1
		if first_motion_t_us == 0:
			first_motion_t_us = event_t_us
		if pointer_down_t_us == 0 and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			button_held_during_movement = true
			_add_invalid_reason("button_held_during_movement")

	if event is InputEventMouseButton:
		num_button_events += 1

	if not _position_inside_viewport(pos):
		left_viewport = true
		_add_invalid_reason("left_viewport")

func _update_target_crossing(position: Vector2, event_t_us: int):
	var inside = target_rect.has_point(position)
	if inside and not was_inside_target:
		entered_target_count += 1
		if target_enter_t_us == 0:
			target_enter_t_us = event_t_us
	if not inside and was_inside_target and entered_target_count > 0:
		left_target_after_enter = true
	was_inside_target = inside

func _phase_for_event(event, type_str: String, pos: Vector2) -> String:
	if type_str == "mouse_button_down" or type_str == "mouse_button_up":
		return "click"
	if first_motion_t_us == 0:
		return "reaction"
	if target_rect.has_point(pos):
		return "inside_target"
	return "movement"

func _add_invalid_reason(reason: String):
	if not trial_invalid_reasons.has(reason):
		trial_invalid_reasons.append(reason)

func _median_gap_ms():
	if event_gaps_us.is_empty():
		return null

	var sorted_gaps = event_gaps_us.duplicate()
	sorted_gaps.sort()
	var middle = int(sorted_gaps.size() / 2.0)
	if sorted_gaps.size() % 2 == 1:
		return float(sorted_gaps[middle]) / 1000.0
	return float(sorted_gaps[middle - 1] + sorted_gaps[middle]) / 2000.0

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

func _position_inside_viewport(pos: Vector2) -> bool:
	return pos.x >= 0.0 and pos.y >= 0.0 and pos.x <= screen_size.x and pos.y <= screen_size.y

func _vector_to_dict(vector: Vector2) -> Dictionary:
	return {"x": vector.x, "y": vector.y}

func _rect_to_dict(rect: Rect2) -> Dictionary:
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"width": rect.size.x,
		"height": rect.size.y
	}

func _on_viewport_size_changed():
	screen_size = get_viewport_rect().size
	if target_shown_t_us != 0:
		window_resized_during_trial = true
		_add_invalid_reason("window_resized")
		DataLogger.window_resize_count += 1
		DataLogger.log_event("quality_event", {
			"session_id": ParticipantConfig.session_id,
			"participant_id": ParticipantConfig.participant_id,
			"trial_id": active_trial_id,
			"event_type": "window_resized",
			"t_us": Time.get_ticks_usec(),
			"viewport_width_px": screen_size.x,
			"viewport_height_px": screen_size.y
		})

func _notification(what):
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and target_shown_t_us != 0:
		lost_focus_during_trial = true
		_add_invalid_reason("lost_focus")
		DataLogger.lost_focus_count += 1
		DataLogger.log_event("quality_event", {
			"session_id": ParticipantConfig.session_id,
			"participant_id": ParticipantConfig.participant_id,
			"trial_id": active_trial_id,
			"event_type": "lost_focus",
			"t_us": Time.get_ticks_usec()
		})

func _unhandled_key_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# Безопасная пауза: скрываем цель, сохраняем прогресс, уходим на перерыв.
		# Текущий trial (если активен) останется без trial_end — нормализатор это обработает.
		target.hide()
		target_shown_t_us = 0
		if block_started:
			_end_current_block("user_paused")
		DataLogger.flush()
		SceneManager.goto_scene("break")

func _finish_experiment():
	_end_current_block("experiment_completed")
	DataLogger.end_session()
	SceneManager.goto_scene("pre_form")

func _update_progress_label():
	if progress_label == null:
		return
	if is_practice:
		progress_label.text = "Тренировка: %d / %d" % [practice_trials_completed, AppConfig.practice_trials]
	else:
		var done = ParticipantConfig.total_completed_trials
		var total = AppConfig.total_trials
		progress_label.text = "%d / %d" % [done, total]

func _flash_miss():
	if background == null:
		return
	var original_color = Color(0.08, 0.08, 0.09, 1)
	var flash_color = Color(0.25, 0.08, 0.08, 1)
	var tween = create_tween()
	tween.tween_property(background, "color", flash_color, 0.06)
	tween.tween_property(background, "color", original_color, 0.15)
