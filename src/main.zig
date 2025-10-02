const std = @import("std");
const chip8 = @import("chip8.zig");

const rl = @cImport({
    @cInclude("raylib.h");
});

const WINDOW_SCALE = 10;
const WINDOW_WIDTH = WINDOW_SCALE * chip8.VIDEO_BUF_WIDTH;
const WINDOW_HEIGHT = WINDOW_SCALE * chip8.VIDEO_BUF_HEIGHT;

pub fn main() !void {
    chip8.load_rom(@embedFile("roms/7-beep.ch8"));

    rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "zig-chip8");
    defer rl.CloseWindow();

    const display_texture = rl.LoadTextureFromImage(rl.Image{
        .data = null,
        .width = chip8.VIDEO_BUF_WIDTH,
        .height = chip8.VIDEO_BUF_HEIGHT,
        .format = rl.PIXELFORMAT_UNCOMPRESSED_GRAYSCALE,
        .mipmaps = 1,
    });
    defer rl.UnloadTexture(display_texture);

    rl.InitAudioDevice();
    defer rl.CloseAudioDevice();

    // Generate samples for one complete frame.
    const sample_rate = 44100;
    const freq = 440;
    var samples = std.mem.zeroes([sample_rate]u8);
    for (0..samples.len) |i| {
        const t = @as(f32, @floatFromInt(i)) / sample_rate;
        samples[i] = if (@sin(2.0 * std.math.pi * freq * t) > 0) 255 else 0;
    }

    const beep_sound = rl.LoadSoundFromWave(rl.Wave{
        .data = &samples,
        .frameCount = samples.len,
        .sampleRate = sample_rate,
        .sampleSize = 8,
        .channels = 1,
    });
    defer rl.UnloadSound(beep_sound);

    rl.SetTargetFPS(60);
    while (!rl.WindowShouldClose()) {
        chip8.emulate();

        rl.BeginDrawing();
        rl.UpdateTexture(display_texture, &chip8.front_buffer);
        rl.DrawTexturePro(display_texture, rl.Rectangle{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(display_texture.width),
            .height = @floatFromInt(display_texture.height),
        }, rl.Rectangle{
            .x = 0,
            .y = 0,
            .width = WINDOW_WIDTH,
            .height = WINDOW_HEIGHT,
        }, rl.Vector2{
            .x = 0,
            .y = 0,
        }, 0, rl.WHITE);
        rl.DrawFPS(0, 0);
        rl.EndDrawing();

        if (chip8.should_play_sound() and !rl.IsSoundPlaying(beep_sound)) {
            rl.PlaySound(beep_sound);
            std.debug.print("beep ", .{});
        }
        if (!chip8.should_play_sound() and rl.IsSoundPlaying(beep_sound)) {
            rl.StopSound(beep_sound);
        }
    }
}
