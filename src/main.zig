const std = @import("std");
const chip8 = @import("chip8.zig");

const rl = @cImport({
    @cInclude("raylib.h");
});

const WINDOW_SCALE = 20;
const WINDOW_WIDTH = WINDOW_SCALE * chip8.FRAME_BUFFER_WIDTH;
const WINDOW_HEIGHT = WINDOW_SCALE * chip8.FRAME_BUFFER_HEIGHT;

pub fn main() !void {
    chip8.load_rom(@embedFile("trip8.ch8"));

    rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "zig-chip8");
    defer rl.CloseWindow();

    const display_texture = rl.LoadTextureFromImage(rl.Image{
        .data = null,
        .width = chip8.FRAME_BUFFER_WIDTH,
        .height = chip8.FRAME_BUFFER_HEIGHT,
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

    rl.SetTargetFPS(60);
    while (!rl.WindowShouldClose()) {
        chip8.emulate();

        if (chip8.should_play_sound() and !rl.IsSoundPlaying(beep_sound)) {
            rl.PlaySound(beep_sound);
        }
        if (!chip8.should_play_sound() and rl.IsSoundPlaying(beep_sound)) {
            rl.StopSound(beep_sound);
        }

        rl.BeginDrawing();
        rl.UpdateTexture(display_texture, chip8.frame_buffer);
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
