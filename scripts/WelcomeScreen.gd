extends Control

@onready var consent_checkbox = $VBoxContainer/HBoxContainer/ConsentCheckBox
@onready var start_button = $VBoxContainer/StartButton
@onready var reset_button = $VBoxContainer/ResetButton

func _ready():
	start_button.disabled = true
	consent_checkbox.toggled.connect(_on_consent_toggled)
	start_button.pressed.connect(_on_start_pressed)
	reset_button.pressed.connect(func():
		ParticipantConfig.clear_state()
		consent_checkbox.button_pressed = false
		start_button.disabled = true
	)

func _on_consent_toggled(toggled_on: bool):
	start_button.disabled = not toggled_on

func _on_start_pressed():
	if ParticipantConfig.load_state() and ParticipantConfig.total_completed_trials > 0:
		# User is returning, skip demographics and instruction
		ParticipantConfig.is_consent_given = true
		ParticipantConfig.generate_session_id()
		ParticipantConfig.save_state()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		SceneManager.goto_scene("task")
	else:
		ParticipantConfig.is_consent_given = true
		SceneManager.goto_scene("demographics")
