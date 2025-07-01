package game

import "core:math/rand"

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
    if should_spawn(75) { // 1 in 75 chance
        p: Powerup
        powerup_init(&p, .Speed, {0.5,0.5,1.0}, 0, block.position, "speed")
        append(powerups, p)
    } else if should_spawn(75) {
        p: Powerup
        powerup_init(&p, .Sticky, {1,0.5,1.0}, 5, block.position, "sticky")
        append(powerups, p)
    } else if should_spawn(75) {
        p: Powerup
        powerup_init(&p, .Passthrough, {0.5,1.0,0.5}, 10, block.position, "passthrough")
        append(powerups, p)
    } else if should_spawn(75) {
        p: Powerup
        powerup_init(&p, .Padsize_Increase, {1.0,0.6,0.4}, 0, block.position, "size")
        append(powerups, p)
    } else if should_spawn(15) {
        p: Powerup
        powerup_init(&p, .Confuse, {1.0,0.3,0.3}, 15, block.position, "confuse")
        append(powerups, p)
    } else if should_spawn(15) {
        p: Powerup
        powerup_init(&p, .Chaos, {0.9,0.25,0.25}, 15, block.position, "chaos")
        append(powerups, p)
    }
}

powerup_activate :: proc(p: ^Powerup) {
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
