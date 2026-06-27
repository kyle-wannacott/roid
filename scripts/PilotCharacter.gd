extends Node3D
class_name PilotCharacter

## 3D pilot/cowboy with Skeleton3D + CCDIK3D arm IK.
## All geometry and IK nodes live in the .tscn file.
##
## At rest the pilot looks exactly as authored in the scene file.
## The skeleton bones are set up for future IK hookup.
## Animation (spine lean, head turn, steering wheel) is applied
## directly to the node transforms.

## Ship state (set from HUD each frame)
var ship_thrust: float = 0.0
var ship_roll: float = 0.0
var ship_yaw: float = 0.0

## Bone names
const BONE_SPINE := "spine"
const BONE_HEAD := "head"
const BONE_UPPER_ARM_L := "upper_arm_L"
const BONE_FOREARM_L := "forearm_L"
const BONE_HAND_L := "hand_L"
const BONE_UPPER_ARM_R := "upper_arm_R"
const BONE_FOREARM_R := "forearm_R"
const BONE_HAND_R := "hand_R"

@onready var skeleton: Skeleton3D = $Skeleton
@onready var torso: Node3D = $Torso
@onready var head_node: Node3D = $Torso/Head
@onready var steering_wheel: Node3D = $SteeringWheel

@onready var shoulder_l_node: Node3D = $Torso/ShoulderL
@onready var upper_arm_l: Node3D = $Torso/ShoulderL/UpperArmL
@onready var forearm_l: Node3D = $Torso/ShoulderL/UpperArmL/ForearmL
@onready var hand_l_node: Node3D = $Torso/ShoulderL/UpperArmL/ForearmL/HandL
@onready var shoulder_r_node: Node3D = $Torso/ShoulderR
@onready var upper_arm_r: Node3D = $Torso/ShoulderR/UpperArmR
@onready var forearm_r: Node3D = $Torso/ShoulderR/UpperArmR/ForearmR
@onready var hand_r_node: Node3D = $Torso/ShoulderR/UpperArmR/ForearmR/HandR

# Rest transforms — stored so we can animate on top of the authored pose
var _torso_rest: Transform3D
var _head_rest: Transform3D
var _steering_rest: Transform3D

var _spine_idx: int = -1
var _head_idx: int = -1
var _upper_arm_l_idx: int = -1
var _forearm_l_idx: int = -1
var _hand_l_idx: int = -1
var _upper_arm_r_idx: int = -1
var _forearm_r_idx: int = -1
var _hand_r_idx: int = -1


func _ready() -> void:
	# Store the authored rest transforms so animation builds on top of them
	_torso_rest = torso.transform
	_head_rest = head_node.transform
	_steering_rest = steering_wheel.transform
	
	# Build the skeleton bones for future IK use
	_build_skeleton_bones()


func _build_skeleton_bones() -> void:
	if skeleton == null:
		return
	
	while skeleton.get_bone_count() > 0:
		skeleton.remove_bone(0)
	
	# Read rest transforms from the scene nodes so they always match
	var torso_xform: Transform3D = _torso_rest
	var head_xform: Transform3D = _head_rest
	var shoulder_l_xform: Transform3D = shoulder_l_node.transform
	var shoulder_r_xform: Transform3D = shoulder_r_node.transform
	var forearm_l_xform: Transform3D = forearm_l.transform
	var forearm_r_xform: Transform3D = forearm_r.transform
	var hand_l_xform: Transform3D = hand_l_node.transform
	var hand_r_xform: Transform3D = hand_r_node.transform
	
	# Spine (root bone at torso center, matching Torso node position)
	_spine_idx = skeleton.add_bone(BONE_SPINE)
	skeleton.set_bone_rest(_spine_idx, torso_xform)
	
	# Head (child of spine, matching Head node transform relative to Torso)
	_head_idx = skeleton.add_bone(BONE_HEAD)
	skeleton.set_bone_parent(_head_idx, _spine_idx)
	skeleton.set_bone_rest(_head_idx, head_xform)
	
	# Left arm (children of spine, at shoulder position and rotation)
	_upper_arm_l_idx = skeleton.add_bone(BONE_UPPER_ARM_L)
	skeleton.set_bone_parent(_upper_arm_l_idx, _spine_idx)
	skeleton.set_bone_rest(_upper_arm_l_idx, shoulder_l_xform)
	
	_forearm_l_idx = skeleton.add_bone(BONE_FOREARM_L)
	skeleton.set_bone_parent(_forearm_l_idx, _upper_arm_l_idx)
	skeleton.set_bone_rest(_forearm_l_idx, forearm_l_xform)
	
	_hand_l_idx = skeleton.add_bone(BONE_HAND_L)
	skeleton.set_bone_parent(_hand_l_idx, _forearm_l_idx)
	skeleton.set_bone_rest(_hand_l_idx, hand_l_xform)
	
	# Right arm (mirror)
	_upper_arm_r_idx = skeleton.add_bone(BONE_UPPER_ARM_R)
	skeleton.set_bone_parent(_upper_arm_r_idx, _spine_idx)
	skeleton.set_bone_rest(_upper_arm_r_idx, shoulder_r_xform)
	
	_forearm_r_idx = skeleton.add_bone(BONE_FOREARM_R)
	skeleton.set_bone_parent(_forearm_r_idx, _upper_arm_r_idx)
	skeleton.set_bone_rest(_forearm_r_idx, forearm_r_xform)
	
	_hand_r_idx = skeleton.add_bone(BONE_HAND_R)
	skeleton.set_bone_parent(_hand_r_idx, _forearm_r_idx)
	skeleton.set_bone_rest(_hand_r_idx, hand_r_xform)
	
	# Reset all poses
	for i in skeleton.get_bone_count():
		skeleton.reset_bone_pose(i)


func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	
	# ── Spine lean from roll and thrust ──
	#   Applied as a rotation on top of the rest transform.
	var roll_lean: float = ship_roll * 0.15
	var thrust_lean: float = -ship_thrust * 0.08
	
	var spine_offset: Transform3D = Transform3D.IDENTITY
	spine_offset = spine_offset.rotated(Vector3.FORWARD, roll_lean)
	spine_offset = spine_offset.rotated(Vector3.RIGHT, thrust_lean)
	spine_offset.origin = Vector3(roll_lean * 0.05, 0, thrust_lean * 0.05)
	
	torso.transform = _torso_rest * spine_offset
	
	# ── Head turn ──
	#   Applied on top of the rest transform (which is relative to the Torso
	#   that already has lean applied — so the head leans with the body
	#   and then additionally turns).
	var head_offset: Transform3D = Transform3D.IDENTITY
	head_offset = head_offset.rotated(Vector3.UP, ship_yaw * 0.2)
	head_offset = head_offset.rotated(Vector3.FORWARD, -ship_roll * 0.1)
	
	head_node.transform = _head_rest * head_offset
	
	# ── Steering wheel counter-roll ──
	steering_wheel.transform = _steering_rest
	steering_wheel.rotate_object_local(Vector3.FORWARD, -ship_roll * 0.3)
	
	# ── Also drive the skeleton bone poses so it stays in sync ──
	#   This ensures the skeleton mirrors the mesh animation. The IK nodes
	#   (LeftArmIK / RightArmIK) can then work on the skeleton while the
	#   mesh follows via the direct animation above.
	if skeleton != null:
		if _spine_idx >= 0:
			skeleton.set_bone_pose(_spine_idx, spine_offset)
		if _head_idx >= 0:
			skeleton.set_bone_pose(_head_idx, head_offset)
