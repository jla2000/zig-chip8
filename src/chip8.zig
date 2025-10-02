const std = @import("std");

pub const FRAME_BUFFER_WIDTH = 64;
pub const FRAME_BUFFER_HEIGHT = 32;

const FRAME_BUFFER_SIZE = FRAME_BUFFER_WIDTH * FRAME_BUFFER_HEIGHT;

/// Two buffers that are used for presenting and rendering.
var front_buffer = std.mem.zeroes([FRAME_BUFFER_SIZE]u8);
var back_buffer = std.mem.zeroes([FRAME_BUFFER_SIZE]u8);

/// Points to the frame that should be displayed currently.
pub var frame_buffer = &front_buffer;
/// Points to the frame that is rendered currently.
var render_buffer = &back_buffer;

var memory = std.mem.zeroes([4096]u8);
var stack = std.mem.zeroes([16]u16);

/// General purpose registers
var regs = std.mem.zeroes([16]u8);

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
    // Should result in a tickrate of 600Hz.
    for (0..10) |_| {
        run_instruction();
    }

    sound_timer = sound_timer -| 1;
    delay_timer = delay_timer -| 1;
}

/// Indicates whether a beeping sound should be played currently.
pub fn should_play_sound() bool {
    return sound_timer > 0;
}

/// Execute a single instruction
fn run_instruction() void {
    const opcode_high = memory[pc];
    const opcode_low = memory[pc + 1];

    std.debug.print("0x{x:04}: 0x{x:02}{x:02}\n", .{ pc, opcode_high, opcode_low });

    const x = opcode_high & 0xf;
    const y = opcode_low >> 2;
    const nn = opcode_low;
    const nnn = read_u16(pc) & 0xfff;

    pc += 2;

    switch (opcode_high >> 4) {
        0x0 => switch (nnn) {
            // Clear display
            0x0E0 => {
                @memset(render_buffer, 0);
                render();
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
        0x6 => {},
        0x7 => {},
        0x8 => {},
        0x9 => {},
        0xa => {},
        0xb => {},
        0xc => {},
        0xd => {},
        0xe => {},
        0xf => {},
        else => unreachable,
    }
}

/// Swap buffers
fn render() void {
    const tmp = frame_buffer;
    frame_buffer = render_buffer;
    render_buffer = tmp;
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
