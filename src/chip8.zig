const std = @import("std");

pub const CPU_CLOCK_SPEED = 600;
pub const TIMER_CLOCK_SPEED = 60;

pub const VIDEO_BUF_WIDTH = 64;
pub const VIDEO_BUF_HEIGHT = 32;
pub const VIDEO_BUF_SIZE = VIDEO_BUF_WIDTH * VIDEO_BUF_HEIGHT;

pub const AUDIO_SAMPLE_RATE = 48000;
const AUDIO_BUF_SIZE = 1024;
const AUDIO_SAMPLES_PER_CYCLE = AUDIO_SAMPLE_RATE / CPU_CLOCK_SPEED;

/// Video memory that is used for rendering.
var video_buf = std.mem.zeroes([VIDEO_BUF_SIZE]u8);

/// Audio buffer that is filled with generated audio samples
var audio_buf = std.mem.zeroes([AUDIO_BUF_SIZE]u8);
var audio_samples = std.ArrayListUnmanaged(u8).initBuffer(&audio_buf);

var memory = std.mem.zeroes([4096]u8);
var stack = std.mem.zeroes([16]u16);

/// General purpose registers
var regs = std.mem.zeroes([16]u8);

/// Keyboard state
var keys = std.mem.zeroes([16]bool);

/// Stack pointer
var sp: u8 = 0;
/// Program counter
var pc: u16 = 0;
/// Index register
var idx: u16 = 0;

var sound_timer: u8 = 0;
var delay_timer: u8 = 0;

var cycle_counter: usize = 0;

/// Load the given bytes into memory.
/// Should be called only once (reset not yet implemented).
pub fn load_rom(rom: []const u8) void {
    const font_data = [_]u8{
        0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
        0x20, 0x60, 0x20, 0x20, 0x70, // 1
        0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
        0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
        0x90, 0x90, 0xF0, 0x10, 0x10, // 4
        0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
        0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
        0xF0, 0x10, 0x20, 0x40, 0x40, // 7
        0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
        0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
        0xF0, 0x90, 0xF0, 0x90, 0x90, // A
        0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
        0xF0, 0x80, 0x80, 0x80, 0xF0, // C
        0xE0, 0x90, 0x90, 0x90, 0xE0, // D
        0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
        0xF0, 0x80, 0xF0, 0x80, 0x80, // F
    };
    const rom_start = 0x200;

    @memcpy(memory[0..font_data.len], &font_data);
    @memcpy(memory[rom_start .. rom_start + rom.len], rom);

    // TODO: Reset other state as well.
    pc = rom_start;
}

/// Emulate the CPU.
/// This function is driven by the amount of requested audio samples.
pub fn emulate(video_output_buf: []u8, audio_output_buf: []u8) void {
    // Emulate cpu until enough audio samples have been generated
    while (audio_samples.items.len < audio_output_buf.len) {
        // Handle timers
        if (cycle_counter % (CPU_CLOCK_SPEED / TIMER_CLOCK_SPEED) == 0) {
            sound_timer -|= 1;
            delay_timer -|= 1;
        }

        run_instruction(video_output_buf);
        generate_audio_samples();

        cycle_counter += 1;
    }

    // Fill given audio buffer
    @memcpy(audio_output_buf, audio_samples.items[0..audio_output_buf.len]);
    remove_audio_samples(audio_output_buf.len);
}

/// Notify that a key has been pressed.
pub fn press_key(key: u8) void {
    keys[key] = true;
}

/// Notify that a key has been released.
pub fn release_key(key: u8) void {
    keys[key] = false;
}

/// Removes audio samples after they have ceen consumed
fn remove_audio_samples(count: usize) void {
    const remaining_samples = audio_samples.items.len - count;
    @memcpy(audio_samples.items[0..remaining_samples], audio_samples.items[count .. count + remaining_samples]);
    audio_samples.items.len = remaining_samples;
}

/// Generate audio samples for one cycle
fn generate_audio_samples() void {
    for (0..AUDIO_SAMPLES_PER_CYCLE) |i| {
        const freq = 440;
        const t = @as(f32, @floatFromInt(i)) / AUDIO_SAMPLE_RATE;
        const sample: u8 = if (@sin(2.0 * std.math.pi * freq * t) > 0) 100 else 0;

        audio_samples.appendBounded(if (sound_timer > 0) sample else 0) catch unreachable;
    }
}

/// Execute a single instruction
fn run_instruction(video_output_buf: []u8) void {
    const opcode_high = memory[pc];
    const opcode_low = memory[pc + 1];

    const x = opcode_high & 0xf;
    const y = opcode_low >> 4;
    const n = opcode_low & 0xf;
    const nn = opcode_low;
    const nnn = read_u16(pc) & 0xfff;

    pc += 2;

    switch (opcode_high >> 4) {
        0x0 => switch (nnn) {
            // Clear display
            0x0E0 => {
                @memset(&video_buf, 0);
                @memcpy(video_output_buf, &video_buf);
            },
            // Return
            0x0EE => pc = pop_stack(),
            // call machine code routine
            else => unreachable,
        },
        // goto nnn
        0x1 => pc = nnn,
        // call nnn
        0x2 => {
            push_stack(pc);
            pc = nnn;
        },
        // if Vx == NN
        0x3 => if (regs[x] == nn) {
            pc += 2;
        },
        // if Vx != NN
        0x4 => if (regs[x] != nn) {
            pc += 2;
        },
        // if Vx == Vy
        0x5 => if (regs[x] == regs[y]) {
            pc += 2;
        },
        // Vx = nn
        0x6 => regs[x] = nn,
        // Vx += nn
        0x7 => regs[x] +%= nn,
        0x8 => switch (n) {
            // Vx = Vy
            0x0 => regs[x] = regs[y],
            // Vx |= Vy
            0x1 => regs[x] |= regs[y],
            // Vx &= Vy
            0x2 => regs[x] &= regs[y],
            // Vx ^= Vy
            0x3 => regs[x] ^= regs[y],
            // Vx += Vy
            0x4 => {
                regs[x], regs[0xf] = @addWithOverflow(regs[x], regs[y]);
            },
            // Vx -= Vy
            0x5 => {
                regs[x], regs[0xf] = @subWithOverflow(regs[x], regs[y]);
            },
            // Vx >== 1
            0x6 => {
                regs[0xf] = regs[x] & 1;
                regs[x] >>= 1;
            },
            // Vx = Vy - Vx
            0x7 => {
                regs[x], regs[0xf] = @subWithOverflow(regs[y], regs[x]);
            },
            // Vx <<= 1
            0xE => {
                regs[0xf] = regs[x] & 0b10000000;
                regs[x] <<= 1;
            },
            else => unreachable,
        },
        // if Vx != Vy
        0x9 => if (regs[x] != regs[y]) {
            pc += 2;
        },
        // I = nnn
        0xa => idx = nnn,
        // Jump to V0 + nnn
        0xb => pc = regs[0] + nnn,
        // Generate random number
        0xc => regs[x] = std.crypto.random.int(u8) & nn,
        // Draw
        0xd => {
            draw_sprite(regs[x], regs[y], n);
            @memcpy(video_output_buf, &video_buf);
        },
        0xe => switch (nn) {
            // if (key == Vx)
            0x9E => if (keys[regs[x] & 0xf]) {
                pc += 2;
            },
            // if (key != Vx)
            0xA1 => if (!keys[regs[y] & 0xf]) {
                pc += 2;
            },
            else => unreachable,
        },
        0xf => switch (nn) {
            // Vx = delay
            0x07 => regs[x] = delay_timer,
            // Wait for key press
            0x0A => regs[x] = wait_for_key(),
            // Set delay timer
            0x15 => delay_timer = regs[x],
            // Set sound timer
            0x18 => sound_timer = regs[x],
            // I += Vx
            0x1E => idx += regs[x],
            // Select font character (each is 5 bytes)
            0x29 => idx = regs[x] * 5,
            // Store bcd
            0x33 => {
                const val = bcd(regs[x]);
                @memcpy(memory[idx .. idx + 3], &val);
            },
            // Dump registers
            0x55 => for (0..x + 1) |offset| {
                memory[idx + offset] = regs[offset];
            },
            // Load registers
            0x65 => for (0..x + 1) |offset| {
                regs[offset] = memory[idx + offset];
            },
            else => unreachable,
        },
        else => unreachable,
    }
}

fn wait_for_key() u8 {
    unreachable;
}

/// Read an u16 from the given address in memory.
fn read_u16(address: u16) u16 {
    return @as(u16, memory[address]) << 8 | @as(u16, memory[address + 1]);
}

// Write an u16 to the given address in memory.
fn write_u16(address: u16, value: u16) void {
    memory[address] = @intCast(value >> 8);
    memory[address + 1] = @intCast(value);
}

fn push_stack(value: u16) void {
    stack[sp] = value;
    sp += 1;
}

fn pop_stack() u16 {
    sp -= 1;
    return stack[sp];
}

fn get_bit(value: u8, index: u3) bool {
    return (value >> index) & 1 == 1;
}

/// Draws a sprite to memory
fn draw_sprite(x: u8, y: u8, height: u8) void {
    // Renders a sprite with the given height, row by row.
    // If the pixel is in memory is already set, collision is reported by setting the VF register to 1.
    // Each pixel of the sprite is xored (flipped) with the video memory.

    // Reset collision flag
    regs[0xf] = 0;

    for (0..height) |y_offset| {
        const sprite_byte = memory[idx + y_offset];

        for (0..8) |x_offset| {
            if (get_bit(sprite_byte, @intCast(7 - x_offset))) {
                const buffer_idx = (y + y_offset) * VIDEO_BUF_WIDTH + (x + x_offset);

                if (video_buf[buffer_idx] == 255) {
                    // Collision detected.
                    regs[0xf] = 1;
                }

                // Invert pixel
                video_buf[buffer_idx] ^= 255;
            }
        }
    }
}

fn bcd(value: u8) [3]u8 {
    return .{
        (value / 100) % 10,
        (value / 10) % 10,
        value % 10,
    };
}
