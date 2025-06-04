package game

import "core:math/linalg"
import "core:image/png"
import "core:log"
import "core:slice"
import "core:fmt"
import "core:strings"
import stbi "vendor:stb/image"
import sapp "sokol/app"
import sg "sokol/gfx"
import sglue "sokol/glue"
import slog "sokol/log"

pr :: fmt.println
to_radians :: linalg.to_radians

LOGICAL_W :: 1920
LOGICAL_H :: 1080

PLAYER_SIZE :: Vec2{100, 20}
PLAYER_VELOCITY :: 1000

BALL_RADIUS :: 12.5
BALL_INITIAL_VELOCITY :: Vec2{100, -350}

MAX_PARTICLES :: 500

Vec2 :: [2]f32
Vec2i :: [2]i32
Vec3 :: [3]f32
Vec4 :: [4]f32
Mat4 :: matrix[4,4]f32

Game_Memory :: struct {
	pip: sg.Pipeline,
	bind: sg.Bindings,

	width: u32,
	height: u32,
	state: Game_State,
	keys: #sparse [sapp.Keycode]bool,
	keys_processed: #sparse [sapp.Keycode]bool,

	player: Entity,
    resman: ^Resource_Manager
}

Game_State :: enum {
	Menu,
	Active,
	Win,
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

Entity :: struct {
    position: Vec2,
    size: Vec2, 
    velocity: Vec2,
	color: Vec3,
	rotation: f32,
	is_solid: bool,
    destroyed: bool,
	sprite: Texture2D,
    texture_name: string,
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
    // sounds: map[string]^ma.sound,
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

    g.resman = new(Resource_Manager)
    resman_init()
    log.info("Initialized resource manager")

    sprite_renderer_init()
    log.info("Initialized sprite renderer")

    resman_load_texture("assets/background.jpg", "background")
    resman_load_texture("assets/awesomeface.png", "face")
    resman_load_texture("assets/block.png", "block")
    resman_load_texture("assets/block_solid.png", "block_solid")
    resman_load_texture("assets/paddle.png", "paddle")
    resman_load_texture("assets/particle.png", "particle")
    resman_load_texture("assets/powerup_chaos.png", "chaos")
    resman_load_texture("assets/powerup_confuse.png", "confuse")
    resman_load_texture("assets/powerup_increase.png", "size")
    resman_load_texture("assets/powerup_passthrough.png", "passthrough")
    resman_load_texture("assets/powerup_speed.png", "speed")
    resman_load_texture("assets/powerup_sticky.png", "sticky")
    log.info("Finished loading textures")

	g.state = .Active
	g.width = LOGICAL_W
	g.height = LOGICAL_H

	player: Entity
    player_pos := Vec2{ (f32(g.width) / 2) - (PLAYER_SIZE.x / 2), f32(g.height) - PLAYER_SIZE.y}
	entity_init(entity = &player, position = player_pos, size = PLAYER_SIZE, texture_name = "paddle")
	g.player = player
    log.info("## END Game Init###")
}

x :f32= 0
@export
game_frame :: proc() {
	dt := f32(sapp.frame_duration())

    process_input(dt)

	pass_action := sg.Pass_Action {
		colors = {
			0 = { load_action = .CLEAR, clear_value = { 0.5, 0.2, 0.5, 1 } },
		},
	}
	sg.begin_pass({ action = pass_action, swapchain = sglue.swapchain() })
        sg.apply_pipeline(g.pip)
        // TODO: draw bg
        entity_draw(g.player)
        // sg.apply_bindings(g.bind)
        // sg.draw(0, 6, 1)

	sg.end_pass()
	sg.commit()

	free_all(context.temp_allocator)
}

// 2D
// rotation in degrees
compute_sprite_mvp :: proc(position: Vec2 = {0,0}, size: Vec2 = {10,10}, rotation: f32 = 0) -> Mat4 {
	proj := linalg.matrix_ortho3d_f32(0, f32(g.width), f32(g.height), 0, -1, 1)
    model := linalg.matrix4_scale(Vec3{size.x, size.y, 1})
    model = linalg.matrix4_translate(Vec3{-0.5 * size.x, -0.5 * size.y, 0}) * model
    model = linalg.matrix4_rotate(to_radians(rotation), Vec3{0,0,1}) * model
    model = linalg.matrix4_translate(Vec3{0.5 * size.x, 0.5 * size.y, 0}) * model
    model = linalg.matrix4_translate(Vec3{position.x, position.y, 0}) * model
	return proj * model
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
					// if g.ball.stuck {
					// 	g.ball.position.x -= dx
					// }
				}
        }
        if g.keys[.D] {
            if g.player.position.x <= f32(g.width) - g.player.size.x {
                g.player.position.x += dx
                // if g.ball.stuck {
                // 	g.ball.position.x += dx
                // }
            }
        }
        if g.keys[.SPACE] {
            // g.ball.stuck = false
        }
        if g.keys[.R] {
				// win state
				reset_player()
				// g.reset_level()
				// effects.chaos = true
				g.state = .Win
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
	sg.destroy_buffer(g.bind.vertex_buffers[0])
	sg.destroy_pipeline(g.pip)
    delete(g.resman.textures)
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
    // ball_reset(game.player.position + Vec2{PLAYER_SIZE.x / 2 - BALL_RADIUS, -(BALL_RADIUS * 2)}, BALL_INITIAL_VELOCITY)
    // effects.chaos = false
    // effects.confuse = false
    // game.ball.passthrough = false
    // game.ball.sticky = false
    // game.ball.color = {1,1,1}
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

draw_sprite :: proc(position: Vec2, size: Vec2 = {10,10}, rotation: f32 = 0, color: Vec3 = {1,1,1}, texture_name: string = "") {
    // 1. Compute transformation matrix and combine with projection
    mvp := compute_sprite_mvp(position, size, rotation)

    // 2. Prepare shader uniforms
	vs_params := Vs_Params {
		mvp = mvp
	}
    // fs_params := Fs_Params{}

    // 3. Setup Bindings
    if texture_name != "" {
        if texture, exists := resman_get_texture(texture_name); exists {
            g.bind.images[IMG_tex] = texture
        } else {
            log.warn("Texture not found:", texture_name)
            g.bind.images[IMG_tex] = g.resman.textures["white"]
        }
    } else {
        g.bind.images[IMG_tex] = g.resman.textures["white"]
    }

    // 4. Issue draw commands
    sg.apply_bindings(g.bind)
	sg.apply_uniforms(UB_vs_params, { ptr = &vs_params, size = size_of(vs_params) })
    sg.draw(0, 6, 1)
}

entity_draw :: proc(entity: Entity) {
    if entity.texture_name != "" {
        draw_sprite(
            entity.position,
            entity.size,
            entity.rotation,
            entity.color,
            entity.texture_name,
        )
    }
}

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
    g.bind.vertex_buffers[0] = sg.make_buffer({
        data = { ptr = &vertices, size = size_of(vertices) },
        label = "sprite-vertices",
    })
    if sg.query_buffer_state(g.bind.vertex_buffers[0]) != .VALID {
        log.error("Failed to create vertex buffer")
        return
    }
    log.info("Created vertex buffer")

    // 3. Create a default white texture for solid colors
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

    g.resman.textures["white"] = white_texture
    log.info("Created white texture")

    // 4. Set up default bindings
    g.bind.images[IMG_tex] = g.resman.textures["white"]

    g.bind.samplers[SMP_smp] = sg.make_sampler({
        label = "sprite-sampler",
    })
    if sg.query_sampler_state(g.bind.samplers[SMP_smp]) != .VALID {
        log.error("Failed to create sampler")
        return
    }
    log.info("Created sampler")

    // 6. Create shader
    shader := sg.make_shader(game_shader_desc(sg.query_backend()))
    if sg.query_shader_state(shader) != .VALID {
        log.error("Failed to create shader")
        return
    }
    log.info("Created shader")

    // 6. Create the rendering pipeline
    g.pip = sg.make_pipeline({
        shader = shader,
		layout = {
			attrs = {
				ATTR_game_pos = { format = .FLOAT2 },
				ATTR_game_texcoord0 = { format = .FLOAT2 },
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
    if sg.query_pipeline_state(g.pip) != .VALID {
        log.error("Failed to create pipeline")
        return
    }
    log.info("Created pipeline")
    log.info("Done initializing sprite renderer")
}
