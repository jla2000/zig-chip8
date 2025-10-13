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

        /// Returns the amount of currently stored elements
        /// Must be called only from the producer thread.
        pub fn producer_fill(self: Self) usize {
            const write_idx = self.write_idx.load(.monotonic);
            const read_idx = self.read_idx.load(.acquire);

            if (write_idx >= read_idx) {
                return write_idx - read_idx;
            } else {
                return self.buffer.len - read_idx + write_idx;
            }
        }

        /// Returns the amount of currently stored elements
        /// Must be called only from the consumer thread.
        pub fn consumer_fill(self: Self) usize {
            const write_idx = self.write_idx.load(.acquire);
            const read_idx = self.read_idx.load(.monotonic);

            if (write_idx >= read_idx) {
                return write_idx - read_idx;
            } else {
                return self.buffer.len - read_idx + write_idx;
            }
        }

        /// Returns the amount of elements that can be stored.
        pub fn capacity(self: Self) usize {
            return self.buffer.len - 1;
        }
    };
}

/// Helper function to advance reader/writer and handle wrap around.
fn calculate_next_index(capacity: usize, index: usize) usize {
    return if (index + 1 == capacity) 0 else index + 1;
}

test "ring buffer len" {
    var mem = std.mem.zeroes([17]usize);
    var ring = RingBuffer(usize).init(&mem);

    std.debug.assert(ring.producer_fill() == 0);

    for (0..1024) |i| {
        ring.produce(i) catch unreachable;
        ring.produce(i + 1) catch unreachable;

        std.debug.assert(ring.producer_fill() == 2);
        std.debug.assert(ring.consume().? == i);
        std.debug.assert(ring.producer_fill() == 1);
        std.debug.assert(ring.consume().? == i + 1);
        std.debug.assert(ring.producer_fill() == 0);
    }
}
