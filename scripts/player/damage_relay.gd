class_name DamageRelay
extends Node
## Reliable player-damage delivery. Child of every Player, named "DamageRelay", so
## its path matches on every peer. It carries NO MultiplayerSynchronizer, so Godot's
## "peer cannot see this node" RPC check never blocks it (that check applies to the
## Player node itself, whose PlayerSync is hidden from a peer until it confirms the spawn).
##
## Sender: send(target_peer, amount) queues a hit and retries every RETRY seconds until
## the owner acknowledges it (a late joiner may not have its own Player node yet, or the
## target may not be connected yet). Receiver: applies each (sender, seq) exactly once to
## the owning Player and acks. Pure server-to-owner traffic in practice (zombies run on
## the server); health itself stays owned and replicated by the Player's own PlayerSync.

const RETRY := 0.4
const MAX_TRIES := 40   ## about 16 s, then the hit is dropped (target gone or never ready)

signal delivered(seq: int)

var _next_seq: int = 1
var _out: Dictionary = {}    # seq -> {target, amount, wait, tries}
var _seen: Dictionary = {}   # "sender:seq" -> true
var applied_total: float = 0.0   ## damage this node applied locally (diagnostics/tests)
var dropped: int = 0


func send(target: int, amount: float) -> void:
	if amount <= 0.0:
		return
	var seq := _next_seq
	_next_seq += 1
	_out[seq] = {"target": target, "amount": amount, "wait": 0.0, "tries": 0}
	_attempt(seq)


func pending_count() -> int:
	return _out.size()


func _can_reach(target: int) -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.get_peers().has(target)


func _attempt(seq: int) -> void:
	var e: Dictionary = _out[seq]
	e["wait"] = RETRY
	e["tries"] = int(e["tries"]) + 1
	if _can_reach(int(e["target"])):
		rpc_id(int(e["target"]), "_rx_damage", seq, float(e["amount"]))


func _process(delta: float) -> void:
	if _out.is_empty():
		return
	for seq in _out.keys():
		var e: Dictionary = _out[seq]
		e["wait"] = float(e["wait"]) - delta
		if float(e["wait"]) > 0.0:
			continue
		if int(e["tries"]) >= MAX_TRIES:
			_out.erase(seq)
			dropped += 1
			continue
		_attempt(seq)


@rpc("any_peer", "call_remote", "reliable")
func _rx_damage(seq: int, amount: float) -> void:
	var parent := get_parent() as Player
	if parent == null or not parent.is_multiplayer_authority():
		return   # not the owner: no ack, the sender keeps retrying towards the real owner
	var sender := multiplayer.get_remote_sender_id()
	rpc_id(sender, "_rx_ack", seq)
	var key := "%d:%d" % [sender, seq]
	if _seen.has(key):
		return
	_seen[key] = true
	var before := parent.health
	parent._hurt(amount, true)
	applied_total += maxf(0.0, before - parent.health)


@rpc("any_peer", "call_remote", "reliable")
func _rx_ack(seq: int) -> void:
	if _out.erase(seq):
		delivered.emit(seq)
