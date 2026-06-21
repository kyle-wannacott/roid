extends Node
class_name SunManager
## Finds every DirectionalLight3D in the "sun" group and spawns a
## giant glowing sun sphere at the light's position.  Uses a
## procedural sun shader (noise‑driven plasma + corona + flares).

const SUN_SHADER: Shader = preload("res://shaders/sun_instance.gdshader")
const SUN_MESH_RADIUS: float = 150.0
const SUN_GROUP: StringName = &"sun"


func _ready() -> void:
	# Defer to the next process frame so the scene tree is fully
	# set up (we need the lights' global_transform).
	await get_tree().process_frame
	_spawn_all()


func _spawn_all() -> void:
	# Look for DirectionalLight3D nodes in the "sun" group.
	var lights: Array[Node] = get_tree().get_nodes_in_group(SUN_GROUP)
	for node in lights:
		if node is DirectionalLight3D and node.is_inside_tree():
			_spawn_sun(node as DirectionalLight3D)


func _spawn_sun(light: DirectionalLight3D) -> void:
	# Place the sun sphere at the light's position.  The light's
	# transform defines both where the sun is and which direction it
	# shines (the shader is view‑independent, so the direction
	# affects lighting only, not the sun's appearance).
	var sun_pos: Vector3 = light.global_position

	# Build the sun mesh once (shared by all suns).
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = SUN_MESH_RADIUS
	sphere.height = SUN_MESH_RADIUS * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = sphere
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_to_group(SUN_GROUP)
	# Add to the tree first, then set global_position.
	get_parent().add_child(mi)
	mi.global_position = sun_pos

	# Sun material: emissive shader, no lighting.
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SUN_SHADER
	# Slight per‑sun phase offset so multiple suns don't pulse in sync.
	mat.set_shader_parameter("time_offset", randf() * 100.0)
	# Tint the sun's core/edge based on the light's colour so the
	# two suns are visually distinct.
	mat.set_shader_parameter("core_color", Color(light.light_color.r * 1.1, light.light_color.g * 1.0, light.light_color.b * 0.7, 1.0))
	mat.set_shader_parameter("hot_color", Color(light.light_color.r, light.light_color.g * 0.7, light.light_color.b * 0.3, 1.0))
	mat.set_shader_parameter("corona_color", Color(light.light_color.r * 0.9, light.light_color.g * 0.5, light.light_color.b * 0.2, 1.0))
	mi.material_override = mat
