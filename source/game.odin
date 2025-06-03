package game

import "core:math/linalg"
import "core:image/png"
import "core:log"
import "core:slice"
import "core:fmt"
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
	position, size, velocity: Vec2,
	color: Vec3,
	rotation: f32,
	is_solid, destroyed: bool,
	sprite: Texture2D,
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
	g = new(Game_Memory)
	game_hot_reloaded(g)

	sg.setup({
		environment = sglue.environment(),
		logger = { func = slog.func },
	})

	vertices := [?]Vertex {
        {0, 1, 0, 1},
        {1, 0, 1, 0},
        {0, 0, 0, 0},

        {0, 1, 0, 1},
        {1, 1, 1, 1},
        {1, 0, 1, 0},
    }

	g.bind.vertex_buffers[0] = sg.make_buffer({
		data = { ptr = &vertices, size = size_of(vertices) },
	})

	g.pip = sg.make_pipeline({
		shader = sg.make_shader(game_shader_desc(sg.query_backend())),
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
        }
	})

    stbi.set_flip_vertically_on_load(1)
    pixels, width, height := read_image_from_file("assets/paddle.png")
    g.bind.images[IMG_tex] = sg.make_image({
        width = i32(width),
        height = i32(height),
        data = {
            subimage = {
                0 = {
                    0 = { ptr = pixels, size = uint(width * height * 4) },
                },
            },
        },
    })

    stbi.image_free(pixels)

	g.bind.samplers[SMP_smp] = sg.make_sampler({})

	g.state = .Active
	g.width = LOGICAL_W
	g.height = LOGICAL_H
	player: Entity
    player_pos := Vec2{ (f32(g.width) / 2) - (PLAYER_SIZE.x / 2), f32(g.height) - PLAYER_SIZE.y}
    // player_pos := Vec2{ (f32(g.width) / 2) - (PLAYER_SIZE.x / 2), f32(g.height) - PLAYER_SIZE.y}
	entity_init(entity = &player, position = player_pos, sprite = {}, size = PLAYER_SIZE)

	g.player = player
}

x :f32= 0
@export
game_frame :: proc() {
	dt := f32(sapp.frame_duration())

    process_input(dt)

	vs_params := Vs_Params {
		mvp = compute_sprite_mvp(g.player),
	}

	pass_action := sg.Pass_Action {
		colors = {
			0 = { load_action = .CLEAR, clear_value = { 0.5, 0.2, 0.5, 1 } },
		},
	}
	sg.begin_pass({ action = pass_action, swapchain = sglue.swapchain() })
	sg.apply_pipeline(g.pip)
	sg.apply_bindings(g.bind)
	// vertex shader uniform with model-view-projection matrix
	sg.apply_uniforms(UB_vs_params, { ptr = &vs_params, size = size_of(vs_params) })
    // TODO: draw_sprite
	sg.draw(0, 6, 1)
	sg.end_pass()
	sg.commit()

	free_all(context.temp_allocator)
}

// 2D
// rotation in degrees
compute_sprite_mvp :: proc(entity: Entity) -> Mat4 {
	proj := linalg.matrix_ortho3d_f32(0, f32(g.width), f32(g.height), 0, -1, 1)
    model := linalg.matrix4_scale(Vec3{entity.size.x, entity.size.y, 1})
    model = linalg.matrix4_translate(Vec3{-0.5 * entity.size.x, -0.5 * entity.size.y, 0}) * model
    model = linalg.matrix4_rotate(to_radians(entity.rotation), Vec3{0,0,1}) * model
    model = linalg.matrix4_translate(Vec3{0.5 * entity.size.x, 0.5 * entity.size.y, 0}) * model
    model = linalg.matrix4_translate(Vec3{entity.position.x, entity.position.y, 0}) * model
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
	sprite: Texture2D,
	color: Vec3 = {1,1,1},
	velocity: Vec2 = {0,0},
) {
	entity.position = position
	entity.size = size
	entity.sprite = sprite
	entity.color = color
	entity.velocity = velocity
	entity.rotation = 0
}

read_image_from_file :: proc(file: string) -> ([^]byte, i32, i32) {
    file := fmt.ctprintf("%v", file)
    width, height, n_channels: i32
    pixels := stbi.load(file, &width, &height, &n_channels, 4)
    if pixels == nil {
        log.error("Failed to load image")
        return nil, 0, 0
    }
    return pixels, width, height

}
