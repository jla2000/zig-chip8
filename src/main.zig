const std = @import("std");
const chip8 = @import("chip8.zig");

const rl = @cImport({
    @cInclude("raylib.h");
});

const AUDIO_SAMPLE_RATE = 44100;
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

    const audio_stream = rl.LoadAudioStream(AUDIO_SAMPLE_RATE, 8, 1);
    defer rl.UnloadAudioStream(audio_stream);

    rl.SetAudioStreamCallback(audio_stream, audio_stream_callback);
    rl.PlayAudioStream(audio_stream);

    rl.SetTargetFPS(60);
    while (!rl.WindowShouldClose()) {
        // chip8.emulate();

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
        rl.EndDrawing();

        // if (chip8.should_play_sound() and rl.IsAudioStreamProcessed(audio_stream)) {}
    }
}

fn audio_stream_callback(audio_sample_ptr: ?*anyopaque, num_audio_samples: c_uint) callconv(.c) void {
    const samples = @as([*]u8, @ptrCast(@alignCast(audio_sample_ptr)));

    const num_cpu_cycles = @as(f32, @floatFromInt(num_audio_samples)) / AUDIO_SAMPLE_RATE * chip8.CPU_CLOCK_SPEED;
    chip8.emulate(num_cpu_cycles, samples, num_audio_samples);
}
