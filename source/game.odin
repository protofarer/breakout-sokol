package game

import "core:math/linalg"
import "core:image/png"
import "core:log"
import "core:slice"
import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:os"
import "core:math/rand"
import sa "core:container/small_array"
import stbi "vendor:stb/image"
import ma "vendor:miniaudio"
import sapp "sokol/app"
import sg "sokol/gfx"
import sglue "sokol/glue"
import slog "sokol/log"

pr :: fmt.println
to_radians :: linalg.to_radians

LOGICAL_W :: 1920
LOGICAL_H :: 1080

PLAYER_SIZE :: Vec2{150, 30}
PLAYER_VELOCITY :: 1000

BALL_RADIUS :: 16
BALL_INITIAL_VELOCITY :: Vec2{200, -700}

MAX_PARTICLES :: 500

Vec2 :: [2]f32
Vec2i :: [2]i32
Vec3 :: [3]f32
Vec4 :: [4]f32
Mat4 :: matrix[4,4]f32

Game_Memory :: struct {
    sprite_pip: sg.Pipeline,
	sprite_bind: sg.Bindings,

    particle_pip: sg.Pipeline,
    particle_bind: sg.Bindings,

	width: u32,
	height: u32,
	state: Game_State,
	keys: #sparse [sapp.Keycode]bool,
	keys_processed: #sparse [sapp.Keycode]bool,

	player: Entity,
    ball: Ball_Object,

    resman: ^Resource_Manager,

    levels: [dynamic]Game_Level,
    level: u32,
    powerups: [dynamic]Powerup_Object,
    lives: i32,

    ball_pg: Particle_Generator,

    post_processor: Post_Processor,

    audio_engine: ma.engine,

    // shake_time: f32,
    // screen_width: u32,
    // screen_height: u32,
    // viewport_x: i32,
    // viewport_y: i32,
    // viewport_width: i32,
    // viewport_height: i32,
}

Game_State :: enum {
	Menu,
	Active,
	Win,
}

Game_Level :: struct {
    bricks: [dynamic]Entity
}

// TODO: ball, powerup variants
Entity :: struct {
    position: Vec2,
    size: Vec2, 
    velocity: Vec2,
	color: Vec3,
	rotation: f32,
	is_solid: bool,
    destroyed: bool,
    texture_name: string,
}

Ball_Object :: struct {
    using game_object: Entity,
    radius: f32,
    stuck: bool,
    sticky: bool,
    passthrough: bool,
}

POWERUP_SIZE :: Vec2{60,20}
POWERUP_VELOCITY :: Vec2{0,150}

Powerup_Type :: enum {
     // Speed: increases the velocity of the ball by 20%.
    Speed,
     // Sticky: when the ball collides with the paddle, the ball remains stuck to the paddle unless the spacebar is pressed again. This allows the player to better position the ball before releasing it.
    Sticky,
     // Pass-Through: collision resolution is disabled for non-solid blocks, allowing the ball to pass through multiple blocks.
    Passthrough,
     // Pad-Size-Increase: increases the width of the paddle by 50 pixels.
    Padsize_Increase,
     // Confuse: activates the confuse postprocessing effect for a short period of time, confusing the user
    Confuse,
     // Chaos: activates the chaos postprocessing effect for a short period of time, heavily disorienting the user.
    Chaos,
}

Powerup_Object :: struct {
    using object: Entity,
    type: Powerup_Type,
    activated: bool,
    duration: f32,
}

Texture2D :: struct {
    id: u32,
    width: i32,
    height: i32,
    internal_format: i32,
    image_format: u32,
    wrap_s: i32,
    wrap_t: i32,
    filter_min: i32,
    filter_max: i32,
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

Resource_Manager :: struct {
    textures: map[string]sg.Image,
    sounds: map[string]^ma.sound,
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

Particle :: struct {
    position, velocity: Vec2,
    color: Vec4,
    life: f32,
}

Particle_Generator :: struct {
    particles: sa.Small_Array(MAX_PARTICLES, Particle),
    max_particles: int,
    last_used_particle: int,
}

Post_Processor :: struct {
    // anti-aliasing via multisampled framebuffer
    msaa_attachments: sg.Attachments,
    msaa_color_img: sg.Image,
    msaa_depth_img: sg.Image,

    // Regular framebuffer with texture attachment
    resolve_color_img: sg.Image,

    // Postprocessing pipeline and bindings
    pip: sg.Pipeline,
    bind: sg.Bindings,

    shake: bool,
    confuse: bool,
    chaos: bool,

    shake_time: f32,

    width, height: i32,

    // cached uniform params
    fs_params: Postprocess_Fs_Params,
}

g: ^Game_Memory

@export
game_app_default_desc :: proc() -> sapp.Desc {
	return {
		width = LOGICAL_W,
		height = LOGICAL_H,
		sample_count = 4,
		window_title = "Breakout",
		icon = { sokol_default = true },
		logger = { func = slog.func },
		html5_update_document_title = true,
	}
}

@export
game_init :: proc() {
	context.logger = log.create_console_logger()
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

	g.state = .Active
	g.width = LOGICAL_W
	g.height = LOGICAL_H
    // g.screen_width = LOGICAL_W
    // g.screen_height = LOGICAL_H
    // g.viewport_width = LOGICAL_W
    // g.viewport_height = LOGICAL_H
    g.lives = 3

    // TODO: letterboxing
    // update_viewport_and_projection(LOGICAL_W, LOGICAL_H)

    g.resman = new(Resource_Manager)
    resman_init()
    log.info("Initialized resource manager")

    sprite_renderer_init()
    log.info("Initialized sprite renderer")

    // TODO: break out partcle_gen and renderer (diff pg's can use same renderer)
    particle_generator_init(&g.ball_pg)
    log.info("Initialized particle generator and particle renderer")

    post_processor_init(&g.post_processor, i32(g.width), i32(g.height))
    log.info("Initialized post processor")

    resman_load_texture("assets/background.jpg", "background")
    resman_load_texture("assets/block.png", "block")
    resman_load_texture("assets/block_solid.png", "block_solid")
    resman_load_texture("assets/paddle.png", "paddle")
    resman_load_texture("assets/awesomeface.png", "ball")
    resman_load_texture("assets/particle.png", "particle")
    resman_load_texture("assets/powerup_chaos.png", "chaos")
    resman_load_texture("assets/powerup_confuse.png", "confuse")
    resman_load_texture("assets/powerup_increase.png", "size")
    resman_load_texture("assets/powerup_passthrough.png", "passthrough")
    resman_load_texture("assets/powerup_speed.png", "speed")
    resman_load_texture("assets/powerup_sticky.png", "sticky")
    log.info("Finished loading textures")

    result := ma.engine_init(nil, &g.audio_engine)
    if result != ma.result.SUCCESS {
        log.error("Failed to initialize audio engine")
    }

    resman_load_sound("assets/music.mp3", "music")
    resman_load_sound("assets/bleep.mp3", "hit-nonsolid")
    resman_load_sound("assets/solid.wav", "hit-solid")
    resman_load_sound("assets/powerup.wav", "get-powerup")
    resman_load_sound("assets/bleep.wav", "hit-paddle")

    one, two, three, four: Game_Level
    game_level_load(&one, "assets/one.lvl", u32(g.width), u32(g.height) / 2)
    game_level_load(&two, "assets/two.lvl", u32(g.width), u32(g.height) / 2)
    game_level_load(&three, "assets/three.lvl", u32(g.width), u32(g.height) / 2)
    game_level_load(&four, "assets/four.lvl", u32(g.width), u32(g.height) / 2)
    append(&g.levels, one)
    append(&g.levels, two)
    append(&g.levels, three)
    append(&g.levels, four)
    g.level = 0

	player: Entity
    player_pos := Vec2{ (f32(g.width) / 2) - (PLAYER_SIZE.x / 2), f32(g.height) - PLAYER_SIZE.y}
	entity_init(entity = &player, position = player_pos, size = PLAYER_SIZE, texture_name = "paddle")
	g.player = player

    ball_pos := player_pos + Vec2{f32(PLAYER_SIZE.x) / 2 - BALL_RADIUS, -BALL_RADIUS * 2}
    g.ball = ball_object_make(ball_pos, BALL_RADIUS, BALL_INITIAL_VELOCITY)

    play_sound("music")

    log.info("## END Game Init###")
}

@export
game_frame :: proc() {
	dt := f32(sapp.frame_duration())
    update(dt)
    render(dt)
	free_all(context.temp_allocator)
}

update :: proc(dt: f32) {
    process_input(dt)

    ball_move(dt, g.width)
    game_do_collisions()
    particle_generator_update(&g.ball_pg, dt, g.ball, 2, {g.ball.radius / 2, g.ball.radius / 2})
    powerups_update(dt)

    if g.post_processor.shake_time > 0 {
        g.post_processor.shake_time -= dt
        if g.post_processor.shake_time <= 0 {
            g.post_processor.shake = false
        }
    }
    if g.ball.position.y >= f32(g.height) {
        g.lives -= 1
        if g.lives == 0 {
            game_reset_level()
            g.state = .Menu
        }
        reset_player()
    }

    if g.state == .Active && game_is_completed(g.levels[g.level]) {
        game_reset_level()
        reset_player()
        // effects.chaos = true
        g.state = .Win
    }
}

render :: proc(dt: f32) {
    if g.state == .Active {
        // Render scene to MSAA fb
        pass_action := sg.Pass_Action {
            colors = {
                0 = { load_action = .CLEAR, clear_value = { 0.1, 0.1, 0.1, 1 } },
            }
        }
        
        // render pass with MSAA attachments
        sg.begin_pass({
            action = pass_action,
            attachments = g.post_processor.msaa_attachments,
        })

        // render as normal
        sg.apply_pipeline(g.sprite_pip)
        draw_sprite({0,0}, {f32(g.width), f32(g.height)}, 0, "background")
        game_level_draw(&g.levels[g.level])
        entity_draw(g.player)
        for p in g.powerups {
            if !p.destroyed {
                game_object_draw(p)
            }
        }
        game_object_draw(g.ball.game_object)

        sg.apply_pipeline(g.particle_pip)
        particle_generator_draw(g.ball_pg)

        // automatically resolves MSAA to resolve_color_img
        sg.end_pass()

        // render postprocessed fullscreen quad to swapchain
        sg.begin_pass({
            action = {},
            swapchain = sglue.swapchain(),
        })

        sg.apply_pipeline(g.post_processor.pip)
        sg.apply_bindings(g.post_processor.bind)

        // update and apply uniforms
        post_processor_apply_uniforms(&g.post_processor, dt)

        sg.draw(0, 4, 1)
        sg.end_pass()

    } else {
        pass_action := sg.Pass_Action {
            colors = {
                0 = { load_action = .CLEAR, clear_value = { 0.5, 0.2, 0.5, 1 } },
            },
        }

        sg.begin_pass({ action = pass_action, swapchain = sglue.swapchain() })
        // Sprites
        sg.apply_pipeline(g.sprite_pip)
        draw_sprite({0,0}, {f32(g.width), f32(g.height)}, 0, "background")
        game_level_draw(&g.levels[g.level])
        entity_draw(g.player)
        for p in g.powerups {
            if !p.destroyed {
                game_object_draw(p)
            }
        }
        game_object_draw(g.ball.game_object)

        sg.apply_pipeline(g.particle_pip)
        particle_generator_draw(g.ball_pg)
        sg.end_pass()
    }
    sg.commit()


    // TODO: render text 

    // gl.Viewport(game.viewport_x, game.viewport_y, game.viewport_width, game.viewport_height)
    // lives := fmt.tprintf("Lives:%v", game.lives)
    // text_renderer_render_text(&text_renderer, lives, 5.0, 5.0, 1.0)
    //
    // if game.state == .Menu {
    //     text_renderer_render_text(&text_renderer, "Press ENTER to start", 320, LOGICAL_H / 2 + 20, 1)
    //     text_renderer_render_text(&text_renderer, "Press W or S to select level", 325, LOGICAL_H / 2 + 45, 0.75)
    // }
    //
    // if game.state == .Win {
    //     text_renderer_render_text(&text_renderer, "You WON!!!", 320, LOGICAL_H / 2 + 20, 1.2, {0,1,0})
    //     text_renderer_render_text(&text_renderer, "Press ENTER to retry or ESC to quit", 200, LOGICAL_H / 2+ 60, 1.2, {1,1,0})
    //
    // }
}

// 2D
// rotation in degrees
compute_sprite_mvp :: proc(position: Vec2 = {0,0}, size: Vec2 = {10,10}, rotation: f32 = 0) -> Mat4 {
	proj := compute_projection()
    model := linalg.matrix4_scale(Vec3{size.x, size.y, 1})
    model = linalg.matrix4_translate(Vec3{-0.5 * size.x, -0.5 * size.y, 0}) * model
    model = linalg.matrix4_rotate(to_radians(rotation), Vec3{0,0,1}) * model
    model = linalg.matrix4_translate(Vec3{0.5 * size.x, 0.5 * size.y, 0}) * model
    model = linalg.matrix4_translate(Vec3{position.x, position.y, 0}) * model
	return proj * model
}

compute_projection :: proc() -> matrix[4,4]f32 {
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
}

process_input :: proc(dt: f32) {
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
        if g.keys[.R] {
				// win state
				reset_player()
				game_reset_level()
				// effects.chaos = true
				// g.state = .Win
                g.state = .Active
        }
        g.player.position.x = clamp(g.player.position.x, 0, f32(g.width) - g.player.size.x)
    }
    // if game.state == .Menu {
    //     if game.keys[glfw.KEY_ENTER] && !game.keys_processed[glfw.KEY_ENTER]{
    //         game.keys_processed[glfw.KEY_ENTER] = true
    //         game.state = .Active
    //     }
    //     if game.keys[glfw.KEY_W] && !game.keys_processed[glfw.KEY_W] {
    //         game.keys_processed[glfw.KEY_W] = true
    //         game.level = (game.level + 1) % 4
    //     }
    //     if game.keys[glfw.KEY_S] && !game.keys_processed[glfw.KEY_S] {
    //         game.keys_processed[glfw.KEY_S] = true
    //         game.level = (game.level - 1) % 4
    //     }
    // }
    // if g.state == .Win {
    //     if g.keys[glfw.KEY_ENTER] {
    //         // g.keys_processed[glfw.KEY_ENTER] = true // NOTE: is this needed?
    //         effects.chaos = false
    //         g.state = .Menu
    //     }
    // }

}

@export
game_cleanup :: proc() {
	sg.shutdown()
	sg.destroy_buffer(g.sprite_bind.vertex_buffers[0])
	sg.destroy_pipeline(g.sprite_pip)
	sg.destroy_buffer(g.particle_bind.vertex_buffers[0])
	sg.destroy_pipeline(g.particle_pip)

    sg.destroy_image(g.post_processor.msaa_color_img)
    sg.destroy_image(g.post_processor.msaa_depth_img)
    sg.destroy_image(g.post_processor.resolve_color_img)
    sg.destroy_attachments(g.post_processor.msaa_attachments)
    sg.destroy_buffer(g.post_processor.bind.vertex_buffers[0])
    sg.destroy_pipeline(g.post_processor.pip)

    delete(g.resman.textures)

    for key, &val in g.resman.sounds {
        ma.sound_uninit(val)
    }

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

reset_player :: proc() {
    g.player.size = PLAYER_SIZE
    g.player.position = Vec2{f32(g.width) / 2 - (g.player.size.x / 2), f32(g.height) - PLAYER_SIZE.y}
    ball_reset(g.player.position + Vec2{PLAYER_SIZE.x / 2 - BALL_RADIUS, -(BALL_RADIUS * 2)}, BALL_INITIAL_VELOCITY)
    // effects.chaos = false
    // effects.confuse = false
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
    file := fmt.ctprintf("%v", file)
    width, height, n_channels: i32
    pixels := stbi.load(file, &width, &height, &n_channels, 4)
    if pixels == nil {
        log.error("Failed to load image")
        return nil, 0, 0, 0
    }
    return pixels, width, height, n_channels

}

resman_init :: proc() {
    g.resman.textures = make(map[string]sg.Image)
    g.resman.sounds = make(map[string]^ma.sound)
}

resman_load_texture :: proc(path: string, name: string) -> sg.Image {
    pixels, width, height, _ := read_image_from_file(path)
    if pixels == nil {
        log.error("Failed to load texture:", path)
        return {}
    }
    defer stbi.image_free(pixels)

    img := sg.make_image({
        width = i32(width),
        height = i32(height),
        pixel_format = .RGBA8,
        data = {
            subimage = {
                0 = {
                    0 = { ptr = pixels, size = uint(width * height * 4) }, // always 4 bytes per pixel
                },
            },
        },
        label = strings.clone_to_cstring(name),
    })
    if sg.query_image_state(img) != .VALID {
        log.error("Failed to create image for:", name)
        return {}
    }

    g.resman.textures[name] = img
    log.info("Loaded texture:", name, "size:", width ,"x", height)
    return img
}

resman_get_texture :: proc(name: string) -> (sg.Image, bool) {
    return g.resman.textures[name]
}

draw_sprite :: proc(position: Vec2, size: Vec2 = {10,10}, rotation: f32 = 0, texture_name: string = "", color: Vec3 = {1,1,1}) {
    // 1. Compute transformation matrix and combine with projection
    mvp := compute_sprite_mvp(position, size, rotation)

    // 2. Prepare shader uniforms
	sprite_vs_params := Sprite_Vs_Params {
		mvp = mvp
	}
	sprite_fs_params := Sprite_Fs_Params {
		sprite_color = color
	}

    // TODO: bind texture
    if tex, exists := resman_get_texture(texture_name); exists {
        g.sprite_bind.images[IMG_tex] = tex
    } else {
        g.sprite_bind.images[IMG_tex], _ = resman_get_texture("white")
    }

    // 4. Issue draw commands
    sg.apply_bindings(g.sprite_bind)
	sg.apply_uniforms(UB_sprite_vs_params, { ptr = &sprite_vs_params, size = size_of(sprite_vs_params) })
	sg.apply_uniforms(UB_sprite_fs_params, { ptr = &sprite_fs_params, size = size_of(sprite_fs_params) })
    sg.draw(0, 6, 1)
}

entity_draw :: proc(entity: Entity) {
    if entity.texture_name != "" {
        draw_sprite(
            entity.position,
            entity.size,
            entity.rotation,
            entity.texture_name,
            entity.color,
        )
    }
}

// TODO: expose dependencies: bind, pip, resman, shader. consolidate into a "renderer" data object
sprite_renderer_init :: proc() {
    log.info("Initializing sprite renderer...")
    // 1. Create the quad geometry (same as OpenGL version)
    vertices := [?]Vertex {
        {0, 1, 0, 1},  // bottom-left
        {1, 0, 1, 0},  // top-right  
        {0, 0, 0, 0},  // top-left

        {0, 1, 0, 1},  // bottom-left
        {1, 1, 1, 1},  // bottom-right
        {1, 0, 1, 0},  // top-right
    }

    // 2. Create vertex buffer
    g.sprite_bind.vertex_buffers[0] = sg.make_buffer({
        data = { ptr = &vertices, size = size_of(vertices) },
        label = "sprite-vertices",
    })
    if sg.query_buffer_state(g.sprite_bind.vertex_buffers[0]) != .VALID {
        log.error("Failed to create vertex buffer")
        return
    }
    log.info("Created vertex buffer")

    // 3. Create a default white texture for solid colors
    // TODO: make independent, used by both sprites and particles
    white_pixels := [4]u8{255, 255, 255, 255}  // RGBA white
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
    // TODO: resman_set_texture
    g.resman.textures["white"] = white_texture
    log.info("Created white texture")

    // 4. Set up default bindings
    g.sprite_bind.images[IMG_tex] = g.resman.textures["white"]

    g.sprite_bind.samplers[SMP_smp] = sg.make_sampler({
        label = "sprite-sampler",
    })
    if sg.query_sampler_state(g.sprite_bind.samplers[SMP_smp]) != .VALID {
        log.error("Failed to create sampler")
        return
    }
    log.info("Created sampler")

    // 6. Create shader
    shader := sg.make_shader(sprite_shader_desc(sg.query_backend()))
    if sg.query_shader_state(shader) != .VALID {
        log.error("Failed to create shader")
        return
    }
    log.info("Created shader")

    // 6. Create the rendering pipeline
    g.sprite_pip = sg.make_pipeline({
        shader = shader,
		layout = {
			attrs = {
				ATTR_sprite_pos = { format = .FLOAT2 },
				ATTR_sprite_texcoord0 = { format = .FLOAT2 },
			}
		},
        colors = {
            0 = {
                blend = {
                    enabled = true,
                    src_factor_rgb = .SRC_ALPHA,
                    dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
                    src_factor_alpha = .ONE,
                    dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
                }
            }
        },
        label = "sprite-pipeline",
    })
    if sg.query_pipeline_state(g.sprite_pip) != .VALID {
        log.error("Failed to create pipeline")
        return
    }
    log.info("Created pipeline")
    log.info("Done initializing sprite renderer")
}

game_is_completed :: proc(level: Game_Level) -> bool {
    for tile in level.bricks {
        if !tile.is_solid && !tile.destroyed {
            return false
        }
    }
    return true
}


ball_move :: proc(dt: f32, window_width: u32) {
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

ball_reset :: proc(position: Vec2, velocity: Vec2) {
    g.ball.position = position
    g.ball.velocity = velocity
    g.ball.stuck = true
    g.ball.sticky = false
    g.ball.passthrough = false
}

check_collision :: proc(a: Entity, b: Entity) -> bool {
    return a.position.x + a.size.x >= b.position.x &&
           b.position.x + b.size.x >= a.position.x &&
           a.position.y + a.size.y >= b.position.y &&
           b.position.y + b.size.y >= a.position.y
}

check_ball_box_collision :: proc(ball: Ball_Object, box: Entity) -> Collision_Data {
    ball_center := ball.position + ball.radius
    half_extents := Vec2{box.size.x / 2, box.size.y / 2}
    box_center := Vec2{box.position.x + half_extents.x, box.position.y + half_extents.y}
    d := ball_center - box_center
    clamped: Vec2
    clamped.x = clamp(d.x, -half_extents.x, half_extents.x)
    clamped.y = clamp(d.y, -half_extents.y, half_extents.y)
    closest := box_center + clamped
    d = closest - ball_center
    if linalg.length(d) < ball.radius {
        return {
            collided = true,
            direction = vector_direction(d),
            difference_vector = d,
        }
    } else {
        return {
            collided = false,
            direction = .Up,
            difference_vector = {},
        }
    }

}

game_do_collisions :: proc() {
    for &box in g.levels[g.level].bricks {
        if !box.destroyed {
            collision := check_ball_box_collision(g.ball, box)
            if collision.collided {
                if !box.is_solid {
                    box.destroyed = true
                    powerups_spawn(box)
                    play_sound("hit-nonsolid")
                } else {
                    g.post_processor.shake_time = 0.1
                    g.post_processor.shake = true
                    play_sound("hit-solid")
                }
                if !(g.ball.passthrough && !box.is_solid) {
                    dir := collision.direction
                    diff_vector := collision.difference_vector
                    if dir == .Left || dir == .Right {
                        g.ball.velocity.x *= -1
                        penetration := g.ball.radius - abs(diff_vector.x)
                        if dir == .Left {
                            g.ball.position.x += penetration
                        } else {
                            g.ball.position.x -= penetration
                        }
                    } else {
                        g.ball.velocity.y *= -1
                        penetration := g.ball.radius - abs(diff_vector.y)
                        if dir == .Up {
                            g.ball.position.y -= penetration
                        } else {
                            g.ball.position.y += penetration
                        }

                    }
                }
            }
        }
    }
    for &p in g.powerups {
        if !p.destroyed {
            if p.position.y >= f32(g.height) {
                p.destroyed = true
            }
            if check_collision(g.player, p) {
                powerup_activate(&p)
                p.destroyed = true
                play_sound("get-powerup")
            }
        }
    }

    collision := check_ball_box_collision(g.ball, g.player)
    if !g.ball.stuck && collision.collided {
        center_board := g.player.position.x + (g.player.size.x / 2)
        distance := g.ball.position.x + g.ball.radius - center_board
        pct := distance / (g.player.size.x / 2)
        strength :f32= 2
        speed := linalg.length(g.ball.velocity)
        g.ball.velocity.x = BALL_INITIAL_VELOCITY.x * pct * strength
        g.ball.velocity.y = -1 * abs(g.ball.velocity.y)
        g.ball.velocity = linalg.normalize0(g.ball.velocity) * speed
        g.ball.stuck = g.ball.sticky
        play_sound("hit-paddle")
    }
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
        trimmed := strings.trim_space(row)
        if len(trimmed) == 0 do continue

        chars, _ := strings.split(trimmed, " ")
        defer delete(chars)

        row_codes: [dynamic]Tile_Code
        for char, x in chars {
            trimmed := strings.trim_space(char)
            if len(char) == 0 do continue

            val, ok := strconv.parse_int(char)
            if !ok {
                log.error("Failed to parse int from tile_code:", char, "pos:", y, x)
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
                obj: Entity
                entity_init(&obj, pos, size, color, {}, "block_solid")
                obj.is_solid = true
                append(&game_level.bricks, obj)
            case .Brick_A:
                color = {.2,.6,1}
                obj: Entity
                entity_init(&obj, pos, size, color, {}, "block")
                append(&game_level.bricks, obj)
            case .Brick_B:
                color = {.0,.7,.0}
                obj: Entity
                entity_init(&obj, pos, size, color, {}, "block")
                append(&game_level.bricks, obj)
            case .Brick_C:
                color = {.8,.8,.4}
                obj: Entity
                entity_init(&obj, pos, size, color, {}, "block")
                append(&game_level.bricks, obj)
            case .Brick_D:
                color = {1.,.5,.0}
                obj: Entity
                entity_init(&obj, pos, size, color, {}, "block")
                append(&game_level.bricks, obj)
            }
        }
    }
}

game_level_draw :: proc(game_level: ^Game_Level) {
    for tile in game_level.bricks {
        if !tile.destroyed {
            game_object_draw(tile)
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
    g.lives = 3
}

read_file_to_string :: proc(path: string) -> string {
	data, ok := os.read_entire_file_from_filename(path)
	if !ok {
		log.error("Failed to read file")
		os.exit(-1)
	}

	return string(data)
}

game_object_draw :: proc(obj: Entity) {
    draw_sprite(obj.position, obj.size, obj.rotation, obj.texture_name, obj.color)
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


// TODO: letterboxing
// update_viewport_and_projection :: proc(screen_width: u32, screen_height: u32) {
//     game.screen_width = screen_width
//     game.screen_height = screen_height
//
//     target_aspect := f32(LOGICAL_W) / f32(LOGICAL_H)
//     screen_aspect := f32(screen_width) / f32(screen_height)
//
//     if screen_aspect > target_aspect {
//         // Screen is wider than target - letterbox on sides
//         game.viewport_height = i32(screen_height)
//         game.viewport_width = i32(f32(screen_height) * target_aspect)
//         game.viewport_x = (i32(screen_width) - game.viewport_width) / 2
//         game.viewport_y = 0
//     } else {
//         // Screen is taller than target - letterbox on top/bottom
//         game.viewport_width = i32(screen_width)
//         game.viewport_height = i32(f32(screen_width) / target_aspect)
//         game.viewport_x = 0
//         game.viewport_y = (i32(screen_height) - game.viewport_height) / 2
//     }
//
//     projection := linalg.matrix_ortho3d_f32(0, f32(game.width), f32(game.height), 0, -1, 1)
//
//     sprite_shader := resman_get_shader("sprite")
//     shader_use(sprite_shader)
//     shader_set_mat4(sprite_shader, "projection", &projection)
//
//     particle_shader := resman_get_shader("particle")
//     shader_use(particle_shader)
//     shader_set_mat4(particle_shader, "projection", &projection)
//
//     text_shader := resman_get_shader("text")
//     shader_use(text_shader)
//     shader_set_mat4(text_shader, "projection", &projection)
//
//     gl.Viewport(game.viewport_x, game.viewport_y, game.viewport_width, game.viewport_height)
// }

ball_object_make :: proc(pos: Vec2, radius: f32 = 12.5, velocity: Vec2) -> Ball_Object {
    obj: Entity
    entity_init(&obj, pos, Vec2{ radius * 2, radius * 2}, Vec3{1,1,1}, velocity, "ball")
    return Ball_Object{
        game_object = obj,
        stuck = true,
        radius = radius,
    }
}

particle_generator_init :: proc(pg: ^Particle_Generator) {
    // 1. Create the quad geometry (same as OpenGL version)
    particle_quad := [?]f32 {
        0.0, 1.0, 0.0, 1.0,
        1.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 0.0,

        0.0, 1.0, 0.0, 1.0,
        1.0, 1.0, 1.0, 1.0,
        1.0, 0.0, 1.0, 0.0
    }

    // 2. Create vertex buffer
    g.particle_bind.vertex_buffers[0] = sg.make_buffer({
      data = { ptr = &particle_quad, size = size_of(particle_quad) },
      label = "particle-vertices",
    })
    if sg.query_buffer_state(g.particle_bind.vertex_buffers[0]) != .VALID {
      log.error("Failed to create particles vertex buffer")
      return
    }
    log.info("Created particle vertex buffer")

    // 4. Set up default bindings
        g.particle_bind.images[IMG_particle_tex] = g.resman.textures["white"]

    g.particle_bind.samplers[SMP_particle_smp] = sg.make_sampler({
      label = "particle-sampler",
    })
    if sg.query_sampler_state(g.particle_bind.samplers[SMP_particle_smp]) != .VALID {
      log.error("Failed to create particle sampler")
      return
    }
    log.info("Created particle sampler")

    // 6. Create shader
    shader := sg.make_shader(particle_shader_desc(sg.query_backend()))
    if sg.query_shader_state(shader) != .VALID {
      log.error("Failed to create particle shader")
      return
    }
    log.info("Created particle shader")


    // 6. Create the rendering pipeline
    g.particle_pip = sg.make_pipeline({
        shader = shader,
        layout = {
            attrs = {
                    ATTR_particle_vertex = { format = .FLOAT4 },
            }
        },
        colors = {
              0 = {
                  blend = {
                      enabled = true,
                      src_factor_rgb = .SRC_ALPHA,
                      dst_factor_rgb = .ONE,
                      src_factor_alpha = .SRC_ALPHA,
                      dst_factor_alpha = .ONE,
                  }
              }
        },
        label = "particle-pipeline",
    })
    if sg.query_pipeline_state(g.particle_pip) != .VALID {
      log.error("Failed to create particle pipeline")
      return
    }
    log.info("Created particle pipeline")
    log.info("Done initializing particle renderer")

    particles: sa.Small_Array(MAX_PARTICLES, Particle)
    particle := particle_make()
    for i in 0..<MAX_PARTICLES {
        sa.push(&particles, particle)
    }
    pg^ = Particle_Generator {
        particles = particles,
        max_particles = MAX_PARTICLES,
    }

}

particle_generator_update :: proc(pg: ^Particle_Generator, dt: f32, object: Entity, n_new_particles: int, offset: Vec2 = {0,0}) {
    // continuously generate particles
    n_new_particles := 2
    for i in 0..<n_new_particles {
        unused_particle := particle_generator_first_unused_particle(pg)
        particle_generator_respawn_particle(pg, sa.get_ptr(&pg.particles, unused_particle), object, offset)
    }

    for &p in sa.slice(&pg.particles) {
        p.life -= dt
        if p.life > 0 {
            p.position -= p.velocity * dt
            p.color.a -= dt * 2.5
        }
    }
}

particle_generator_first_unused_particle :: proc(pg: ^Particle_Generator) -> int {
    for i in pg.last_used_particle..<sa.len(pg.particles) {
        if sa.get(pg.particles, i).life <= 0 {
            pg.last_used_particle = i
            return i
        }
    }
    for i in 0..<pg.last_used_particle {
        if sa.get(pg.particles, i).life <= 0 {
            pg.last_used_particle = i
            return i
        }
    }
    pg.last_used_particle = 0
    return 0
}

particle_generator_respawn_particle :: proc(pg: ^Particle_Generator, particle: ^Particle, object: Entity, offset: Vec2 = {0,0}) {
    rgn := rand.float32_range(-5, 5)
    particle.position = object.position + rgn + offset

    random_color := rand.float32_range(0.5, 1.0)
    particle.color = {random_color, random_color, random_color, 1.0}

    particle.life = 1
    particle.velocity = object.velocity * 0.1
}

// TODO: set blend functions
particle_generator_draw :: proc(pg: Particle_Generator) {
    // gl.BlendFunc(gl.SRC_ALPHA, gl.ONE)
    projection := compute_projection()
    for i in 0..<sa.len(pg.particles) {
        p := sa.get(pg.particles, i)
        if p.life > 0 {
            particle_vs_params := Particle_Vs_Params {
                projection = projection,
                offset = p.position,
                color = p.color,
            }

            if texture, exists := resman_get_texture("particle"); exists {
                g.particle_bind.images[IMG_particle_tex] = texture
            } 

            // TODO: should specify bind.vertex_buffers[1]??
            sg.apply_bindings(g.particle_bind)
            sg.apply_uniforms(UB_particle_vs_params, { ptr = &particle_vs_params, size = size_of(particle_vs_params) })
            sg.draw(0, 6, 1)
        }
    }
    // gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
}

particle_make :: proc() -> Particle {
    return {
        color = {1,1,1,1}
    }
}

post_processor_init :: proc(pp: ^Post_Processor, width, height: i32) {
    pp.width = width
    pp.height = height

    // ms color attach
    pp.msaa_color_img = sg.make_image({
        usage = {
            render_attachment = true,
        },
        width = width,
        height = height,
        pixel_format = .RGBA8,
        sample_count = 4, // 4x MSAA
        label = "msaa-color",
    })

    // resolve target (receive msaa resolved image)
    pp.resolve_color_img = sg.make_image({
        usage = {
            render_attachment = true,
        },
        width = width,
        height = height,
        pixel_format = .RGBA8,
        sample_count = 1,
        label = "resolve-color",
    })

    pp.msaa_depth_img = sg.make_image({
        usage = {
            render_attachment = true,
        },
        width = width,
        height = height,
        pixel_format = .DEPTH_STENCIL,
        sample_count = 4, // 4x MSAA
        label = "msaa-depth",

    })

    // attachments obj with msaa resolve
    pp.msaa_attachments = sg.make_attachments({
        colors = {
            0 = { image = pp.msaa_color_img },
        },
        resolves = {
            0 = { image = pp.resolve_color_img }, // triggers msaa resolve
        },
        depth_stencil = { image = pp.msaa_depth_img },
        label = "msaa-attachments",
    })

    // quad
    vertices := [?]f32{
        // pos      // tex
        -1, -1,     0, 0,
         1, -1,     1, 0,
        -1,  1,     0, 1,
         1,  1,     1, 1,
    }

    pp.bind.vertex_buffers[0] = sg.make_buffer({
        data = { ptr = &vertices, size = size_of(vertices) },
        label = "post-vertices",
    })

    pp.bind.images[IMG_scene_tex] = pp.resolve_color_img
    pp.bind.samplers[SMP_scene_smp] = sg.make_sampler({
        wrap_u = .REPEAT,
        wrap_v = .REPEAT,
        label = "post-sampler",
    })

    shader := sg.make_shader(postprocess_shader_desc(sg.query_backend()))

    pp.pip = sg.make_pipeline({
        shader = shader,
        layout = {
            attrs = {
                ATTR_postprocess_vertex = { format = .FLOAT4 }
            },
        },
        primitive_type = .TRIANGLE_STRIP,
        label = "post-pipeline",
    })

    pp.fs_params = init_postprocess_params()
}


init_postprocess_params :: proc() -> Postprocess_Fs_Params {
    params: Postprocess_Fs_Params

    offset: f32 = 1.0 / 300.0
        params.offsets = {
        {-offset,  offset, 0, 0},  // top-left
        { 0.0,     offset, 0, 0},  // top-center
        { offset,  offset, 0, 0},  // top-right
        {-offset,  0.0, 0, 0},     // center-left
        { 0.0,     0.0, 0, 0},     // center-center
        { offset,  0.0, 0, 0},     // center-right
        {-offset, -offset, 0, 0},  // bottom-left
        { 0.0,    -offset, 0, 0},  // bottom-center
        { offset, -offset, 0, 0},  // bottom-right
    }

    // Edge detection kernel
    params.edge_kernel = {
        {-1, -1, -1, 0},
        {-1,  8, -1, 0},
        {-1, -1, -1, 0},
    }

    // Blur kernel (normalized)
    params.blur_kernel = {
        {1.0/16, 2.0/16, 1.0/16, 0},
        {2.0/16, 4.0/16, 2.0/16, 0},
        {1.0/16, 2.0/16, 1.0/16, 0},
    }

    return params
}

post_processor_apply_uniforms :: proc(pp: ^Post_Processor, dt: f32) {
    vs_params := Postprocess_Vs_Params{
        time = f32(sapp.frame_count()) * dt,
        chaos = i32(pp.chaos),
        confuse = i32(pp.confuse),
        shake = i32(pp.shake),
    }
    sg.apply_uniforms(UB_postprocess_vs_params, {
        ptr = &vs_params,
        size = size_of(vs_params)
    })

    // frag shader unforms (with cached params)
    pp.fs_params.chaos = i32(pp.chaos)
    pp.fs_params.confuse = i32(pp.chaos)
    pp.fs_params.shake = i32(pp.shake)
    sg.apply_uniforms(UB_postprocess_fs_params, {
        ptr = &pp.fs_params,
        size = size_of(pp.fs_params),
    })
}

powerup_make :: proc(type: Powerup_Type, color: Vec3, duration: f32, position: Vec2, texture_name: string) -> Powerup_Object {
    o: Entity
    entity_init(
        &o, 
        position = position, 
        size = POWERUP_SIZE, 
        color = color, 
        velocity = POWERUP_VELOCITY,
        texture_name = texture_name
    )
    return {
        position = o.position,
        size = o.size, 
        velocity = o.velocity,
        color = o.color,
        rotation = o.rotation,
        is_solid = o.is_solid,
        destroyed = o.destroyed,
        texture_name = o.texture_name,

        type = type,
        duration = duration,
        activated = false,
    }
}

should_spawn :: proc(chance: u32) -> bool {
    chance := 1 / f32(chance)
    rgn := rand.float32()
    return rgn < chance
}

powerups_spawn :: proc(block: Entity) {
    if should_spawn(75) { // 1 in 75 chance
        p := powerup_make(.Speed, {0.5,0.5,1.0}, 0, block.position, "speed")
        append(&g.powerups, p)
    }
    if should_spawn(75) {
        p := powerup_make(.Sticky, {1,0.5,1.0}, 5, block.position, "sticky")
        append(&g.powerups, p)
    }
    if should_spawn(75) {
        p := powerup_make(.Passthrough, {0.5,1.0,0.5}, 10, block.position, "passthrough")
        append(&g.powerups, p)
    }
    if should_spawn(75) {
        p := powerup_make(.Padsize_Increase, {1.0,0.6,0.4}, 0, block.position, "size")
        append(&g.powerups, p)
    }
    if should_spawn(15) {
        p := powerup_make(.Confuse, {1.0,0.3,0.3}, 15, block.position, "confuse")
        append(&g.powerups, p)
    }
    if should_spawn(15) {
        p := powerup_make(.Chaos, {0.9,0.25,0.25}, 15, block.position, "chaos")
        append(&g.powerups, p)
    }
}

powerup_activate :: proc(p: ^Powerup_Object) {
    p.activated = true
    switch p.type {
    case .Speed:
        g.ball.velocity *= 1.2
    case .Sticky:
        g.ball.sticky = true
        g.player.color = {1,0.5,1}
    case .Passthrough:
        g.ball.passthrough = true
        g.ball.color = {1,0.5,0.5}
    case .Padsize_Increase:
        g.player.size.x += 50
    case .Confuse:
        if !g.post_processor.chaos {
            g.post_processor.confuse = true
        }
    case .Chaos:
        if !g.post_processor.confuse {
            g.post_processor.chaos = true
        }
    }
}

powerups_update :: proc(dt: f32) {
    for &p in g.powerups {
        p.position += p.velocity * dt

        if p.activated {
            p.duration -= dt

            if p.duration <= 0 {
                p.activated = false

                if p.type == .Sticky {
                    if !is_other_powerup_active(.Sticky) {
                        g.ball.sticky = false
                        g.player.color = {1,1,1}
                    }
                } else if p.type == .Passthrough {
                    if !is_other_powerup_active(.Passthrough) {
                        g.ball.passthrough = false
                        g.ball.color = {1,1,1}
                    }
                } else if p.type == .Confuse {
                    if !is_other_powerup_active(.Confuse) {
                        g.post_processor.confuse = false
                    }
                } else if p.type == .Chaos {
                    if !is_other_powerup_active(.Chaos) {
                        g.post_processor.chaos = false
                    }
                }
            }
        }
    }
    indices_to_remove: [dynamic]int
    defer delete(indices_to_remove)
    for p, i in g.powerups {
        if p.destroyed && !p.activated {
            append(&indices_to_remove, i)
        }
    }
    for idx in indices_to_remove {
        unordered_remove(&g.powerups, idx)
    }
}

is_other_powerup_active :: proc(type: Powerup_Type) -> bool {
    for p in g.powerups {
        if p.activated && p.type == type {
            return true
        }
    }
    return false
}

resman_load_sound :: proc(file: string, name: string) -> ^ma.sound {
    sound := new(ma.sound)

    file_cstring := strings.clone_to_cstring(file)
    result := ma.sound_init_from_file(&g.audio_engine, file_cstring, nil, nil, nil, sound)
    delete(file_cstring)

    if result != ma.result.SUCCESS {
        log.error("Failed to load sound:", file)
        free(sound)
        return nil
    } 

    log.info("Load sound, file:", file, "name:", name)
    g.resman.sounds[name] = sound
    return g.resman.sounds[name]
}

play_sound :: proc(name: string, loop: b32 = false) {
    if sound, exists := g.resman.sounds[name]; exists {
        ma.sound_set_looping(sound, loop)
        ma.sound_seek_to_pcm_frame(sound, 0)
        ma.sound_start(sound)
    } else {
        log.error("Failed to play sound:", name)
    }
}

resman_get_sound :: proc(name: string) -> ^ma.sound {
    sound, exists := g.resman.sounds[name]; 
    if !exists do log.error("Failed to get sound:", name)
    return sound
}
