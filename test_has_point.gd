extends SceneTree

func _init():
    var rect = Rect2(Vector2(0, 0), Vector2(100, 100))
    print(rect.has_point(Vector2(100, 100))) # Exclusivity issue?
    quit()
