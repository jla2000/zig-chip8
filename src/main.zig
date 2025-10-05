const std = @import("std");
const chip8 = @import("chip8.zig");

const rl = @cImport({
    @cInclude("raylib.h");
});

const WINDOW_SCALE = 10;
const WINDOW_WIDTH = WINDOW_SCALE * chip8.VIDEO_BUF_WIDTH;
const WINDOW_HEIGHT = WINDOW_SCALE * chip8.VIDEO_BUF_HEIGHT;

const FrameBuffer = [chip8.VIDEO_BUF_SIZE]u8;

var frame_buffers = std.mem.zeroes([2]FrameBuffer);
var front_buf_idx: u8 = 0;
var back_buf_idx: u8 = 1;
var mutex = std.Thread.Mutex{};

var key_buf = std.mem.zeroes([1024]u8);
var key_queue = std.Deque(u8).initBuffer(&key_buf);

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var args = try std.process.ArgIterator.initWithAllocator(allocator);
    defer args.deinit();
    std.debug.assert(args.skip());

    // Load trip8 on default
    const rom = if (args.next()) |filename| try read_rom(allocator, filename) else @embedFile("roms/trip8.ch8");
    chip8.load_rom(rom);

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

    const audio_stream = rl.LoadAudioStream(chip8.AUDIO_SAMPLE_RATE, chip8.AUDIO_SAMPLE_SIZE, chip8.AUDIO_CHANNELS);
    defer rl.UnloadAudioStream(audio_stream);

    rl.SetAudioStreamCallback(audio_stream, audio_stream_callback);
    rl.PlayAudioStream(audio_stream);

    rl.SetTargetFPS(60);
    while (!rl.WindowShouldClose()) {
        mutex.lock();
        rl.UpdateTexture(display_texture, &frame_buffers[front_buf_idx]);
        mutex.unlock();

        rl.BeginDrawing();
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
    }
}

fn audio_stream_callback(audio_sample_ptr: ?*anyopaque, num_audio_samples: c_uint) callconv(.c) void {
    const audio_samples = @as([*]u8, @ptrCast(audio_sample_ptr))[0..num_audio_samples];
    chip8.emulate(&frame_buffers[back_buf_idx], audio_samples);

    mutex.lock();
    std.mem.swap(u8, &front_buf_idx, &back_buf_idx);
    mutex.unlock();
}

fn read_rom(allocator: std.mem.Allocator, filename: []const u8) ![]u8 {
    const rom_file = try std.fs.cwd().openFile(filename, .{});
    return try rom_file.readToEndAlloc(allocator, 4096);
}
