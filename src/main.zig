const std = @import("std");
const chip8 = @import("chip8.zig");
const spsc = @import("spsc.zig");

const rl = @cImport({
    @cInclude("raylib.h");
});

const WINDOW_SCALE = 10;
const WINDOW_WIDTH = WINDOW_SCALE * chip8.VIDEO_BUF_WIDTH;
const WINDOW_HEIGHT = WINDOW_SCALE * chip8.VIDEO_BUF_HEIGHT;
const TARGET_FPS = 60;

var video_buf = std.mem.zeroes(chip8.FrameBuffer);
var audio_sample_buf = std.mem.zeroes([chip8.AUDIO_SAMPLE_RATE / TARGET_FPS * 2]u8);
var audio_sample_ring = spsc.RingBuffer(u8).init(&audio_sample_buf);

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var args = try std.process.ArgIterator.initWithAllocator(allocator);
    defer args.deinit();

    std.debug.assert(args.skip());
    if (args.next()) |filename| {
        const rom_file = try std.fs.cwd().openFile(filename, .{});
        const rom = try rom_file.readToEndAlloc(allocator, 4096);
        defer allocator.free(rom);

        chip8.load_rom(rom);
    } else {
        chip8.load_rom(@embedFile("roms/trip8.ch8"));
    }

    rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "zig-chip8");
    defer rl.CloseWindow();

    rl.SetWindowState(rl.FLAG_VSYNC_HINT);

    const shader = rl.LoadShaderFromMemory(null, @embedFile("postprocess.glsl"));
    defer rl.UnloadShader(shader);
    const time_location = rl.GetShaderLocation(shader, "time");

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

    const audio_stream = rl.LoadAudioStream(chip8.AUDIO_SAMPLE_RATE, chip8.AUDIO_SAMPLE_SIZE, chip8.AUDIO_CHANNELS);
    defer rl.UnloadAudioStream(audio_stream);

    for (0..audio_sample_buf.len / 2) |_| {
        audio_sample_ring.produce(0) catch unreachable;
    }

    rl.SetAudioStreamCallback(audio_stream, audio_stream_callback);
    rl.PlayAudioStream(audio_stream);

    while (!rl.WindowShouldClose()) {
        chip8.emulate(&video_buf, &audio_sample_ring);
        rl.UpdateTexture(display_texture, &video_buf);

        rl.BeginDrawing();
        const time = @as(f32, @floatCast(rl.GetTime()));
        rl.SetShaderValue(shader, time_location, &time, rl.SHADER_UNIFORM_FLOAT);
        rl.BeginShaderMode(shader);
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
        rl.EndShaderMode();
        rl.EndDrawing();
    }
}

fn audio_stream_callback(audio_sample_ptr: ?*anyopaque, num_audio_samples: c_uint) callconv(.c) void {
    const audio_samples = @as([*]u8, @ptrCast(audio_sample_ptr))[0..num_audio_samples];

    var write_idx: usize = 0;
    while (write_idx < audio_samples.len) {
        if (audio_sample_ring.consume()) |sample| {
            audio_samples[write_idx] = sample;
            write_idx += 1;
        }
    }
}
