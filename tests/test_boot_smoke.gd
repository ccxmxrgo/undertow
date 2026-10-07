extends GdUnitTestSuite


func test_skeleton_boots_and_runs_30_frames() -> void:
	var runner := scene_runner("res://scenes/skeleton.tscn")
	await runner.simulate_frames(30)
	var scene: Node = runner.scene()
	assert_object(scene).is_not_null()
	assert_object(scene.get_node_or_null("Conductor")).is_not_null()
	assert_object(scene.get_node_or_null("Highway")).is_not_null()
	# clock advanced from the negative lead-in without going backwards
	var conductor: Conductor = scene.get_node("Conductor")
	assert_float(conductor.song_time()).is_greater(-1.0)
