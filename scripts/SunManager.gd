extends Node
class_name SunManager
## Finds every DirectionalLight3D in the scene and spawns a giant
## glowing sun sphere along each light's forward direction (very far
## away so the sun sits in the "sky").  Uses a procedural sun shader
## (noise‑driven plasma + corona + flares).

const SUN_SHADER: Shader = preload("res://shaders/sun_instance.gdshader")
const SUN_MESH_RADIUS: float = 60.0
const SUN_DISTANCE: float = 2000.0


func _ready() -> void:
	# Defer to the next process frame so the scene tree is fully
	# set up (we need the lights' global_transform).
	await get_tree().process_frame
	_spawn_all()


func _spawn_all() -> void:
	# Look for DirectionalLight3D nodes in the Main scene.
	var main_node: Node = get_parent()
	if main_node == null:
		return
	var lights: Array = []
	_collect_lights(main_node, lights)
	for light in lights:
		_spawn_sun(light)


func _collect_lights(node: Node, out: Array) -> void:
	if node is DirectionalLight3D and node.is_inside_tree():
		out.append(node)
	for child in node.get_children():
		_collect_lights(child, out)


func _spawn_sun(light: DirectionalLight3D) -> void:
	# DirectionalLight shines in its local -Z.  Place the sun far
	# away in that direction so it lines up with the light's
	# apparent position in the sky.
	var forward: Vector3 = -light.global_transform.basis.z
	var sun_pos: Vector3 = light.global_position + forward * SUN_DISTANCE

	# Build the sun mesh once (shared by all suns).
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = SUN_MESH_RADIUS
	sphere.height = SUN_MESH_RADIUS * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = sphere
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Add to the tree first, then set global_position.
	get_parent().add_child(mi)
	mi.global_position = sun_pos

	# Sun material: emissive shader, no lighting.
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SUN_SHADER
	# Slight per‑sun phase offset so multiple suns don't pulse in sync.
	mat.set_shader_parameter("time_offset", randf() * 100.0)
	mi.material_override = mat
