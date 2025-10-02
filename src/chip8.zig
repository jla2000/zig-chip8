const std = @import("std");

pub const VIDEO_BUF_WIDTH = 64;
pub const VIDEO_BUF_HEIGHT = 32;

const VIDEO_BUF_SIZE = VIDEO_BUF_WIDTH * VIDEO_BUF_HEIGHT;

/// Video memory that should be displayed currently.
pub var front_buffer = std.mem.zeroes([VIDEO_BUF_SIZE]u8);
/// Video memory that should be used for rendering.
var back_buffer = std.mem.zeroes([VIDEO_BUF_SIZE]u8);

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
/// Should be called with a tickrate of 60Hz.
pub fn emulate() void {
    sound_timer -|= 1;
    delay_timer -|= 1;

    // Should result in a tickrate of 600Hz.
    for (0..10) |_| {
        run_instruction();
    }
}

/// Indicates whether a beeping sound should be played currently.
pub fn should_play_sound() bool {
    return sound_timer > 0;
}

/// Notify that a key has been pressed.
pub fn press_key(key: u8) void {
    keys[key] = true;
}

/// Notify that a key has been released.
pub fn release_key(key: u8) void {
    keys[key] = false;
}

/// Execute a single instruction
fn run_instruction() void {
    const opcode_high = memory[pc];
    const opcode_low = memory[pc + 1];

    // std.debug.print("0x{x:04}: 0x{x:02}{x:02}\n", .{ pc, opcode_high, opcode_low });

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
                @memset(&back_buffer, 0);
                @memcpy(&front_buffer, &back_buffer);
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
        0xd => draw_sprite(regs[x], regs[y], n),
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
            0x55 => for (0..x) |offset| {
                memory[idx + offset] = regs[offset];
            },
            // Load registers
            0x65 => for (0..x) |offset| {
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
                const y_pos = (y + y_offset) % VIDEO_BUF_HEIGHT;
                const x_pos = (x + x_offset) % VIDEO_BUF_WIDTH;
                const buffer_idx = y_pos * VIDEO_BUF_WIDTH + x_pos;

                if (back_buffer[buffer_idx] == 255) {
                    // Collision detected.
                    regs[0xf] = 1;
                }

                // Invert pixel
                back_buffer[buffer_idx] ^= 255;
            }
        }
    }

    // Present new frame
    @memcpy(&front_buffer, &back_buffer);
}

fn bcd(value: u8) [3]u8 {
    return .{
        (value / 100) % 10,
        (value / 10) % 10,
        value % 10,
    };
}
