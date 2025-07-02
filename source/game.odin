package game

import "core:log"
import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:os"
import "core:c"
import "core:math/linalg"

import stbi "vendor:stb/image"

import sapp "sokol/app"
import sg "sokol/gfx"
import sglue "sokol/glue"
import slog "sokol/log"

LOGICAL_W :: 1920
LOGICAL_H :: 1080

PLAYER_SIZE :: Vec2{150, 30}
PLAYER_VELOCITY :: 1000
PLAYER_COLOR :: Vec3{1,1,1}
PADDLE_BOUNCE_STRENGTH :: 2
INITIAL_LIVES :: 3

BALL_RADIUS :: 16
BALL_SIZE :: Vec2{ BALL_RADIUS * 2, BALL_RADIUS * 2}
BALL_INITIAL_VELOCITY :: Vec2{200, -700}
BALL_COLOR :: Vec3{1,1,1}

UI_LIVES_POSITION :: Vec2{50, 50}
UI_MENU_TITLE_OFFSET :: 50
UI_MENU_LINE_SPACING :: 30

BACKGROUND_COLOR :: sg.Color{0.1, 0.1, 0.1, 1}
TEXT_COLOR_WHITE :: Vec3{1, 1, 1}
TEXT_COLOR_LIGHT_GRAY :: Vec3{0.8, 0.8, 0.8}
TEXT_COLOR_GRAY :: Vec3{0.6, 0.6, 0.6}
TEXT_COLOR_GREEN :: Vec3{0, 1, 0}
TEXT_COLOR_YELLOW :: Vec3{1, 1, 0}

MSAA_SAMPLE_COUNT :: 4
SHAKE_DURATION :: 0.1
DEFAULT_FONT_SIZE :: 24

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Mat4f32 :: matrix[4,4]f32

Game_Memory :: struct {
	width: u32,
	height: u32,
	state: Game_State,
	keys: #sparse [sapp.Keycode]bool,
	keys_processed: #sparse [sapp.Keycode]bool,

	player: Player,
    ball: Ball,

    levels: [dynamic]Game_Level,
    level: u32,
    powerups: [dynamic]Powerup,
    lives: i32,

    resman: ^Resource_Manager,
    audio_system: Audio_System,

    sprite_renderer: Sprite_Renderer,
    particle_renderer: Particle_Renderer,
    post_processor: Post_Processor,
    text_renderer: Text_Renderer,

    ball_pg: Particle_Generator,

    screen_width: u32,
    screen_height: u32,
    viewport_x: i32,
    viewport_y: i32,
    viewport_width: i32,
    viewport_height: i32,
}

Game_State :: enum {
	Menu,
	Active,
	Win,
}

Game_Level :: struct {
    bricks: [dynamic]Brick,
}

Entity :: struct {
    position: Vec2,
    velocity: Vec2,
    size: Vec2, 
	color: Vec3,
	rotation: f32,
    texture_name: string,
}

Brick :: struct {
    using entity: Entity,
    is_solid, destroyed: bool,
}

Ball :: struct {
    using entity: Entity,
    radius: f32,
    stuck, sticky, passthrough: bool,
}

Player :: struct {
    using entity: Entity,
}

Direction :: enum { Up, Down, Left, Right, }
Direction_Vectors := [Direction]Vec2{
	.Up = {0,1},
	.Down = {0,-1},
	.Left = {-1,0},
	.Right = {1,0},
}

Vertex :: struct {
	x, y: f32,
	u, v: f32,
}

Collision_Data :: struct {
    collided: bool,
    direction: Direction,
    difference_vector: Vec2,
}

Tile_Code :: enum {
    Space = 0,
    Indestructible_Brick = 1,
    Brick_A = 2,
    Brick_B = 3,
    Brick_C = 4,
    Brick_D = 5,
}

g: ^Game_Memory

@export
game_app_default_desc :: proc() -> sapp.Desc {
	return {
		width = LOGICAL_W,
		height = LOGICAL_H,
		sample_count = MSAA_SAMPLE_COUNT,
		window_title = "Breakout",
		icon = { sokol_default = true },
		logger = { func = slog.func },
		gl_major_version = 3,
		gl_minor_version = 0,
		// html5_canvas_selector = "#canvas",
		// html5_canvas_resize = true,
		// html5_update_document_title = true,
	}
}

@export
game_init :: proc() {
	context.logger = log.create_console_logger(.Info)
    log.info("### START Game Init ###")

	g = new(Game_Memory)
    if g == nil {
        log.error("Failed to allocate game memory")
        return
    }
	game_hot_reloaded(g)

    stbi.set_flip_vertically_on_load(1)

	sg.setup({
		environment = sglue.environment(),
		logger = { func = slog.func },
	})

    if !sg.isvalid() {
        log.error("Failed to initialize Sokol GFX")
        return
    }

	g.state = .Menu
	g.width = LOGICAL_W
	g.height = LOGICAL_H
    g.screen_width = LOGICAL_W
    g.screen_height = LOGICAL_H
    g.viewport_width = LOGICAL_W
    g.viewport_height = LOGICAL_H
    g.lives = INITIAL_LIVES

    update_viewport_and_projection(u32(sapp.width()), u32(sapp.height()))

    g.resman = new(Resource_Manager)
    resman_init(g.resman)
    log.info("Initialized resource manager")

    create_and_load_white_texture(g.resman)
    log.info("Initialized white fallback texture")

    sprite_renderer_init(&g.sprite_renderer, g.resman)
    log.info("Initialized sprite renderer")

    particle_renderer_init(&g.particle_renderer, g.resman^)
    log.info("Initialized particle renderer")
 
    particle_generator_init(&g.ball_pg)
    log.info("Initialized ball particle generator")

    post_processor_init(&g.post_processor, i32(g.width), i32(g.height))
    log.info("Initialized post processor")

    resman_load_texture(g.resman, "assets/background.jpg", "background")
    resman_load_texture(g.resman, "assets/block.png", "block")
    resman_load_texture(g.resman, "assets/block_solid.png", "block_solid")
    resman_load_texture(g.resman, "assets/paddle.png", "paddle")
    resman_load_texture(g.resman, "assets/awesomeface.png", "ball")
    resman_load_texture(g.resman, "assets/particle.png", "particle")
    resman_load_texture(g.resman, "assets/powerup_chaos.png", "chaos")
    resman_load_texture(g.resman, "assets/powerup_confuse.png", "confuse")
    resman_load_texture(g.resman, "assets/powerup_increase.png", "size")
    resman_load_texture(g.resman, "assets/powerup_passthrough.png", "passthrough")
    resman_load_texture(g.resman, "assets/powerup_speed.png", "speed")
    resman_load_texture(g.resman, "assets/powerup_sticky.png", "sticky")
    log.info("Finished loading textures")

    audio_init(&g.audio_system)
    log.info("Initialized audio system")

    audio_load_sound(&g.audio_system, "assets/music.ogg", "music")
    audio_load_sound(&g.audio_system, "assets/hit-nonsolid.ogg", "hit-nonsolid")
    audio_load_sound(&g.audio_system, "assets/solid.wav", "hit-solid")
    audio_load_sound(&g.audio_system, "assets/powerup.wav", "get-powerup")
    audio_load_sound(&g.audio_system, "assets/bleep.wav", "hit-paddle")
    log.info("Finished loading sounds")

    text_renderer_init(&g.text_renderer, "assets/arial.ttf", DEFAULT_FONT_SIZE)
    log.info("Initialized text renderer")

    one, two, three, four: Game_Level
    game_level_load(&one, "assets/one.lvl", u32(g.width), u32(g.height) / 2)
    append(&g.levels, one)
    game_level_load(&two, "assets/two.lvl", u32(g.width), u32(g.height) / 2)
    append(&g.levels, two)
    game_level_load(&three, "assets/three.lvl", u32(g.width), u32(g.height) / 2)
    append(&g.levels, three)
    game_level_load(&four, "assets/four.lvl", u32(g.width), u32(g.height) / 2)
    append(&g.levels, four)
    g.level = 0

    player_init(&g.player, g.width, g.height)
    ball_init(&g.ball, g.player, BALL_INITIAL_VELOCITY)

    log.info("## END Game Init ###")

    play_sound(&g.audio_system, "music", true)
}

@export
game_frame :: proc() {
	dt := f32(sapp.frame_duration())
    update(dt)
    render(dt)
	free_all(context.temp_allocator)
}

update :: proc(dt: f32) {
    game_process_input(dt)
    ball_update(dt, g.width)
    collisions_update(g.levels[g.level].bricks[:], &g.audio_system)
    particle_generator_update(&g.ball_pg, dt, g.ball, 2, {g.ball.radius / 2, g.ball.radius / 2})
    powerups_update(dt, &g.powerups)
    post_processor_update(&g.post_processor, dt)

    // Lose life
    if g.ball.position.y >= f32(g.height) {
        g.lives -= 1
        if g.lives == 0 {
            game_reset_level()
            g.state = .Menu
        }
        game_reset_player()
    }

    // Win condition
    if g.state == .Active && game_is_completed(g.levels[g.level]) {
        game_reset_level()
        game_reset_player()
        g.post_processor.chaos = true
        g.state = .Win
    }
}

render :: proc(dt: f32) {
    msaa_pass_action := sg.Pass_Action {
        colors = { 0 = { load_action = .CLEAR, clear_value = BACKGROUND_COLOR }},
    }
    // Render scene to MSAA fb
    sg.begin_pass({ 
        action = msaa_pass_action, attachments = g.post_processor.msaa_attachments,
    })
    sg.apply_viewport(0, 0, i32(g.width), i32(g.height), true)

    // Sprites
    sg.apply_pipeline(g.sprite_renderer.pip)
    draw_sprite(
        &g.sprite_renderer, 
        g.resman^,
        {0,0}, 
        {f32(g.width), f32(g.height)}, 
        0, 
        "background",
    )
    game_level_draw(
        &g.levels[g.level], 
        &g.sprite_renderer, 
        g.resman^,
    )
    draw_sprite(
        &g.sprite_renderer, 
        g.resman^,
        g.player.position, 
        g.player.size, 
        g.player.rotation, 
        g.player.texture_name, 
        g.player.color,
    )
    for p in g.powerups {
        if !p.destroyed {
            draw_sprite(
                &g.sprite_renderer, 
                g.resman^,
                p.position, 
                p.size, 
                p.rotation, 
                p.texture_name, 
                p.color,
            )
        }
    }
    draw_sprite(
        &g.sprite_renderer, 
        g.resman^,
        g.ball.position, 
        g.ball.size, 
        g.ball.rotation, 
        g.ball.texture_name, 
        g.ball.color,
    )

    // Particles
    sg.apply_pipeline(g.particle_renderer.pip)
    particle_generator_draw(&g.particle_renderer, g.ball_pg, g.resman^)

    // Text
    lives_text := fmt.tprintf("Lives: %v", g.lives)
    text_draw(&g.text_renderer, lives_text, UI_LIVES_POSITION.x, UI_LIVES_POSITION.y, TEXT_COLOR_WHITE)
    if g.state == .Menu {
        text_draw_centered(&g.text_renderer, "BREAKOUT", 
            f32(g.width)/2, f32(g.height)/2 - UI_MENU_TITLE_OFFSET, TEXT_COLOR_WHITE)
        text_draw_centered(&g.text_renderer, "Press ENTER to start", 
            f32(g.width)/2, f32(g.height)/2, TEXT_COLOR_LIGHT_GRAY)
        text_draw_centered(&g.text_renderer, "Press W or S to select level", 
            f32(g.width)/2, f32(g.height)/2 + UI_MENU_LINE_SPACING, TEXT_COLOR_GRAY)
        text_draw_centered(&g.text_renderer, "A/D to move paddle", 
            f32(g.width)/2, f32(g.height)/2 + UI_MENU_LINE_SPACING * 2, TEXT_COLOR_GRAY)
    }
    if g.state == .Win {
        text_draw_centered(&g.text_renderer, "YOU WIN!!!", 
            f32(g.width)/2, f32(g.height)/2 + 50, TEXT_COLOR_GREEN)
        text_draw_centered(&g.text_renderer, "Press ENTER to retry or ESC to quit", 
            f32(g.width)/2, f32(g.height)/2 + 100, TEXT_COLOR_YELLOW)
    }

    text_renderer_flush(&g.text_renderer)

    sg.end_pass()

    // Render postprocessed fullscreen quad
    fullscreen_pass_action := sg.Pass_Action {
        colors = { 0 = { load_action = .CLEAR, clear_value = BACKGROUND_COLOR }},
    }
    sg.begin_pass({ action = fullscreen_pass_action, swapchain = sglue.swapchain() })
        sg.apply_viewport(g.viewport_x, g.viewport_y, g.viewport_width, g.viewport_height, true)
        sg.apply_pipeline(g.post_processor.pip)
        sg.apply_bindings(g.post_processor.bind)
        post_processor_apply_uniforms(&g.post_processor, dt)
        sg.draw(0, 4, 1)
    sg.end_pass()
    sg.commit()
}

player_init :: proc(player: ^Player, game_width: u32, game_height: u32) {
    pos := Vec2 {
        (f32(game_width) / 2) - (PLAYER_SIZE.x / 2), 
        f32(game_height) - PLAYER_SIZE.y,
    }
	entity_init(
        entity = &player.entity, 
        position = pos, 
        size = PLAYER_SIZE, 
        texture_name = "paddle",
        color = PLAYER_COLOR,
    )
}

compute_projection :: proc() -> Mat4f32 {
	proj := linalg.matrix_ortho3d_f32(0, f32(g.width), f32(g.height), 0, -1, 1)
    return proj
}

force_reset: bool

@export
game_event :: proc(e: ^sapp.Event) {
    if e.type == .KEY_DOWN {
        g.keys[e.key_code] = true
        if g.keys[.F6] {
            force_reset = true
        }
        if g.keys[.ESCAPE] {
            sapp.quit()
        }
    }
    if e.type == .KEY_UP {
        g.keys[e.key_code] = false
        g.keys_processed[e.key_code] = false
	}
    if e.type == .RESIZED {
        update_viewport_and_projection(u32(e.framebuffer_width), u32(e.framebuffer_height))
    }
}

game_process_input :: proc(dt: f32) {
    if g.state == .Menu {
        if g.keys[.ENTER] && !g.keys_processed[.ENTER]{
            g.keys_processed[.ENTER] = true
            g.state = .Active
        }
        if g.keys[.W] && !g.keys_processed[.W] {
            g.keys_processed[.W] = true
            g.level = (g.level + 1) % 4
        }
        if g.keys[.S] && !g.keys_processed[.S] {
            g.keys_processed[.S] = true
            g.level = (g.level - 1) % 4
        }
    }

    if g.state == .Active {
        dx := PLAYER_VELOCITY * dt
        if g.keys[.A] {
				if g.player.position.x >= 0 {
					g.player.position.x -= dx
					if g.ball.stuck {
						g.ball.position.x -= dx
					}
				}
        }
        if g.keys[.D] {
            if g.player.position.x <= f32(g.width) - g.player.size.x {
                g.player.position.x += dx
                if g.ball.stuck {
                	g.ball.position.x += dx
                }
            }
        }
        if g.keys[.SPACE] {
            g.ball.stuck = false
        }

        // for debug
        if g.keys[.R] {
				// win state
				game_reset_player()
				game_reset_level()
				g.post_processor.chaos = true
				g.state = .Win
        }

        g.player.position.x = clamp(
            g.player.position.x, 
            0, 
            f32(g.width) - g.player.size.x,
        )
    }

    if g.state == .Win {
        if g.keys[.ENTER] {
            g.post_processor.chaos = false
            g.state = .Menu
        }
    }
}

@export
game_cleanup :: proc() {
	sg.shutdown()
    sprite_renderer_cleanup(g.sprite_renderer)
    particle_renderer_cleanup(g.particle_renderer)
    text_renderer_cleanup(&g.text_renderer)
    post_processor_cleanup(g.post_processor)
    resman_cleanup(g.resman)
    audio_cleanup(&g.audio_system)
	free(g)
}

@(export)
game_memory :: proc() -> rawptr {
	return g
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = (^Game_Memory)(mem)
	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside
	// `g`. Then that state carries over between hot reloads.
}

@(export)
game_force_restart :: proc() -> bool {
	return force_reset
}

game_reset_player :: proc() {
    g.player.size = PLAYER_SIZE
    g.player.position = Vec2{f32(g.width) / 2 - (g.player.size.x / 2), f32(g.height) - PLAYER_SIZE.y}
    ball_reset(g.player.position + Vec2{PLAYER_SIZE.x / 2 - BALL_RADIUS, -(BALL_RADIUS * 2)})

    g.post_processor.chaos = false
    g.post_processor.confuse = false

    g.ball.passthrough = false
    g.ball.sticky = false
    g.ball.color = {1,1,1}
}

entity_init :: proc(
	entity: ^Entity, 
	position: Vec2 = {0,0}, 
	size: Vec2 = {1,1}, 
	color: Vec3 = {1,1,1},
	velocity: Vec2 = {0,0},
    texture_name: string = "white",
) {
	entity.position = position
	entity.size = size
	entity.color = color
	entity.velocity = velocity
	entity.rotation = 0
    entity.texture_name = texture_name
}

read_image_from_file :: proc(file: string) -> ([^]byte, i32, i32, i32) {
    file_data, ok := read_entire_file(file)
    if !ok {
        log.error("Failed to read image file:", file)
        return nil, 0, 0, 0
    }
    defer delete(file_data)

    width, height, n_channels: c.int
    pixels := stbi.load_from_memory(raw_data(file_data), c.int(len(file_data)), &width, &height, &n_channels, 4)
    if pixels == nil {
        log.error("Failed to load image")
        return nil, 0, 0, 0
    }

    return pixels, i32(width), i32(height), i32(n_channels)
}

game_is_completed :: proc(level: Game_Level) -> bool {
    for tile in level.bricks {
        if !tile.is_solid && !tile.destroyed {
            return false
        }
    }
    return true
}

ball_update :: proc(dt: f32, window_width: u32) {
    if !g.ball.stuck {
        g.ball.position += g.ball.velocity * dt

        if g.ball.position.x < 0 {
            g.ball.velocity.x *= -1
            g.ball.position.x = 0
        } else if g.ball.position.x + g.ball.size.x >= f32(window_width) {
            g.ball.velocity.x *= -1
            g.ball.position.x = f32(window_width) - g.ball.size.x
        }

        if g.ball.position.y < 0 {
            g.ball.velocity.y *= -1
            g.ball.position.y = 0
        }
    }
}

ball_reset :: proc(position: Vec2) {
    g.ball.position = position
    g.ball.velocity = BALL_INITIAL_VELOCITY
    g.ball.size = BALL_SIZE
    g.ball.color = BALL_COLOR
    g.ball.stuck = true
    g.ball.sticky = false
    g.ball.passthrough = false
}

game_level_load :: proc(game_level: ^Game_Level, file: string, level_width: u32, level_height: u32) {
    // clear bricks
    clear(&game_level.bricks)

    // load file to string
    data_string := read_file_to_string(file)
    defer delete(data_string)

    data_string = strings.trim_space(data_string)

    // read string to brick/space types into tileData
    tile_data: [dynamic][dynamic]Tile_Code
    lines, _ := strings.split(data_string, "\n")
    defer delete(lines)

    for row, y in lines {
        trim_a := strings.trim_space(row)
        if len(trim_a) == 0 do continue

        chars, _ := strings.split(trim_a, " ")
        defer delete(chars)

        row_codes: [dynamic]Tile_Code
        for char, x in chars {
            trim_b := strings.trim_space(char)
            if len(trim_b) == 0 do continue

            val, ok := strconv.parse_int(trim_b)
            if !ok {
                log.error("Failed to parse int from tile_code:", trim_b, "pos:", y, x)
                continue
            }

            code: Tile_Code
            switch val {
            case 0:
                code = .Space
            case 1:
                code = .Indestructible_Brick
            case 2:
                code = .Brick_A
            case 3:
                code = .Brick_B
            case 4:
                code = .Brick_C
            case 5:
                code = .Brick_D
            }
            append(&row_codes, code)
        }
        append(&tile_data, row_codes)
    }
    if len(tile_data) > 0 {
        game_level_init(game_level, tile_data[:], level_width, level_height)
    }
}

game_level_init :: proc(game_level: ^Game_Level, tile_data: [][dynamic]Tile_Code, level_width: u32, level_height: u32) {
    unit_width := f32(level_width) / f32(len(tile_data[0]))
    unit_height := f32(level_height) / f32(len(tile_data))
    for row, r in tile_data {
        for tile_code, c in row {
            pos := Vec2{unit_width * f32(c), unit_height * f32(r)}
            size := Vec2{unit_width, unit_height}
            color := Vec3{1,1,1}
            switch tile_code {
            case .Space:
            case .Indestructible_Brick:
                color = {.8,.8,.7}
                obj: Brick
                entity_init(&obj, pos, size, color, {}, "block_solid")
                obj.is_solid = true
                append(&game_level.bricks, obj)
            case .Brick_A:
                color = {.2,.6,1}
                obj: Brick
                entity_init(&obj, pos, size, color, {}, "block")
                append(&game_level.bricks, obj)
            case .Brick_B:
                color = {.0,.7,.0}
                obj: Brick
                entity_init(&obj, pos, size, color, {}, "block")
                append(&game_level.bricks, obj)
            case .Brick_C:
                color = {.8,.8,.4}
                obj: Brick
                entity_init(&obj, pos, size, color, {}, "block")
                append(&game_level.bricks, obj)
            case .Brick_D:
                color = {1.,.5,.0}
                obj: Brick
                entity_init(&obj, pos, size, color, {}, "block")
                append(&game_level.bricks, obj)
            }
        }
    }
}

game_level_draw :: proc(game_level: ^Game_Level, sr: ^Sprite_Renderer, rm: Resource_Manager) {
    for tile in game_level.bricks {
        if !tile.destroyed {
            draw_sprite(
                sr,
                rm,
                tile.position, 
                tile.size, 
                tile.rotation, 
                tile.texture_name, 
                tile.color,
            )
        }
    }
}

game_reset_level :: proc() {
    switch g.level {
    case 0:
        game_level_load(&g.levels[0], "assets/one.lvl", g.width, g.height/2)
    case 1:
        game_level_load(&g.levels[1], "assets/two.lvl", g.width, g.height/2)
    case 2:
        game_level_load(&g.levels[2], "assets/three.lvl", g.width, g.height/2)
    case 3:
        game_level_load(&g.levels[3], "assets/four.lvl", g.width, g.height/2)
    }
    clear(&g.powerups)
    g.lives = INITIAL_LIVES
}

read_file_to_string :: proc(path: string) -> string {
	data, ok := os.read_entire_file_from_filename(path)
	if !ok {
		log.error("Failed to read file")
		os.exit(-1)
	}

	return string(data)
}

vector_direction :: proc(target: Vec2) -> Direction {
    max: f32
    best_match: Direction
    for dir in Direction {
        dot := linalg.dot(linalg.normalize0(target), Direction_Vectors[dir])
        if dot > max {
            max = dot
            best_match = dir
        }
    }
    return best_match
}

update_viewport_and_projection :: proc(screen_width: u32, screen_height: u32) {
    g.screen_width = screen_width
    g.screen_height = screen_height

    target_aspect := f32(LOGICAL_W) / f32(LOGICAL_H)
    screen_aspect := f32(screen_width) / f32(screen_height)

    if screen_aspect > target_aspect {
        // Screen is wider than target - letterbox on sides
        g.viewport_height = i32(screen_height)
        g.viewport_width = i32(f32(screen_height) * target_aspect)
        g.viewport_x = (i32(screen_width) - g.viewport_width) / 2
        g.viewport_y = 0
    } else {
        // Screen is taller than target - letterbox on top/bottom
        g.viewport_width = i32(screen_width)
        g.viewport_height = i32(f32(screen_width) / target_aspect)
        g.viewport_x = 0
        g.viewport_y = (i32(screen_height) - g.viewport_height) / 2
    }
}

ball_init :: proc(ball: ^Ball, player: Player, velocity: Vec2) {
    pos := player.position + Vec2 { 
        f32(PLAYER_SIZE.x) / 2 - BALL_RADIUS, 
        -BALL_RADIUS * 2,
    }
    entity_init(
        entity = &ball.entity, 
        position = pos, 
        size = BALL_SIZE,
        color = BALL_COLOR, 
        velocity = velocity, 
        texture_name = "ball"
    )
    ball.stuck = true
    ball.radius = BALL_RADIUS
}

create_and_load_white_texture :: proc(rm: ^Resource_Manager) {
    white_pixels := [4]u8{255, 255, 255, 255}
    white_texture := sg.make_image({
        width = 1,
        height = 1,
        data = {
            subimage = {
                0 = {
                    0 = { ptr = &white_pixels, size = size_of(white_pixels) },
                },
            },
        },
        label = "white-texture",
    })
    if sg.query_image_state(white_texture) != .VALID {
       log.error("Failed to create white texture")
       return
    }
    resman_set_texture(rm, "white", white_texture)
}
