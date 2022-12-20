import std/math

type Vector2* = tuple[x, y: float32]
template normalize*(v: Vector2) =
  let length = v.length
  if length > 0:
    v.x /= length
    v.y /= length

template length*(v: Vector2): float32 =
  sqrt(v.x.pow(2) + v.y.pow(2))

template `+`*(v1, v2: Vector2): Vector2 =
  (v1.x+v2.x, v1.y+v2.y).Vector2

template `+=`*(v1, v2: Vector2) =
  v1.x+=v2.x
  v1.y+=v2.y

template `-`*(v1, v2: Vector2): Vector2 =
  (v1.x-v2.x, v1.y-v2.y).Vector2

template `*`*(v: Vector2, scalar: float32): Vector2 =
  (v.x*scalar, v.y*scalar).Vector2

# Angle is in clockwise degrees, assuming +y is down
func rotated *(v: Vector2, angle: float32): Vector2 =
  (
    v.x*cos(angle.degToRad) - v.y*sin(angle.degToRad),
    v.y*cos(angle.degToRad) + v.x*sin(angle.degToRad)).Vector2
