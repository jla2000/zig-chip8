const std = @import("std");

pub fn RingBuffer(comptime T: type) type {
    // std.debug.assert(std.atomic.cache_line == @sizeOf(usize));

    return struct {
        const Self = @This();

        write_idx: std.atomic.Value(usize),
        read_idx: std.atomic.Value(usize),
        buffer: []T,

        pub fn init(buffer: []T) Self {
            return Self{
                .write_idx = std.atomic.Value(usize).init(0),
                .read_idx = std.atomic.Value(usize).init(0),
                .buffer = buffer,
            };
        }

        pub fn produce(self: *Self, value: T) !void {
            const write_idx = self.write_idx.load(.monotonic);
            const read_idx = self.read_idx.load(.acquire);

            const next_write_idx = calculate_next_index(self.buffer.len, write_idx);
            if (next_write_idx == read_idx) {
                return error.Full;
            }

            self.buffer[write_idx] = value;
            self.write_idx.store(next_write_idx, .release);
        }

        pub fn consume(self: *Self) ?T {
            const write_idx = self.write_idx.load(.acquire);
            const read_idx = self.read_idx.load(.monotonic);

            if (read_idx == write_idx) {
                return null;
            }

            const value = self.buffer[read_idx];
            const next_read_idx = calculate_next_index(self.buffer.len, read_idx);
            self.read_idx.store(next_read_idx, .release);

            return value;
        }
    };
}

fn calculate_next_index(capacity: usize, index: usize) usize {
    return if (index + 1 == capacity) 0 else index + 1;
}
