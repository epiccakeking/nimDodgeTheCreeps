import sdl2, sdl2/image, sdl2/ttf
import std/math
import std/lists
import std/random
import ./vectors
const
  GameWidth = 480
  GameHeight = 720
  PlayerSpeed = 400
  EnemySpeed = 200
  SpawnInterval = 1
  PlayerRadius = 20 # TODO: Make sure this is correct
  EnemyRadius = 40  # TODO: Make sure this is correct

sdl2.init(INIT_EVERYTHING)
ttfInit()

var
  window = "Dodge the Creeps".createWindow(
    SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
    480, 720,
    SDL_WINDOW_SHOWN,
  )
  renderer = window.createRenderer(
    -1,
    Renderer_Accelerated or
    Renderer_PresentVsync or
    Renderer_TargetTexture,
  )

type
  Input {.pure.} = enum none, left, right, up, down, restart
  Animation {.pure.} = enum
    playerWalk, playerUp
    enemyFlying, enemySwimming, enemyWalking
  AnimationPlayer = ref object
    fps: float32
    scale: float32
    time: float32
    playing: bool
    animation: Animation
    flip: tuple[x, y: bool]
  Player = ref object
    dead: bool
    position: Vector2
    animation: AnimationPlayer
  Enemy = ref object
    remove: bool   # Used to signal that it should be removed
    position: Vector2
    angle: float32 # degrees
    animation: AnimationPlayer
  Game = ref object
    over: bool
    score: int
    inputs: array[Input, bool]
    player: Player
    enemies: DoublyLinkedList[Enemy]
    enemySpawnTimer: float32

var player_animations: array[Animation, seq[TexturePtr]]

# Load animation frames
player_animations[Animation.playerWalk] = @[
  renderer.loadTexture("art/playerGrey_walk1.png"),
  renderer.loadTexture("art/playerGrey_walk2.png")]
player_animations[Animation.playerUp] = @[
  renderer.loadTexture("art/playerGrey_up1.png"),
  renderer.loadTexture("art/playerGrey_up2.png")]
player_animations[Animation.enemyFlying] = @[
  renderer.loadTexture("art/enemyFlyingAlt_1.png"),
  renderer.loadTexture("art/enemyFlyingAlt_2.png")]
player_animations[Animation.enemySwimming] = @[
  renderer.loadTexture("art/enemySwimming_1.png"),
  renderer.loadTexture("art/enemySwimming_2.png")]
player_animations[Animation.enemyWalking] = @[
  renderer.loadTexture("art/enemyWalking_1.png"),
  renderer.loadTexture("art/enemyWalking_2.png")]

# Load font
let font = "fonts/Xolonium-Regular.ttf".openFont 64
if font.isNil:
  echo getError()
  quit 1

template frames(a: Animation): untyped =
  player_animations[a]

proc toInput(s: Scancode): Input =
  case s:
  of SDL_SCANCODE_UP: Input.up
  of SDL_SCANCODE_DOWN: Input.down
  of SDL_SCANCODE_LEFT: Input.left
  of SDL_SCANCODE_RIGHT: Input.right
  of SDL_SCANCODE_RETURN: Input.restart
  else: Input.none

proc newPlayer(x, y: float32): Player =
  Player(
    dead: false,
    position: (x, y),
    animation: AnimationPlayer(
      fps: 5,
      scale: 0.5,
      animation: playerWalk))

proc newEnemy(x, y, theta: float32): Enemy =
  Enemy(
    position: (x, y),
    angle: theta,
    animation: AnimationPlayer(
      playing: true,
      fps: 3,
      scale: 0.75,
      animation: (enemyFlying..enemyWalking).rand))

proc newGame(): Game =
  Game(
    player: newPlayer(GameWidth/2, GameHeight/2))


template getFrame(animation: seq[TexturePtr], dt: float32,
    fps: float32): TexturePtr =
  animation[int(dt*fps) mod animation.len]

proc draw(r: RendererPtr, t: TexturePtr, x, y: cint,
    scale = 1.float32, theta = 0.float32, flip = SDL_FLIP_NONE) =
  const nilRect: ptr Rect = nil
  const nilPoint: ptr Point = nil
  var w, h: cint
  t.queryTexture(nil, nil, addr w, addr h)
  w = cint(w.float32 * scale)
  h = cint(h.float32 * scale)
  let textureRect = rect(
    x - (w div 2), y - (w div 2),
    w, h,
  )
  r.copyEx(t, nilRect, textureRect.unsafeAddr, cdouble(theta), nilPoint, flip)

proc draw(r: RendererPtr, a: AnimationPlayer, x, y: cint, theta = 0.float32) =
  let frame = a.animation.frames.getFrame(a.time, 5)
  var flip = SDL_FLIP_NONE
  if a.flip.x:
    flip = flip or SDL_FLIP_HORIZONTAL
  if a.flip.y:
    flip = flip or SDL_FLIP_VERTICAL
  r.draw frame, x, y, a.scale, theta, flip

proc draw(r: RendererPtr, p: Player) =
  if not p.dead:
    r.draw p.animation, cint(p.position.x), cint(p.position.y)

proc draw(r: RendererPtr, e: Enemy) =
  r.draw e.animation, cint(e.position.x), cint(e.position.y), e.angle

proc draw(r: RendererPtr, text: cstring, x, y: cint) =
  let textSurface = font.renderTextSolid(text, color(255, 255, 255, 255))
  if textSurface.isNil:
    echo "Bad render"
  let textTexture = r.createTextureFromSurface(textSurface)
  r.draw(textTexture, x, y)
  textSurface.freeSurface
  textTexture.destroy

proc draw(r: RendererPtr, g: Game) =
  r.draw ($g.score).cstring, GameWidth div 2, 50
  r.draw g.player
  for enemyNode in g.enemies.nodes:
    r.draw enemyNode.value
  if g.over:
    r.draw "Game Over", GameWidth div 2, GameHeight div 2
    r.draw "Press Enter", GameWidth div 2, 3*GameHeight div 4
    r.draw "to restart", GameWidth div 2, 3*GameHeight div 4 + 64

proc update(a: AnimationPlayer, dt: float32) =
  if a.playing:
    a.time += dt

template pressed (g: Game, key: untyped): bool =
  g.inputs[Input.key]

template clip(a, lower, upper: float32) =
  if a < lower:
    a = lower
  if a > upper:
    a = upper

proc update(p: Player, g: Game, dt: float32) =
  # Compute the direction vector
  var delta = (0.float32, 0.float32).Vector2
  if g.pressed left:
    delta.x -= 1
  if g.pressed right:
    delta.x += 1
  if g.pressed up:
    delta.y -= 1
  if g.pressed down:
    delta.y += 1
  delta.normalize

  # Apply movement to the player, clipping to the bounds of the game
  p.position += delta * dt * PlayerSpeed
  p.position.x.clip 0, GameWidth
  p.position.y.clip 0, GameHeight

  # Update animation parameters and frame time
  p.animation.playing = delta.length != 0
  if delta.x != 0:
    p.animation.animation = playerWalk
    p.animation.flip.y = false
    p.animation.flip.x = delta.x < 0
  elif delta.y != 0:
    p.animation.animation = playerUp
    p.animation.flip.y = delta.y > 0
  if delta.x == 0 and delta.y == 0:
    p.animation.playing = false
  elif not p.animation.playing:
    p.animation.playing = true
    p.animation.time = 0
  p.animation.update dt

proc update(e: Enemy, dt: float32) =
  if e.remove: return

  e.position += (EnemySpeed.float32 * dt, 0.float32).Vector2.rotated(e.angle)

  # Check if the enemy left the screen
  if e.position.x < -EnemyRadius or
  e.position.x > GameWidth + EnemyRadius or
  e.position.y < -EnemyRadius or
  e.position.y > GameHeight + EnemyRadius:
    e.remove = true

  e.animation.update dt

proc spawnEnemy(g: Game) =
  template addEnemy(x, y, theta) =
    g.enemies.add newDoublyLinkedNode[Enemy](
      newEnemy(x, y, theta + (-20.float32..20.float32).rand))

  var position = (0..(GameWidth+GameHeight)*2).rand
  if position < GameWidth:
    addEnemy position.float32, 0, 90
    return
  position -= GameWidth
  if position < GameHeight:
    addEnemy GameWidth, position.float32, 180
    return
  position -= GameHeight
  if position < GameWidth:
    addEnemy position.float32, GameHeight, 270
    return
  addEnemy 0, position.float32, 0
  return


proc update(g: Game, dt: float32) =
  for node in g.enemies.nodes:
    if node.value.remove:
      g.enemies.remove node
    else:
      node.value.update dt

      # Collision check
      if (g.player.position - node.value.position).length < EnemyRadius + PlayerRadius:
        g.player.dead = true
        g.over = true

  if g.over: return # The rest should be ignored past the end of the game
  g.player.update g, dt
  g.enemySpawnTimer += dt
  if g.enemySpawnTimer > SpawnInterval:
    g.spawnEnemy
    g.enemySpawnTimer -= SpawnInterval
    g.score += 1

var
  game = newGame()
  time, prevTime: uint64
  dt: float32

randomize()
time = getPerformanceCounter()
var event = defaultEvent
while true:
  prevTime = time
  time = getPerformanceCounter()
  dt = (time-prevTime).float32/getPerformanceFrequency().float32
  while event.pollEvent:
    case event.kind:
    of QuitEvent: quit 0
    of KeyDown:
      let input = event.key.keysym.scancode.toInput
      game.inputs[input] = true
      if input == restart and game.over:
        game = newGame()
    of KeyUp: game.inputs[event.key.keysym.scancode.toInput] = false
    else: discard

  # Background
  renderer.setDrawColor 0x38, 0x5f, 0x61, 0xff
  renderer.clear

  renderer.draw game
  game.update dt

  renderer.present
