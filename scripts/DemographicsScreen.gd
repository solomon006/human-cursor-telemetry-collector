extends Control

@onready var age_option = $VBoxContainer/AgeOption
@onready var hand_option = $VBoxContainer/HandOption
@onready var device_option = $VBoxContainer/DeviceOption
@onready var mouse_hand_option = $VBoxContainer/MouseHandOption
@onready var dpi_option = $VBoxContainer/DpiOption
@onready var continue_button = $VBoxContainer/ContinueButton

func _ready():
	# Наполняем списки
	age_option.add_item("< 18")
	age_option.add_item("18-24")
	age_option.add_item("25-34")
	age_option.add_item("35-44")
	age_option.add_item("45+")
	
	hand_option.add_item("Правша")
	hand_option.add_item("Левша")
	
	device_option.add_item("Обычная мышь (офисная)")
	device_option.add_item("Игровая мышь")
	device_option.add_item("Тачпад")
	
	mouse_hand_option.add_item("Правой рукой")
	mouse_hand_option.add_item("Левой рукой")
	
	dpi_option.add_item("400")
	dpi_option.add_item("800 (Стандарт)")
	dpi_option.add_item("1200")
	dpi_option.add_item("1600")
	dpi_option.add_item("3200")
	dpi_option.add_item("Не знаю (оставить 800)")
	dpi_option.select(1) # По умолчанию 800
	
	continue_button.pressed.connect(_on_continue_pressed)

func _on_continue_pressed():
	# Сохраняем ответы в глобальный конфиг
	ParticipantConfig.age_group = age_option.get_item_text(age_option.selected)
	ParticipantConfig.handedness = "right" if hand_option.selected == 0 else "left"
	
	match device_option.selected:
		0: ParticipantConfig.device_type = "office_mouse"
		1: ParticipantConfig.device_type = "gaming_mouse"
		2: ParticipantConfig.device_type = "touchpad"
		
	ParticipantConfig.usual_mouse_hand = "right" if mouse_hand_option.selected == 0 else "left"
	
	var dpi_val = 800
	match dpi_option.selected:
		0: dpi_val = 400
		1: dpi_val = 800
		2: dpi_val = 1200
		3: dpi_val = 1600
		4: dpi_val = 3200
		5: dpi_val = 800
	ParticipantConfig.mouse_dpi = dpi_val
	
	# Генерируем ID участника
	ParticipantConfig.generate_ids()
	ParticipantConfig.save_state()
	
	# Переводим игру в полноэкранный режим для сбора данных
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	
	# Переходим к инструкции
	SceneManager.goto_scene("instruction")
