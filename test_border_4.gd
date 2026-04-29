extends SceneTree

func _init():
    var rect = Rect2(Vector2(0, 0), Vector2(100, 100))
    print(rect)
    print("Has point 100,100: ", rect.has_point(Vector2(100,100)))
    quit()
