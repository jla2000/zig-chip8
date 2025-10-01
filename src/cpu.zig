const std = @import("std");

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
        emulate_cycle();
    }

    sound_timer = sound_timer -| 1;
    delay_timer = delay_timer -| 1;
}

/// Execute a single instruction
fn emulate_cycle() void {
    const opcode = @as(u16, memory[pc]) << 8 | @as(u16, memory[pc + 1]);
    _ = opcode;
    // std.debug.print("0x{x:04}: 0x{x:02}\n", .{ pc, opcode });
    pc += 2;
}
