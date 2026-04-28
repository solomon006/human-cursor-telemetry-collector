extends Control

func _ready():
	$VBoxContainer/Button.pressed.connect(func():
		SceneManager.goto_scene("task")
	)
