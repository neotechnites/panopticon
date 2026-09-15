class_name RingPath
extends RefCounted

## A planned route over a [RingBake]: corner points, and which link each lies on.

var points: PackedVector3Array = PackedVector3Array()
## The link that starts at a point, or -1; the point after it is that link's end.
var links: PackedInt32Array = PackedInt32Array()
## The next corner to steer at.
var cursor: int = 0


func clear() -> void:
	points.clear()
	links.clear()
	cursor = 0


func append(point: Vector3, link: int) -> void:
	points.append(point)
	links.append(link)


func size() -> int:
	return points.size()


func is_empty() -> bool:
	return points.is_empty()


func last() -> Vector3:
	return points[points.size() - 1]


## The index at which the next link starts, from [param from], or -1.
func next_link_from(from: int) -> int:
	for index: int in range(maxi(from, 0), links.size() - 1):
		if links[index] >= 0:
			return index
	return -1


## Metres along the corners from [param from] to [param to], in the horizontal plane.
func metres_between(from: int, to: int) -> float:
	var total: float = 0.0
	for index: int in range(maxi(from, 0) + 1, mini(to + 1, points.size())):
		var a: Vector3 = points[index - 1]
		var b: Vector3 = points[index]
		total += Vector2(b.x - a.x, b.z - a.z).length()
	return total
