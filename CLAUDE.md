# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Breakout game implementation built with the Odin programming language and the Sokol graphics library. The project supports hot reloading during development, native builds, and web builds via WebAssembly.

## Common Commands

### Initial Setup
```bash
python build.py -update-sokol
```
Downloads Sokol bindings and compiles C libraries. Required for first-time setup.

### Development (Hot Reload)
```bash
python build.py -hot-reload -run
```
Builds the game as a hot-reloadable DLL and starts it. While running, re-run the same command to hot reload code changes.

### Release Build
```bash
python build.py -release
```
Creates optimized native release build in `build/release/`.

### Web Build
```bash
python build.py -web
```
Creates WebAssembly build in `build/web/`. Requires Emscripten (`emcc` in PATH or use `-emsdk-path`).

### Debug Builds
Add `-debug` flag to any build command for debuggable binaries.

### Force OpenGL
Add `-gl` flag to use OpenGL backend instead of platform defaults (D3D11/Metal).

### Miniaudio Optimization
Add `-check-miniaudio` flag to force recompilation of miniaudio for web builds (normally cached automatically).

## Code Architecture

### Core Structure
- `source/game.odin` - Main game logic and state management
- `source/main_**/` - Platform-specific entry points (hot_reload, release, web)
- `source/sokol/` - Sokol graphics library bindings and compiled libraries

### Game Systems
- **Resource Management** (`resource_manager.odin`) - Handles textures, shaders, fonts
- **Sprite Rendering** (`sprite_renderer.odin`) - 2D sprite batch rendering
- **Text Rendering** (`text_renderer.odin`) - Font rendering system
- **Particle System** (`particle_generator.odin`, `particle_renderer.odin`) - Particle effects
- **Audio System** - Platform-specific audio backends:
  - `audio_native.odin` - Uses miniaudio for native platforms
  - `audio_web.odin` - Web audio implementation with miniaudio bindings
- **Post Processing** (`post_processor.odin`) - Screen effects and shaders
- **Collision Detection** (`collision.odin`) - Game collision logic
- **Power-ups** (`powerup.odin`) - Game power-up system

### Build System Architecture
The `build.py` script handles:
- Cross-platform compilation (Windows, Linux, macOS)
- Hot reload DLL compilation with unique PDB naming on Windows
- Shader compilation using `sokol-shdc`
- Web build with Emscripten integration
- Automatic Sokol library updates and compilation
- Miniaudio pre-compilation and caching for faster web builds

### Audio Architecture
Dual audio system design:
- **Native**: Uses `vendor:miniaudio` with engine/sound management
- **Web**: Custom miniaudio bindings via C foreign imports
- Platform selection via Odin build tags (`#+build !js` / `#+build js`)
- **Web Performance**: Miniaudio is pre-compiled and cached in `source/web/precompiled/` to reduce build times

### Shader System
- Shaders written in `shader.glsl`
- Compiled to platform-specific formats (HLSL5, Metal, GLSL) using sokol-shdc
- Generated bindings in `gen__shader.odin`

### Hot Reload Design  
- Game logic compiled as DLL/shared library (`source/`)
- Host executable loads and reloads the game library (`source/main_hot_reload/`)  
- State persistence across reloads via global game memory
- Windows uses unique PDB files for proper debugging

## Important Notes

- Never modify files in `source/sokol/` or `sokol-shdc/` - these are auto-generated
- Never modify files in `source/web/precompiled/` - these are build artifacts
- Game state is in global `Game_Memory` struct for hot reload persistence
- Web builds require all assets to be in `assets/` directory (preloaded)
- Use `SOKOL_DLL=true` define for hot reload builds
- Platform-specific code uses Odin build tags (`#+build js`, `#+build !js`)
- Miniaudio compilation is automatically cached - use `-check-miniaudio` to force recompilation