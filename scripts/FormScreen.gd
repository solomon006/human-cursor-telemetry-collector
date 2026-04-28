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

func _ready():
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
	# Data logging and transition
	DataLogger.log_event("form_completed", {
		"session_id": ParticipantConfig.session_id,
		"participant_id": ParticipantConfig.participant_id,
		"t_us": Time.get_ticks_usec()
	})
	SceneManager.goto_scene("thank_you")
