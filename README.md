# zig-chip8

Cross platform [chip8](https://en.wikipedia.org/wiki/CHIP-8) emulator, built using zig and [raylib](https://www.raylib.com/)

## Architecture

The emulation logic is executed on the rendering thread, while audio samples are being played using an audio callback.
The emulator will emit audio samples to a dedicated ring buffer, which the audio thread will consume in the background.

## Try it out using nix

```bash
nix run github:jla2000/zig-chip8
```

## Build locally

### Native build

```bash
zig build run 
```

### Cross compile to windows

```bash
zig build -Dwindows
```

## Todo's

- Implement keyboard handling
- Implement super chip 8 extension
- Implement xochip extension
