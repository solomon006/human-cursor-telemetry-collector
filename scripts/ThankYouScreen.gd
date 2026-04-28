extends Control

func _ready():
	# При загрузке экрана сразу экспортируем на рабочий стол
	if DataLogger.raw_session_path != "":
		DataLogger.export_to_desktop()
	
	$VBoxContainer/TelegramButton.pressed.connect(func():
		var tg_user = AppConfig.telegram_username
		if tg_user != "":
			OS.shell_open("https://t.me/" + tg_user)
		else:
			OS.shell_open("https://web.telegram.org/")
	)
	
	$VBoxContainer/QuitButton.pressed.connect(func():
		get_tree().quit()
	)
