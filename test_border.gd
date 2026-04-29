extends SceneTree

func _init():
    var target_rect = Rect2(Vector2(100, 100), Vector2(48, 48))
    var padded_rect = target_rect.grow(3.0)
    print("target_rect: ", target_rect)
    print("padded_rect: ", padded_rect)
    print("padded_rect.has_point(100,100): ", padded_rect.has_point(Vector2(100,100)))
    print("padded_rect.has_point(147.9,147.9): ", padded_rect.has_point(Vector2(147.9,147.9)))
    print("padded_rect.has_point(150,150): ", padded_rect.has_point(Vector2(150,150)))
    quit()
