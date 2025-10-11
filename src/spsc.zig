const std = @import("std");

/// SPSC ring buffer implementation
pub fn RingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Aligned to a cache line to avoid false-sharing.
        write_idx: std.atomic.Value(usize) align(std.atomic.cache_line),
        /// Aligned to a cache line to avoid false-sharing.
        read_idx: std.atomic.Value(usize) align(std.atomic.cache_line),

        buffer: []T,

        /// Initialize using the given buffer.
        /// The last slot will be unused, so the caller should provide a buffer with `desired_capacity + 1` elements.
        pub fn init(buffer: []T) Self {
            return Self{
                .write_idx = std.atomic.Value(usize).init(0),
                .read_idx = std.atomic.Value(usize).init(0),
                .buffer = buffer,
            };
        }

        /// Provide a single value for consumption.
        /// If the ring buffer is full, an error is returned.
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

        /// Try to consume a single value.
        /// When nothing is available, `null` is returned.
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

/// Helper function to advance reader/writer and handle wrap around.
fn calculate_next_index(capacity: usize, index: usize) usize {
    return if (index + 1 == capacity) 0 else index + 1;
}
