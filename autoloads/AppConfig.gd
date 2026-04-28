extends Node

var telegram_username: String = ""
var total_trials: int = 300
var trials_per_block: int = 100
var practice_trials: int = 10
var min_target_distance_px: float = 120.0
var target_margin_px: float = 64.0
var trial_plan_id: String = "fallback_random"
var trial_plan_seed: int = 0
var trial_conditions: Array = []

func _ready():
	load_config()

func load_config():
	var config = ConfigFile.new()
	# Сначала пробуем user:// (позволяет переопределить настройки без пересборки),
	# затем res:// (запечатан в экспорте).
	var err = config.load("user://config.cfg")
	if err != OK:
		err = config.load("res://config.cfg")
	if err == OK:
		telegram_username = config.get_value("telegram", "username", "")
		total_trials = config.get_value("experiment", "total_trials", 300)
		trials_per_block = config.get_value("experiment", "trials_per_block", 100)
		practice_trials = config.get_value("experiment", "practice_trials", 10)
	else:
		push_warning("config.cfg не найден, используем параметры по умолчанию.")

	load_trial_plan()

func load_trial_plan():
	trial_conditions.clear()

	if not FileAccess.file_exists("res://trial_plan.json"):
		push_warning("trial_plan.json не найден, используем fallback-условия.")
		return

	var file = FileAccess.open("res://trial_plan.json", FileAccess.READ)
	if file == null:
		push_warning("Не удалось открыть trial_plan.json.")
		return

	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_warning("trial_plan.json содержит некорректный JSON.")
		return

	trial_plan_id = str(parsed.get("plan_id", trial_plan_id))
	trial_plan_seed = int(parsed.get("shuffle_seed", 0))
	min_target_distance_px = float(parsed.get("min_target_distance_px", min_target_distance_px))
	target_margin_px = float(parsed.get("target_margin_px", target_margin_px))

	var distances: Array = parsed.get("distances_px", [150, 300, 600])
	var target_sizes: Array = parsed.get("target_sizes_px", [32, 64])
	var directions: Array = parsed.get("directions_deg", [0, 90, 180, 270])
	var target_shapes: Array = parsed.get("target_shapes", ["square"])
	var repeats = int(parsed.get("repeats", 1))

	for repeat_index in range(repeats):
		for distance in distances:
			for target_size in target_sizes:
				for direction in directions:
					var shape_index = trial_conditions.size() % max(1, target_shapes.size())
					var shape = str(target_shapes[shape_index])
					var condition = {
						"plan_id": trial_plan_id,
						"distance_level_px": float(distance),
						"target_size_level_px": float(target_size),
						"direction_level_deg": float(direction),
						"repeat_index": repeat_index + 1,
						"target_shape": shape,
						"condition_id": _make_condition_id(float(distance), float(target_size), float(direction), repeat_index + 1, shape)
					}
					trial_conditions.append(condition)

	if bool(parsed.get("shuffle_trials", true)):
		_shuffle_conditions(trial_plan_seed)

func get_condition(index: int) -> Dictionary:
	if trial_conditions.is_empty():
		return _fallback_condition(index)

	var plan_index = index % trial_conditions.size()
	var condition = trial_conditions[plan_index].duplicate(true)
	condition["plan_index"] = plan_index
	condition["condition_cycle"] = int(index / float(trial_conditions.size()))
	return condition

func get_plan_summary() -> Dictionary:
	return {
		"plan_id": trial_plan_id,
		"planned_trials": total_trials,
		"conditions_in_plan": trial_conditions.size(),
		"trials_per_block": trials_per_block,
		"practice_trials": practice_trials,
		"shuffle_seed": trial_plan_seed,
		"min_target_distance_px": min_target_distance_px,
		"target_margin_px": target_margin_px
	}

func _fallback_condition(index: int) -> Dictionary:
	var distances = [150.0, 300.0, 450.0]
	var sizes = [32.0, 48.0, 64.0]
	var directions = [0.0, 90.0, 180.0, 270.0]
	var shapes = ["square", "rectangle_wide", "rectangle_tall"]
	var distance = distances[index % distances.size()]
	var target_size = sizes[int(index / float(distances.size())) % sizes.size()]
	var direction = directions[int(index / float(distances.size() * sizes.size())) % directions.size()]
	var shape = shapes[index % shapes.size()]
	return {
		"plan_id": trial_plan_id,
		"plan_index": index,
		"condition_cycle": 0,
		"distance_level_px": distance,
		"target_size_level_px": target_size,
		"direction_level_deg": direction,
		"repeat_index": 1,
		"target_shape": shape,
		"condition_id": _make_condition_id(distance, target_size, direction, 1, shape)
	}

func _make_condition_id(distance: float, target_size: float, direction: float, repeat_index: int, shape: String) -> String:
	return "d%s_w%s_a%s_r%s_%s" % [str(int(distance)), str(int(target_size)), str(int(direction)), str(repeat_index), shape]

func _shuffle_conditions(seed_value: int):
	if trial_conditions.size() <= 1:
		return

	var rng = RandomNumberGenerator.new()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	for i in range(trial_conditions.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = trial_conditions[i]
		trial_conditions[i] = trial_conditions[j]
		trial_conditions[j] = tmp
