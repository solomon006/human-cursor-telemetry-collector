extends Node

var participant_id: String = ""
var session_id: String = ""

# Данные опросника
var is_consent_given: bool = false
var age_group: String = ""
var handedness: String = ""
var device_type: String = ""
var usual_mouse_hand: String = ""
var mouse_experience: String = "normal"
var total_completed_trials: int = 0

func generate_ids():
	participant_id = _make_id("p")
	generate_session_id()

func generate_session_id():
	session_id = _make_id("s")

func get_participant_dict() -> Dictionary:
	return {
		"participant_id": participant_id,
		"created_at_utc": Time.get_datetime_string_from_system(true, true),
		"consent_given": is_consent_given,
		"demographics": {
			"age_group": age_group,
			"handedness": handedness
		},
		"self_report": {
			"device_type": device_type,
			"usual_mouse_hand": usual_mouse_hand,
			"mouse_experience": mouse_experience
		},
		"notes": null
	}

func save_state():
	var file = FileAccess.open("user://participant_state.json", FileAccess.WRITE)
	if file:
		var data = {
			"participant_id": participant_id,
			"session_id": session_id,
			"is_consent_given": is_consent_given,
			"total_completed_trials": total_completed_trials,
			"age_group": age_group,
			"handedness": handedness,
			"device_type": device_type,
			"usual_mouse_hand": usual_mouse_hand,
			"mouse_experience": mouse_experience
		}
		file.store_string(JSON.stringify(data))

func load_state() -> bool:
	if FileAccess.file_exists("user://participant_state.json"):
		var file = FileAccess.open("user://participant_state.json", FileAccess.READ)
		var txt = file.get_as_text()
		var dict = JSON.parse_string(txt)
		if dict and dict.has("participant_id"):
			participant_id = dict["participant_id"]
			session_id = dict.get("session_id", session_id)
			is_consent_given = dict.get("is_consent_given", false)
			total_completed_trials = dict.get("total_completed_trials", 0)
			age_group = dict.get("age_group", "")
			handedness = dict.get("handedness", "")
			device_type = dict.get("device_type", "")
			usual_mouse_hand = dict.get("usual_mouse_hand", "")
			mouse_experience = dict.get("mouse_experience", "normal")
			return true
	return false

func _make_id(prefix: String) -> String:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var dt = Time.get_datetime_dict_from_system(true)
	var timestamp = "%04d%02d%02dT%02d%02d%02dZ" % [
		int(dt["year"]),
		int(dt["month"]),
		int(dt["day"]),
		int(dt["hour"]),
		int(dt["minute"]),
		int(dt["second"])
	]
	var random_hex = ""
	for i in range(4):
		random_hex += "%04x" % rng.randi_range(0, 65535)
	return "%s_%s_%s" % [prefix, timestamp, random_hex]

func clear_state():
	if FileAccess.file_exists("user://participant_state.json"):
		var dir = DirAccess.open("user://")
		if dir:
			dir.remove("participant_state.json")
	
	total_completed_trials = 0
	is_consent_given = false
	participant_id = ""
	session_id = ""
	age_group = ""
	handedness = ""
	device_type = ""
	usual_mouse_hand = ""
	mouse_experience = "normal"
