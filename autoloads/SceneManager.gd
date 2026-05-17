extends Node

# В словаре будут лежать пути к сценам.
# Если сцены еще нет, мы просто заложим пустые строки, 
# а потом обновим, когда создадим их.
var scenes = {
	"welcome": "res://scenes/WelcomeScreen.tscn",
	"demographics": "res://scenes/DemographicsScreen.tscn",
	"instruction": "res://scenes/InstructionScreen.tscn",
	"task": "res://scenes/TaskScreen.tscn",
	"break": "res://scenes/BreakScreen.tscn",
	"thank_you": "res://scenes/ThankYouScreen.tscn"
}

var current_scene = null

func _ready():
	var root = get_tree().root
	current_scene = root.get_child(root.get_child_count() - 1)

func goto_scene(scene_name: String):
	if not scenes.has(scene_name):
		push_error("Сцена не найдена в SceneManager: ", scene_name)
		return
		
	call_deferred("_deferred_goto_scene", scenes[scene_name])

func _deferred_goto_scene(path: String):
	if not ResourceLoader.exists(path):
		push_error("Файл сцены не существует: ", path)
		return
		
	current_scene.free()
	var s = ResourceLoader.load(path)
	current_scene = s.instantiate()
	get_tree().root.add_child(current_scene)
	get_tree().current_scene = current_scene
