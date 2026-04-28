extends Control

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	$VBoxContainer/ContinueButton.pressed.connect(func():
		SceneManager.goto_scene("form")
	)
