package game

import "core:math/rand"

POWERUP_SIZE :: Vec2{60,20}
POWERUP_VELOCITY :: Vec2{0,150}

POWERUP_COMMON_SPAWN_CHANCE :: 15
POWERUP_RARE_SPAWN_CHANCE :: 75

POWERUP_STICKY_DURATION :: 5
POWERUP_PASSTHROUGH_DURATION :: 10
POWERUP_CONFUSE_DURATION :: 15
POWERUP_CHAOS_DURATION :: 15

POWERUP_SPEED_MULTIPLIER :: 1.2
POWERUP_PADDLE_SIZE_INCREASE :: 50

POWERUP_COLOR_SPEED :: Vec3{0.5, 0.5, 1.0}
POWERUP_COLOR_STICKY :: Vec3{1.0, 0.5, 1.0}
POWERUP_COLOR_PASSTHROUGH :: Vec3{0.5, 1.0, 0.5}
POWERUP_COLOR_PADSIZE :: Vec3{1.0, 0.6, 0.4}
POWERUP_COLOR_CONFUSE :: Vec3{1.0, 0.3, 0.3}
POWERUP_COLOR_CHAOS :: Vec3{0.9, 0.25, 0.25}

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

Powerup :: struct {
    using entity: Entity,
    type: Powerup_Type,
    destroyed: bool,
    activated: bool,
    duration: f32,
}

powerup_init :: proc(powerup: ^Powerup, type: Powerup_Type, color: Vec3, duration: f32, position: Vec2, texture_name: string) {
    entity_init(
        &powerup.entity, 
        position = position, 
        size = POWERUP_SIZE, 
        color = color, 
        velocity = POWERUP_VELOCITY,
        texture_name = texture_name,
    )
    powerup.type = type
    powerup.duration = duration
    powerup.activated = false
}

should_spawn :: proc(chance: u32) -> bool {
    chance := 1 / f32(chance)
    rgn := rand.float32()
    return rgn < chance
}

powerups_spawn :: proc(block: Entity, powerups: ^[dynamic]Powerup) {
    if should_spawn(POWERUP_RARE_SPAWN_CHANCE) { // 1 in 75 chance
        p: Powerup
        powerup_init(&p, .Speed, POWERUP_COLOR_SPEED, 0, block.position, "speed")
        append(powerups, p)
    } else if should_spawn(POWERUP_RARE_SPAWN_CHANCE) {
        p: Powerup
        powerup_init(&p, .Sticky, POWERUP_COLOR_STICKY, POWERUP_STICKY_DURATION, block.position, "sticky")
        append(powerups, p)
    } else if should_spawn(POWERUP_RARE_SPAWN_CHANCE) {
        p: Powerup
        powerup_init(&p, .Passthrough, POWERUP_COLOR_PASSTHROUGH, POWERUP_PASSTHROUGH_DURATION, block.position, "passthrough")
        append(powerups, p)
    } else if should_spawn(POWERUP_RARE_SPAWN_CHANCE) {
        p: Powerup
        powerup_init(&p, .Padsize_Increase, POWERUP_COLOR_PADSIZE, 0, block.position, "size")
        append(powerups, p)
    } else if should_spawn(POWERUP_COMMON_SPAWN_CHANCE) { // 1 in 15 chance
        p: Powerup
        powerup_init(&p, .Confuse, POWERUP_COLOR_CONFUSE, POWERUP_CONFUSE_DURATION, block.position, "confuse")
        append(powerups, p)
    } else if should_spawn(POWERUP_COMMON_SPAWN_CHANCE) {
        p: Powerup
        powerup_init(&p, .Chaos, POWERUP_COLOR_CHAOS, POWERUP_CHAOS_DURATION, block.position, "chaos")
        append(powerups, p)
    }
}

powerup_activate :: proc(p: ^Powerup) {
    p.activated = true

    switch p.type {

    case .Speed:
        g.ball.velocity *= POWERUP_SPEED_MULTIPLIER

    case .Sticky:
        g.ball.sticky = true
        g.player.color = {1,0.5,1}

    case .Passthrough:
        g.ball.passthrough = true
        g.ball.color = {1,0.5,0.5}

    case .Padsize_Increase:
        g.player.size.x += POWERUP_PADDLE_SIZE_INCREASE

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

powerups_update :: proc(dt: f32, powerups: ^[dynamic]Powerup) {
    for &p in powerups {
        p.position += p.velocity * dt
        if p.activated {
            p.duration -= dt
            if p.duration <= 0 {
                p.activated = false
                if p.type == .Sticky {
                    if !is_other_powerup_active(.Sticky) {
                        g.ball.sticky = false
                        g.player.color = PLAYER_COLOR
                    }
                } else if p.type == .Passthrough {
                    if !is_other_powerup_active(.Passthrough) {
                        g.ball.passthrough = false
                        g.ball.color = BALL_COLOR
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
    for p, i in powerups {
        if p.destroyed && !p.activated {
            append(&indices_to_remove, i)
        }
    }
    for idx in indices_to_remove {
        unordered_remove(powerups, idx)
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
