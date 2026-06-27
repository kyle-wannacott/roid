extends Node3D
func _ready() -> void:
	print("CCDIK3D available: ", ClassDB.class_exists("CCDIK3D"))
	print("FABRIKIK3D available: ", ClassDB.class_exists("FABRIKIK3D"))
	print("SkeletonIK3D available: ", ClassDB.class_exists("SkeletonIK3D"))
	get_tree().quit()
