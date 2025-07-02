package game

import "core:math/linalg"

check_collision :: proc(a: Entity, b: Entity) -> bool {
    return a.position.x + a.size.x >= b.position.x &&
           b.position.x + b.size.x >= a.position.x &&
           a.position.y + a.size.y >= b.position.y &&
           b.position.y + b.size.y >= a.position.y
}

check_ball_box_collision :: proc(ball: Ball, box: Entity) -> Collision_Data {
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

collisions_update :: proc(bricks: []Brick, as: ^Audio_System) {
    // for &box in g.levels[g.level].bricks {
    for &box in bricks {
        if !box.destroyed {
            collision := check_ball_box_collision(g.ball, box)
            if collision.collided {
                if !box.is_solid {
                    box.destroyed = true
                    powerups_spawn(box, &g.powerups)
                    play_sound(as, "hit-nonsolid")
                } else {
                    g.post_processor.shake_time = SHAKE_DURATION
                    g.post_processor.shake = true
                    play_sound(as, "hit-solid")
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
                play_sound(as, "get-powerup")
            }
        }
    }

    collision := check_ball_box_collision(g.ball, g.player)
    if !g.ball.stuck && collision.collided {
        center_board := g.player.position.x + (g.player.size.x / 2)
        distance := g.ball.position.x + g.ball.radius - center_board
        pct := distance / (g.player.size.x / 2)
        strength :f32= PADDLE_BOUNCE_STRENGTH
        speed := linalg.length(g.ball.velocity)
        g.ball.velocity.x = BALL_INITIAL_VELOCITY.x * pct * strength
        g.ball.velocity.y = -1 * abs(g.ball.velocity.y)
        g.ball.velocity = linalg.normalize0(g.ball.velocity) * speed
        g.ball.stuck = g.ball.sticky
        play_sound(as, "hit-paddle")
    }
}

