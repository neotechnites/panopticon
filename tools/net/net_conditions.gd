class_name NetConditions
extends RefCounted

## One direction of a test link, modelled as netem models one: loss (Gilbert-Elliott), duplication,
## delay with jitter, hold-back reordering. No transport: items go in with a time, come out when due.
##
## Everything runs on time, not packet counts, so a 60 Hz and a 2 Hz stream on one path see the same
## link. Reliable items are only delayed: below this sits the transport's own retransmission and order.

enum Jitter { UNIFORM, NORMAL }

## One-way base delay, milliseconds.
var delay_ms: float = 0.0
## The spread around [member delay_ms]: UNIFORM its half-width, NORMAL its standard deviation.
var jitter_ms: float = 0.0
var jitter: Jitter = Jitter.UNIFORM
## How long the jitter remembers itself (an Ornstein-Uhlenbeck process, the shape of a queue that
## fills and drains); 0 draws it afresh per packet, as netem, Gaffer's and Unity's simulators do.
var jitter_tau_ms: float = 0.0
## False keeps a path in order (one UDP flow through one queue); true lets jitter reorder it.
var jitter_reorders: bool = false
## Chance an unreliable copy is lost while the link is good (with no bursts, plain Bernoulli loss).
var loss: float = 0.0
## Mean length of a bad spell and of the good spell between two, milliseconds; 0 turns bursts off.
var burst_ms: float = 0.0
var burst_gap_ms: float = 0.0
## Chance an unreliable copy is lost during a bad spell.
var burst_loss: float = 1.0
## Chance an unreliable packet goes twice; the copy has its own loss.
var duplicate: float = 0.0
## Chance an unreliable copy is held back, and how long it then trails behind its due time.
var reorder: float = 0.0
var reorder_ms: float = 0.0

## Every per-packet decision has its own stream, so adding one condition moves no other one's draws.
var _rng_loss: RandomNumberGenerator = RandomNumberGenerator.new()
var _rng_link: RandomNumberGenerator = RandomNumberGenerator.new()
var _rng_delay: RandomNumberGenerator = RandomNumberGenerator.new()
var _rng_copy: RandomNumberGenerator = RandomNumberGenerator.new()
var _rng_order: RandomNumberGenerator = RandomNumberGenerator.new()
var _links: Dictionary[int, Link] = {}
## Pending items, sorted by due time then by push order: [due_ms, order, path, item].
var _queue: Array = []
var _order: int = 0
var _stats: Dictionary[int, Dictionary] = {}


## The state of one path: its burst state, its jitter state and the last in-order due times.
class Link extends RefCounted:
	var bad: bool = false
	var bad_at: float = 0.0
	var jitter_z: float = 0.0
	var jitter_at: float = -INF
	var last_due: float = -INF
	var last_reliable_due: float = -INF


func _init(rng_seed: int = 1) -> void:
	reseed(rng_seed)


## Restart every stream from [param rng_seed]. Loss draws from the seed itself, as the first
## conditioner did, so a loss-only line replays the same drops.
func reseed(rng_seed: int) -> void:
	_rng_loss.seed = rng_seed
	var others: Array[RandomNumberGenerator] = [_rng_link, _rng_delay, _rng_copy, _rng_order]
	for i: int in others.size():
		others[i].seed = hash([rng_seed, i + 1])


## Options as the net runners take them: loss, delay-ms, jitter-ms, jitter-dist, jitter-tau-ms,
## jitter-reorders, burst-ms, burst-gap-ms, burst-loss, dup, reorder, reorder-ms.
static func from_options(options: Dictionary, rng_seed: int = 1) -> NetConditions:
	var c: NetConditions = NetConditions.new(rng_seed)
	c.loss = float(options.get("loss", 0.0))
	c.delay_ms = float(options.get("delay-ms", 0.0))
	c.jitter_ms = float(options.get("jitter-ms", 0.0))
	c.jitter = Jitter.NORMAL if String(options.get("jitter-dist", "uniform")) == "normal" else Jitter.UNIFORM
	c.jitter_tau_ms = float(options.get("jitter-tau-ms", 0.0))
	c.jitter_reorders = str(options.get("jitter-reorders", false)).to_lower() in ["true", "1", "yes", "on"]
	c.burst_ms = float(options.get("burst-ms", 0.0))
	c.burst_gap_ms = float(options.get("burst-gap-ms", 0.0))
	c.burst_loss = float(options.get("burst-loss", 1.0))
	c.duplicate = float(options.get("dup", 0.0))
	c.reorder = float(options.get("reorder", 0.0))
	c.reorder_ms = float(options.get("reorder-ms", 0.0))
	return c


## Whether anything at all is done to the line.
func is_conditioned() -> bool:
	return loss > 0.0 or delay_ms > 0.0 or jitter_ms > 0.0 or has_bursts() or duplicate > 0.0 \
		or (reorder > 0.0 and reorder_ms > 0.0)


func has_bursts() -> bool:
	return burst_ms > 0.0 and burst_gap_ms > 0.0


## The settings, one line, keys as [method from_options] reads them.
func describe() -> String:
	return "loss=%.3f delay-ms=%.1f jitter-ms=%.1f jitter-dist=%s jitter-tau-ms=%.1f jitter-reorders=%s burst-ms=%.1f burst-gap-ms=%.1f burst-loss=%.3f dup=%.3f reorder=%.3f reorder-ms=%.1f" % [
		loss, delay_ms, jitter_ms, "normal" if jitter == Jitter.NORMAL else "uniform", jitter_tau_ms,
		str(jitter_reorders), burst_ms, burst_gap_ms, burst_loss, duplicate, reorder, reorder_ms]


## Offer [param item] to the link towards [param path] at [param now_ms]. Returns how many copies
## will come out of [method pop_due]: 0 lost, 2 duplicated.
func push(path: int, reliable: bool, item: Variant, now_ms: float) -> int:
	var link: Link = _link(path, now_ms)
	var copies: int = 1
	if not reliable and duplicate > 0.0 and _rng_copy.randf() < duplicate:
		copies = 2
		_count(path, "duplicated")
	_count(path, "reliable" if reliable else "offered")
	var kept: int = 0
	for _copy: int in copies:
		if not reliable and _lost(link, now_ms):
			_count(path, "lost")
			continue
		_enqueue(link, path, reliable, item, now_ms)
		kept += 1
	return kept


## Items due by [param now_ms], earliest first, removed from the link.
func pop_due(now_ms: float) -> Array:
	var taken: int = 0
	while taken < _queue.size() and float(_queue[taken][0]) <= now_ms:
		taken += 1
	var due: Array = []
	for entry: Array in _queue.slice(0, taken):
		due.append(entry[3])
	_queue = _queue.slice(taken)
	return due


func pending() -> int:
	return _queue.size()


## When the next item comes due, or INF with nothing in flight.
func next_due() -> float:
	return float(_queue[0][0]) if not _queue.is_empty() else INF


## Drop everything in flight towards [param path] and its link state; its counters stay.
func forget(path: int) -> void:
	_queue = _queue.filter(func(entry: Array) -> bool: return int(entry[2]) != path)
	_links.erase(path)


## Counters for one path, or every path summed for -1: offered, reliable, lost, duplicated, held,
## delivered, delay_sum_ms, delay_sq_sum_ms, delay_max_ms.
func stats(path: int = -1) -> Dictionary:
	if path != -1:
		return _stats.get(path, {}).duplicate()
	var total: Dictionary = {}
	for one: Dictionary in _stats.values():
		for key: String in one:
			var value: float = float(one[key])
			total[key] = maxf(float(total.get(key, 0.0)), value) if key == "delay_max_ms" \
				else float(total.get(key, 0.0)) + value
	return total


func _lost(link: Link, now_ms: float) -> bool:
	var chance: float = burst_loss if _bad_at(link, now_ms) else loss
	# One loss draw per unreliable copy, always: a seed replays the same drops when the rate changes.
	return _rng_loss.randf() < chance


## The two-state link of Gilbert and Elliott in continuous time: exponential good and bad spells,
## advanced to [param now_ms] with the exact two-state transition probability.
func _bad_at(link: Link, now_ms: float) -> bool:
	if not has_bursts():
		return false
	var to_bad: float = 1.0 / burst_gap_ms
	var to_good: float = 1.0 / burst_ms
	var bad_share: float = to_bad / (to_bad + to_good)
	var decay: float = exp(-(to_bad + to_good) * maxf(now_ms - link.bad_at, 0.0))
	var p_bad: float = bad_share + (1.0 - bad_share) * decay if link.bad else bad_share * (1.0 - decay)
	link.bad = _rng_link.randf() < p_bad
	link.bad_at = now_ms
	return link.bad


## This path's jitter at [param now_ms]: a unit normal carried forward with the exact
## Ornstein-Uhlenbeck step, shaped to the distribution asked for.
func _jitter_at(link: Link, now_ms: float) -> float:
	var carried: float = exp(-(now_ms - link.jitter_at) / jitter_tau_ms) if jitter_tau_ms > 0.0 else 0.0
	link.jitter_z = carried * link.jitter_z + sqrt(1.0 - carried * carried) * _rng_delay.randfn(0.0, 1.0)
	link.jitter_at = now_ms
	if jitter == Jitter.NORMAL:
		return jitter_ms * link.jitter_z
	# Through the normal's own CDF the same process has a uniform marginal (a Gaussian copula).
	return jitter_ms * erf_approx(link.jitter_z / sqrt(2.0))


func _enqueue(link: Link, path: int, reliable: bool, item: Variant, now_ms: float) -> void:
	var wait: float = delay_ms + (_jitter_at(link, now_ms) if jitter_ms > 0.0 else 0.0)
	var due: float = now_ms + maxf(wait, 0.0)
	# In order unless jitter may reorder; reliable items always, as the transport would deliver them.
	var in_order: bool = reliable or not jitter_reorders
	if in_order:
		due = maxf(due, link.last_reliable_due if reliable and jitter_reorders else link.last_due)
	if not reliable and reorder > 0.0 and reorder_ms > 0.0 and _rng_order.randf() < reorder:
		# Held back off the in-order line: the packets behind it are not held with it.
		due += reorder_ms
		_count(path, "held")
	elif in_order:
		if reliable and jitter_reorders:
			link.last_reliable_due = due
		else:
			link.last_due = due
	_count(path, "delivered")
	var waited: float = due - now_ms
	_count(path, "delay_sum_ms", waited)
	_count(path, "delay_sq_sum_ms", waited * waited)
	_stats[path]["delay_max_ms"] = maxf(float(_stats[path].get("delay_max_ms", 0.0)), waited)
	var entry: Array = [due, _order, path, item]
	_order += 1
	_queue.insert(_queue.bsearch_custom(entry, _before), entry)


func _link(path: int, now_ms: float) -> Link:
	if not _links.has(path):
		var link: Link = Link.new()
		link.bad_at = now_ms
		_links[path] = link
	return _links[path]


func _count(path: int, key: String, amount: float = 1.0) -> void:
	if not _stats.has(path):
		_stats[path] = {}
	_stats[path][key] = float(_stats[path].get(key, 0.0)) + amount


static func _before(a: Array, b: Array) -> bool:
	return float(a[0]) < float(b[0]) or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1]))


## The error function to 1.5e-7 (Abramowitz and Stegun 7.1.26); GDScript has none.
static func erf_approx(x: float) -> float:
	var t: float = 1.0 / (1.0 + 0.3275911 * absf(x))
	var poly: float = t * (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))))
	return signf(x) * (1.0 - poly * exp(-x * x))
