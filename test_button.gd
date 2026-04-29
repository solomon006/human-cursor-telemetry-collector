extends SceneTree

func _init():
    var rect = Rect2(Vector2(100, 100), Vector2(48, 48))
    print(rect.has_point(Vector2(100, 100))) # true
    print(rect.has_point(Vector2(148, 148))) # false! Rect2.has_point is exclusive on the bottom/right edges
    quit()
