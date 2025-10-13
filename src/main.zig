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
const AUDIO_SAMPLES_PER_FRAME = chip8.AUDIO_SAMPLE_RATE / TARGET_FPS;
const CYCLES_PER_FRAME = chip8.CPU_CLOCK_SPEED / TARGET_FPS;

const audio = struct {
    /// Buffer for the audio_sample_ring
    var sample_buf = std.mem.zeroes([AUDIO_SAMPLES_PER_FRAME * 3 + 1]u8);
    /// Audio ring buffer, contains generated samples.
    var sample_ring = spsc.RingBuffer(u8).init(&sample_buf);
};

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

    rl.SetTargetFPS(TARGET_FPS);

    const shader = rl.LoadShaderFromMemory(null, @embedFile("postprocess.glsl"));
    defer rl.UnloadShader(shader);
    const time_location = rl.GetShaderLocation(shader, "time");

    var display_buffer = std.mem.zeroes(chip8.FrameBuffer);
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

    for (0..audio.sample_ring.capacity()) |_| {
        try audio.sample_ring.produce(0);
    }

    rl.SetAudioStreamCallback(audio_stream, audio_stream_callback);
    rl.PlayAudioStream(audio_stream);

    const target_fill = 0.5;
    const feedback_gain = 1.1;

    while (!rl.WindowShouldClose()) {
        const produced_samples = audio.sample_ring.producer_fill();
        const free_samples = audio.sample_ring.capacity() - produced_samples;
        const fill_level = @as(f32, @floatFromInt(produced_samples)) / @as(f32, @floatFromInt(audio.sample_ring.capacity()));

        const emulation_error = fill_level - target_fill;
        const speed_factor = 1.0 - emulation_error * feedback_gain;

        const num_samples = @min(AUDIO_SAMPLES_PER_FRAME * speed_factor, @as(f32, @floatFromInt(free_samples)));
        const num_cycles: usize = @intFromFloat(num_samples / chip8.AUDIO_SAMPLES_PER_CYCLE);

        // std.debug.print("free: {d}, want: {d}, cycles: {d}\n", .{ free_samples, num_samples, num_cycles });

        for (0..num_cycles) |_| {
            chip8.emulate(&display_buffer, &audio.sample_ring);
        }

        rl.UpdateTexture(display_texture, &display_buffer);

        const time: f32 = @floatCast(rl.GetTime());

        rl.BeginDrawing();
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
        rl.DrawFPS(0, 0);
        rl.EndDrawing();

        chip8.reset_keys();
        while (true) {
            const key: u8 = @intCast(rl.GetCharPressed());
            switch (key) {
                '0'...'9' => chip8.press_key(key - '0'),
                'a'...'f' => chip8.press_key(key - 'a' + 10),
                0 => break,
                else => {},
            }
        }
    }
}

fn audio_stream_callback(audio_sample_ptr: ?*anyopaque, num_audio_samples: c_uint) callconv(.c) void {
    const audio_samples = @as([*]u8, @ptrCast(audio_sample_ptr))[0..num_audio_samples];

    if (audio.sample_ring.consumer_fill() < audio_samples.len) {
        @memset(audio_samples, 0);
    } else {
        for (0..audio_samples.len) |write_idx| {
            if (audio.sample_ring.consume()) |sample| {
                audio_samples[write_idx] = sample;
            } else {
                std.debug.print("ERROR: Audio underflow\n", .{});
            }
        }
    }
}
