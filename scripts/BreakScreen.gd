extends Control

func _ready():
	# Показываем прогресс
	var done = ParticipantConfig.total_completed_trials
	var total = AppConfig.total_trials
	var label = $VBoxContainer/Label
	label.text = "Отличная работа! Блок завершен.\nВыполнено: %d / %d заданий.\nМожно размять руку.\n\nЕсли вы устали, вы можете закрыть игру сейчас \nи продолжить в другой день (прогресс сохранён)." % [done, total]

	$VBoxContainer/HBoxContainer/QuitButton.pressed.connect(func():
		DataLogger.end_session()
		get_tree().quit()
	)
	
	$VBoxContainer/HBoxContainer/ContinueButton.pressed.connect(func():
		SceneManager.goto_scene("task")
	)
