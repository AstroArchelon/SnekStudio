extends Mod_Base

var target_ip : String = "127.0.0.1"
var target_port : int = 39539
var vmc_sender_enabled : bool = false

# List from the VRM spec:
# https://github.com/vrm-c/vrm-specification/blob/master/specification/0.0/schema/vrm.humanoid.bone.schema.json
const _humanoid_bone_list : PackedStringArray = [
	"hips",
	"leftUpperLeg", "rightUpperLeg",
	"leftLowerLeg", "rightLowerLeg",
	"leftFoot", "rightFoot",
	"spine", "chest", "neck", "head",
	"leftShoulder", "rightShoulder",
	"leftUpperArm", "rightUpperArm",
	"leftLowerArm", "rightLowerArm",
	"leftHand", "rightHand",
	"leftToes", "rightToes",
	"leftEye", "rightEye",
	"jaw",
	"leftThumbProximal", "leftThumbIntermediate", "leftThumbDistal",
	"leftIndexProximal", "leftIndexIntermediate", "leftIndexDistal",
	"leftMiddleProximal", "leftMiddleIntermediate", "leftMiddleDistal",
	"leftRingProximal", "leftRingIntermediate", "leftRingDistal",
	"leftLittleProximal", "leftLittleIntermediate", "leftLittleDistal",
	"rightThumbProximal", "rightThumbIntermediate", "rightThumbDistal",
	"rightIndexProximal", "rightIndexIntermediate", "rightIndexDistal",
	"rightMiddleProximal", "rightMiddleIntermediate","rightMiddleDistal",
	"rightRingProximal", "rightRingIntermediate", "rightRingDistal",
	"rightLittleProximal", "rightLittleIntermediate", "rightLittleDistal",
	"upperChest"]

const _vrm_1_to_0_blend_shape_map : Dictionary = {
	"neutral" : "Neutral",
	"aa" : "A",
	"ih" : "I",
	"ou" : "U",
	"ee" : "E",
	"oh" : "O",
	"blink" : "Blink",
	"happy" : "Joy",
	"angry" : "Angry",
	"sad" : "Sorrow",
	"relaxed" : "Fun",
	"lookUp" : "LookUp",
	"lookDown" : "LookDown",
	"lookLeft" : "LookLeft",
	"lookRight" : "LookRight",
	"blinkLeft" : "Blink_L",
	"blinkRight" : "Blink_R" }

# These are the names to match, along with their first-letter-uppercased
# versions.
var _humanoid_bone_dict_lowercase_to_upper_first_letter : Dictionary = {}

func _ready() -> void:
	add_tracked_setting("target_ip", "Reciever IP address")
	add_tracked_setting("target_port", "Reciever port")
	add_tracked_setting("vmc_sender_enabled", "Sender enabled")

	for bone_name in _humanoid_bone_list:
		var bone_name_upper_first_letter : String = bone_name[0].to_upper() + bone_name.substr(1)
		_humanoid_bone_dict_lowercase_to_upper_first_letter[bone_name.to_lower()] = \
			bone_name_upper_first_letter

	update_settings_ui()

func load_after(_settings_old : Dictionary, _settings_new : Dictionary) -> void:
	$KiriOSClient.change_port_and_ip(target_port, target_ip)
	if _settings_old["vmc_sender_enabled"] != _settings_new["vmc_sender_enabled"]:
		if vmc_sender_enabled:
			$KiriOSClient.start_client()
		else:
			$KiriOSClient.stop_client()

func _physics_process(delta: float) -> void:
	var skel : Skeleton3D = get_skeleton()

	#for bone_index in range(0, skel.get_bone_count()):
	for bone_name in _humanoid_bone_list:
		var bone_name_lower : String = bone_name.to_lower()
		var bone_name_upper_first_letter : String = _humanoid_bone_dict_lowercase_to_upper_first_letter[bone_name_lower]
		var actual_bone_name : String = bone_name_upper_first_letter

		# We may have to rename some thumb bone names, depending on whether we
		# have a VRM 1.0 or 0.0 model.
		if actual_bone_name.begins_with("LeftThumb") or actual_bone_name.begins_with("RightThumb"):
			if skel.find_bone("LeftThumbMetacarpal") != -1:
				# We have the metacarpal bone, so assume VRM 1.0.
				var bone_without_side : String = ""
				var bone_side : String = ""
				if actual_bone_name.begins_with("Left"):
					bone_without_side = actual_bone_name.substr(4)
					bone_side = "Left"
				else:
					bone_without_side = actual_bone_name.substr(5)
					bone_side = "Right"

				var converted_bone_without_side : String = bone_without_side
				if bone_without_side == "ThumbProximal":
					converted_bone_without_side = "ThumbMetacarpal"
				if bone_without_side == "ThumbIntermediate":
					converted_bone_without_side = "ThumbProximal"

				actual_bone_name = bone_side + converted_bone_without_side

		var bone_index : int = skel.find_bone(actual_bone_name)
		if bone_index != -1:

			var global_rest : Transform3D = skel.get_bone_global_rest(bone_index)
			var rest : Transform3D = skel.get_bone_rest(bone_index)
			var pose : Transform3D = skel.get_bone_pose(bone_index)

			var transformed_pose : Transform3D = global_rest * rest.inverse() * pose * global_rest.inverse()
			var rotation_quat : Quaternion = transformed_pose.basis.get_rotation_quaternion()
			var origin : Vector3 = pose.origin

			# Shuffle stuff around into the coordinate space that VMC expects.
			rotation_quat.y *= -1
			rotation_quat.z *= -1
			origin.x *= -1

			$KiriOSClient.send_osc_message("/VMC/Ext/Bone/Pos", "sfffffff", [
				bone_name_upper_first_letter,
				origin.x, origin.y, origin.z,
				rotation_quat.x, rotation_quat.y, rotation_quat.z, rotation_quat.w])

	var blend_shapes_to_apply : Dictionary = get_global_mod_data("BlendShapes")
	for shape_name in blend_shapes_to_apply:
		var shape_name_mapped : String = shape_name
		if shape_name_mapped in _vrm_1_to_0_blend_shape_map:
			shape_name_mapped = _vrm_1_to_0_blend_shape_map[shape_name]

		$KiriOSClient.send_osc_message("/VMC/Ext/Blend/Val", "sf", [
			shape_name_mapped,
			blend_shapes_to_apply[shape_name]])

	$KiriOSClient.send_osc_message("/VMC/Ext/Blend/Apply", "", [])
