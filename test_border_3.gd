extends SceneTree

func _init():
    var rect = Rect2(Vector2(0, 0), Vector2(100, 100))
    var pt = Vector2(99, 99)
    print("Has point 99,99: ", rect.has_point(pt))
    print("Has point 100,100: ", rect.has_point(Vector2(100,100)))
    quit()
