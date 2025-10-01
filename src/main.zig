const std = @import("std");
const cpu = @import("cpu.zig");

const rl = @cImport({
    @cInclude("raylib.h");
});

const DISPLAY_WIDTH = 64;
const DISPLAY_HEIGHT = 32;

const WINDOW_SCALE = 20;
const WINDOW_WIDTH = WINDOW_SCALE * DISPLAY_WIDTH;
const WINDOW_HEIGHT = WINDOW_SCALE * DISPLAY_HEIGHT;

pub fn main() !void {
    cpu.load_rom(@embedFile("trip8.ch8"));

    rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "zig-chip8");
    defer rl.CloseWindow();

    const display_texture = rl.LoadTextureFromImage(rl.Image{
        .data = null,
        .width = DISPLAY_WIDTH,
        .height = DISPLAY_HEIGHT,
        .format = rl.PIXELFORMAT_UNCOMPRESSED_GRAYSCALE,
        .mipmaps = 1,
    });
    defer rl.UnloadTexture(display_texture);

    rl.InitAudioDevice();
    defer rl.CloseAudioDevice();

    const beep_sound = rl.LoadSoundFromWave(rl.Wave{
        .data = null,
        .frameCount = 0,
        .sampleRate = 0,
        .sampleSize = 0,
        .channels = 1,
    });
    defer rl.UnloadSound(beep_sound);

    rl.PlaySound(beep_sound);

    // var random_data = std.mem.zeroes([DISPLAY_WIDTH * DISPLAY_HEIGHT]u8);
    // for (&random_data) |*value| {
    //     value.* = @intCast(rl.GetRandomValue(0, 255));
    // }
    //
    // rl.UpdateTexture(display_texture, &random_data);

    rl.SetTargetFPS(60);
    while (!rl.WindowShouldClose()) {
        cpu.emulate();

        rl.BeginDrawing();
        rl.ClearBackground(rl.BLACK);
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
    }
}
