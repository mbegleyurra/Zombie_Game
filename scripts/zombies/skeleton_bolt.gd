class_name SkeletonBolt
extends Node3D
## Slow magic bolt fired by a skeleton mage. Every peer simulates the flight (visual);
## only the server (damaging = true) applies damage, via Player.request_damage.
## Stops on world geometry (collision layer 1). Add it to the scene root, not to a
## MultiplayerSpawner container.

const HIT_RADIUS := 0.7
const MASK_WORLD := 1

var velocity: Vector3 = Vector3.ZERO
var damage: float = 14.0
var damaging: bool = true
var life: float = 5.0
var hit_player: Node = null


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 1.0, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 1.0, 0.4)
	mat.emission_energy_multiplier = 2.5
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	mesh.radial_segments = 10
	mesh.rings = 5
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 1.0, 0.4)
	light.light_energy = 1.2
	light.omni_range = 4.0
	add_child(light)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, MASK_WORLD)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		queue_free()
		return
	global_position = to
	if not damaging:
		return
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p == null or p.is_dead:
			continue
		if (p.global_position + Vector3.UP * 1.0).distance_to(to) < HIT_RADIUS:
			hit_player = p
			p.request_damage(damage, false, 0)
			queue_free()
			return
