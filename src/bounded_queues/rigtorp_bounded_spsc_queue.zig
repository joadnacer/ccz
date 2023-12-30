const std = @import("std");
const utils = @import("utils.zig");
const testing = std.testing;
const assert = std.debug.assert;
const Atomic = std.atomic.Atomic;
const Ordering = std.atomic.Ordering;

const cache_line = std.atomic.cache_line;

// TODO: modify to not use extra space

/// Array based bounded single producer single consumer queue
/// This is a zig port of Rigtorp's https://rigtorp.se/ringbuffer/ | TODO: with no empty slot
pub fn RigtorpBoundedSpscQueue(comptime T: type, comptime buffer_size: usize) type {
    assert(utils.isPowerOfTwo(buffer_size));

    const buffer_mask = buffer_size - 1;

    return struct {
        write_idx: Atomic(usize) align(cache_line),
        cached_write_idx: usize align(cache_line),
        read_idx: Atomic(usize) align(cache_line),
        cached_read_idx: usize align(cache_line),
        buffer: [buffer_size]T,

        const Self = @This();

        pub fn init() RigtorpBoundedSpscQueue(T, buffer_size) {
            return .{
                .write_idx = Atomic(usize).init(0),
                .cached_write_idx = 0,
                .read_idx = Atomic(usize).init(0),
                .cached_read_idx = 0,
                .buffer = undefined,
            };
        }

        /// Attempts to write to the queue, without overwriting any data
        /// Returns `true` if the data is written, `false` if the queue was full
        pub fn offer(self: *Self, data: T) bool {
            const write_idx = self.write_idx.load(Ordering.Monotonic);
            const next_write_idx = (write_idx + 1) & buffer_mask;

            if (next_write_idx == self.cached_read_idx) {
                self.cached_read_idx = self.read_idx.load(Ordering.Acquire);

                if (next_write_idx == self.cached_read_idx) return false;
            }

            self.buffer[write_idx] = data;
            self.write_idx.store(next_write_idx, Ordering.Release);

            return true;
        }

        /// Attempts to read and remove the head element of the queue
        /// Returns `null` if there was no element to read
        pub fn poll(self: *Self) ?T {
            const read_idx = self.read_idx.load(Ordering.Monotonic);

            if (read_idx == self.cached_write_idx) {
                self.cached_write_idx = self.write_idx.load(Ordering.Acquire);

                if (read_idx == self.cached_write_idx) return null;
            }

            const res = self.buffer[read_idx];
            const next_read_idx = (read_idx + 1) & buffer_mask;
            self.read_idx.store(next_read_idx, Ordering.Release);

            return res;
        }

        /// Attempts to read the head element of the queue, without removing it
        /// Returns `null` if there was no element to read
        pub fn peek(self: *Self) ?T {
            const read_idx = self.read_idx.load(Ordering.Monotonic);

            if (read_idx == self.cached_write_idx) {
                self.cached_write_idx = self.write_idx.load(Ordering.Acquire);

                if (read_idx == self.cached_write_idx) return null;
            }

            return self.buffer[read_idx];
        }
    };
}

test "offer/poll" {
    var queue = RigtorpBoundedSpscQueue(u64, 16).init();

    _ = queue.offer(17);
    _ = queue.offer(36);

    try testing.expect(queue.poll().? == 17);
    try testing.expect(queue.poll().? == 36);
}

test "offer/peek/poll" {
    var queue = RigtorpBoundedSpscQueue(u64, 16).init();

    _ = queue.offer(17);
    _ = queue.offer(36);

    try testing.expect(queue.peek().? == 17);
    try testing.expect(queue.poll().? == 17);
    try testing.expect(queue.poll().? == 36);
}

test "peek/poll empty" {
    var queue = RigtorpBoundedSpscQueue(u64, 16).init();

    try testing.expect(queue.peek() == null);
    try testing.expect(queue.poll() == null);
}

test "peek/poll emptied" {
    var queue = RigtorpBoundedSpscQueue(u64, 2).init();

    _ = queue.offer(1);
    _ = queue.offer(2);

    try testing.expect(queue.poll().? == 1);
    try testing.expect(queue.poll().? == 2);
    try testing.expect(queue.poll() == null);
}

test "offer to full" {
    var queue = RigtorpBoundedSpscQueue(u64, 2).init();

    _ = queue.offer(1);
    _ = queue.offer(2);

    try testing.expect(queue.offer(3) == false);
    try testing.expect(queue.poll().? == 1);
    try testing.expect(queue.poll().? == 2);
}
