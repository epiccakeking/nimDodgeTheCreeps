import sdl2
import sdl2/[image, ttf, mixer, audio]
import std/[math, lists, random, os]
import ./vectors
const
  GameWidth = 480
  GameHeight = 720

  SpawnInterval = 0.5
  ScoreInterval = 1

  PlayerSpeed = 400
  PlayerRadius = 20

  EnemySpeed = 200
  EnemyRadius = 40
  EnemyAngleVariance = 45

let appDir = getAppDir()

sdl2.init(INIT_EVERYTHING)
ttfInit()

var
  window = "Dodge the Creeps".createWindow(
    SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
    480, 720,
    SDL_WINDOW_SHOWN or SDL_WINDOW_RESIZABLE)
  renderer = window.createRenderer(
    -1,
    Renderer_Accelerated or
    Renderer_PresentVsync or
    Renderer_TargetTexture)

template sdlAssert(statement: untyped, msg: string) =
  if not (statement):
    echo msg, ": ", getError()
    quit 1

sdlAssert renderer.setLogicalSize(GameWidth, GameHeight) == 0, "Failed to set logical size"

sdlAssert openAudio(44100, AUDIO_F32, 2, 4096) == 0, "Failed to open audio"

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
    scoreTimer: float32
    startTimer: float32 # Time after the start of the game
    endTimer: float32   # Time after end of game

var animation_frames: array[Animation, seq[TexturePtr]]

template load(relativePath: string): TexturePtr =
  renderer.loadTexture((appDir / relativePath).cstring)

# Load animation frames
animation_frames[Animation.playerWalk] = @[
  load "art/playerGrey_walk1.png",
  load "art/playerGrey_walk2.png"]
animation_frames[Animation.playerUp] = @[
  load "art/playerGrey_up1.png",
  load "art/playerGrey_up2.png"]
animation_frames[Animation.enemyFlying] = @[
  load "art/enemyFlyingAlt_1.png",
  load "art/enemyFlyingAlt_2.png"]
animation_frames[Animation.enemySwimming] = @[
  load "art/enemySwimming_1.png",
  load "art/enemySwimming_2.png"]
animation_frames[Animation.enemyWalking] = @[
  load "art/enemyWalking_1.png",
  load "art/enemyWalking_2.png"]

template frames(a: Animation): untyped =
  animation_frames[a]

# Load font
let font = (appDir/"fonts/Xolonium-Regular.ttf").cstring.openFont 64
sdlAssert not font.isNil, "Failed to open font"

# Load audio
let
  gameover = (appDir/"art/gameover.wav").cstring.loadWAV
  music = (appDir/"art/House In a Forest Loop.ogg").cstring.loadMUS

proc toInput(s: Scancode): Input =
  case s:
  of SDL_SCANCODE_UP: Input.up
  of SDL_SCANCODE_DOWN: Input.down
  of SDL_SCANCODE_LEFT: Input.left
  of SDL_SCANCODE_RIGHT: Input.right
  of SDL_SCANCODE_RETURN: Input.restart
  else: Input.none

proc newPlayer(x, y: float32): Player = Player(
  dead: false,
  position: (x, y),
  animation: AnimationPlayer(
    fps: 5,
    scale: 0.5,
    animation: playerWalk))

proc newEnemy(x, y, theta: float32): Enemy = Enemy(
  position: (x, y),
  angle: theta,
  animation: AnimationPlayer(
    playing: true,
    fps: 3,
    scale: 0.75,
    animation: (enemyFlying..enemyWalking).rand))

proc newGame(): Game = Game(
  player: newPlayer(GameWidth/2, 540))


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
    x - (w div 2), y - (h div 2),
    w, h)
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
  sdlAssert not textSurface.isNil, "Failed to render text"
  let textTexture = r.createTextureFromSurface(textSurface)
  r.draw(textTexture, x, y)
  textSurface.freeSurface
  textTexture.destroy

proc draw(r: RendererPtr, g: Game) =
  # Background
  r.setDrawColor 0x38, 0x5f, 0x61, 0xff
  var bgRect = rect(0, 0, GameWidth, GameHeight)
  r.fillRect(bgRect)

  # Score
  r.draw ($g.score).cstring, GameWidth div 2, 50

  # "Entities"
  r.draw g.player
  for enemyNode in g.enemies.nodes:
    r.draw enemyNode.value

  # HUD
  if g.over:
    if g.endTimer < 2:
      r.draw "Game Over", GameWidth div 2, GameHeight div 2
    else:
      r.draw "Dodge the", GameWidth div 2, GameHeight div 2
      r.draw "creeps!", GameWidth div 2, GameHeight div 2 + 64

    if g.endTimer > 3:
      r.draw "Press Enter", GameWidth div 2, 3*GameHeight div 4
      r.draw "to restart", GameWidth div 2, 3*GameHeight div 4 + 64
  elif g.startTimer < 2:
    r.draw "Get ready!", GameWidth div 2, GameHeight div 2

proc update(a: AnimationPlayer, dt: float32) =
  if a.playing: a.time += dt

template pressed (g: Game, key: untyped): bool =
  g.inputs[Input.key]

template clip(a, lower, upper: float32) =
  if a < lower:
    a = lower
  elif a > upper:
    a = upper

proc update(p: Player, g: Game, dt: float32) =
  if p.dead: return

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

  # Collision check
  for enemy in g.enemies.items:
    if (g.player.position - enemy.position).length < EnemyRadius + PlayerRadius:
      g.player.dead = true
      g.over = true
      discard playChannel(-1, gameover, 0)
      break

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
      newEnemy(x, y, theta + (-EnemyAngleVariance.float32..EnemyAngleVariance.float32).rand))

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
  g.startTimer += dt

  for node in g.enemies.nodes:
    if node.value.remove:
      g.enemies.remove node
    else:
      node.value.update dt

  g.player.update g, dt

  if g.over:
    g.endTimer += dt
    if playingMusic().bool:
      discard haltMusic()
    return # The rest should be ignored past the end of the game

  if not playingMusic().bool:
    sdlAssert music.playMusic(-1) == 0, "Playing music failed"

  if g.startTimer > 2:
    g.enemySpawnTimer += dt
    if g.enemySpawnTimer > SpawnInterval:
      g.spawnEnemy
      g.enemySpawnTimer -= SpawnInterval

    g.scoreTimer += dt
    if g.scoreTimer > ScoreInterval:
      g.scoreTimer -= ScoreInterval
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
    of QuitEvent:
      mixer.closeAudio()
      quit 0
    of KeyDown:
      let input = event.key.keysym.scancode.toInput
      game.inputs[input] = true
      if input == restart and game.over:
        game = newGame()
    of KeyUp: game.inputs[event.key.keysym.scancode.toInput] = false
    else: discard

  renderer.setDrawColor 0, 0, 0, 255
  renderer.clear

  renderer.draw game
  game.update dt

  renderer.present
