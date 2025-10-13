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

const audio = struct {
    /// Buffer for the audio_sample_ring
    var sample_buf = std.mem.zeroes([AUDIO_SAMPLES_PER_FRAME * 3 + 1]u8);
    /// Audio ring buffer, contains generated samples.
    var sample_ring = spsc.RingBuffer(u8).init(&sample_buf);
    /// Buffer for the request_sample_ring.
    var request_buf = std.mem.zeroes([16]u16);
    /// Audio requestor ring, tells the rendering thread how many samples should be produced.
    var request_ring = spsc.RingBuffer(u16).init(&request_buf);
    /// Used to gracefully shut down the audio thread.
    var should_play = std.atomic.Value(bool).init(true);
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

    // Prefill two audio frames
    for (0..audio.sample_buf.len - 1) |_| {
        audio.sample_ring.produce(0) catch unreachable;
    }

    rl.SetAudioStreamCallback(audio_stream, audio_stream_callback);
    rl.PlayAudioStream(audio_stream);

    while (!rl.WindowShouldClose()) {
        while (audio.request_ring.consume()) |num_samples| {
            chip8.emulate(&display_buffer, &audio.sample_ring, num_samples);
        }
        rl.UpdateTexture(display_texture, &display_buffer);

        const time = @as(f32, @floatCast(rl.GetTime()));

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

    // Hint the audio thread that no audio is being generated anymore.
    audio.should_play.store(false, .monotonic);
}

fn audio_stream_callback(audio_sample_ptr: ?*anyopaque, num_audio_samples: c_uint) callconv(.c) void {
    const audio_samples = @as([*]u8, @ptrCast(audio_sample_ptr))[0..num_audio_samples];

    var write_idx: usize = 0;
    while (write_idx < audio_samples.len) {
        if (audio.sample_ring.consume()) |sample| {
            audio_samples[write_idx] = sample;
            write_idx += 1;
        } else {
            if (!audio.should_play.load(.monotonic)) {
                break;
            } else {
                std.debug.panic("ERROR: Audio underflow\n", .{});
            }
        }
    }

    // Request the exact amount that was taken from ring buffer
    audio.request_ring.produce(@intCast(num_audio_samples)) catch unreachable;
}
