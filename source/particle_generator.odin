package game

import "core:math/rand"
import sa "core:container/small_array"
import sg "sokol/gfx"

MAX_PARTICLES :: 500

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

particle_generator_init :: proc(pg: ^Particle_Generator) {
    particles: sa.Small_Array(MAX_PARTICLES, Particle)
    particle := particle_init()
    for _ in 0..<MAX_PARTICLES {
        sa.push(&particles, particle)
    }
    pg^ = Particle_Generator {
        particles = particles,
        max_particles = MAX_PARTICLES,
    }

}

particle_generator_update :: proc(pg: ^Particle_Generator, dt: f32, object: Entity, n_new_particles: int = 2, offset: Vec2 = {0,0}) {
    // continuously generate particles
    for _ in 0..<n_new_particles {
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

particle_init :: proc() -> Particle {
    return { color = {1,1,1,1} } }

particle_generator_draw :: proc(pr: ^Particle_Renderer, pg: Particle_Generator, rm: Resource_Manager) {
    projection := pr.projection

    for i in 0..<sa.len(pg.particles) {
        p := sa.get(pg.particles, i)
        if p.life > 0 {
            particle_vs_params := Particle_Vs_Params {
                projection = projection,
                offset = p.position,
                color = p.color,
            }

            if tex, exists := resman_get_texture(rm, "particle"); exists {
                pr.bind.images[IMG_particle_tex] = tex
            } 

            sg.apply_bindings(pr.bind)
            sg.apply_uniforms(UB_particle_vs_params, { ptr = &particle_vs_params, size = size_of(particle_vs_params) })
            sg.draw(0, 6, 1)
        }
    }
}
