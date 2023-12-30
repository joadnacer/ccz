const std = @import("std");
const utils = @import("utils.zig");
const testing = std.testing;
const assert = std.debug.assert;
const Mutex = std.Thread.Mutex;
const Atomic = std.atomic.Atomic;
const Ordering = std.atomic.Ordering;

const cache_line = std.atomic.cache_line;

// TODO: can maybe be done better without using count? as has to be synchronized
// can maybe use cell seq numbers as in other ones? or optional for null

pub fn BoundedMpmcMutexQueue(comptime T: type, comptime buffer_size: usize) type {
    assert(utils.isPowerOfTwo(buffer_size));

    const buffer_mask = buffer_size - 1;

    return struct {
        write_index: usize align(cache_line),
        write_mutex: Mutex align(cache_line),
        read_index: usize align(cache_line),
        read_mutex: Mutex align(cache_line),
        count: Atomic(usize),
        buffer: [buffer_size]T,

        const Self = @This();

        pub fn init() BoundedMpmcMutexQueue(T, buffer_size) {
            return .{
                .write_index = 0,
                .write_mutex = .{},
                .read_index = 0,
                .read_mutex = .{},
                .count = Atomic(usize).init(0),
                .buffer = undefined,
            };
        }

        /// Attempts to write to the queue, without overwriting any data
        /// Returns `true` if the data is written, `false` if the queue was full
        pub fn offer(self: *Self, data: T) bool {
            self.write_mutex.lock();
            defer self.write_mutex.unlock();

            if (self.count.load(Ordering.Monotonic) == buffer_size) return false;

            self.buffer[self.write_index] = data;
            self.write_index = (self.write_index + 1) & buffer_mask;
            _ = self.count.fetchAdd(1, Ordering.Monotonic);

            return true;
        }

        /// Attempts to read and remove the head element of the queue
        /// Returns `null` if there was no element to read
        pub fn poll(self: *Self) ?T {
            self.read_mutex.lock();
            defer self.read_mutex.unlock();

            if (self.count.load(Ordering.Monotonic) == 0) return null;

            const res = self.buffer[self.read_index];
            self.read_index = (self.read_index + 1) & buffer_mask;
            _ = self.count.fetchSub(1, Ordering.Monotonic);

            return res;
        }

        /// Attempts to read the head element of the queue, without removing it
        /// Returns `null` if there was no element to read
        pub fn peek(self: *Self) ?T {
            self.read_mutex.lock();
            defer self.read_mutex.unlock();

            if (self.count.load(Ordering.Monotonic) == 0) return null;

            return self.buffer[self.read_index];
        }
    };
}

test "offer/poll" {
    var queue = BoundedMpmcMutexQueue(u64, 16).init();

    _ = queue.offer(17);
    _ = queue.offer(36);

    try testing.expect(queue.poll().? == 17);
    try testing.expect(queue.poll().? == 36);
}

test "offer/peek/poll" {
    var queue = BoundedMpmcMutexQueue(u64, 16).init();

    _ = queue.offer(17);
    _ = queue.offer(36);

    try testing.expect(queue.peek().? == 17);
    try testing.expect(queue.poll().? == 17);
    try testing.expect(queue.poll().? == 36);
}

test "peek/poll empty" {
    var queue = BoundedMpmcMutexQueue(u64, 16).init();

    try testing.expect(queue.peek() == null);
    try testing.expect(queue.poll() == null);
}

test "peek/poll emptied" {
    var queue = BoundedMpmcMutexQueue(u64, 2).init();

    _ = queue.offer(1);
    _ = queue.offer(2);

    try testing.expect(queue.poll().? == 1);
    try testing.expect(queue.poll().? == 2);
    try testing.expect(queue.poll() == null);
}

test "offer to full" {
    var queue = BoundedMpmcMutexQueue(u64, 2).init();

    _ = queue.offer(1);
    _ = queue.offer(2);

    try testing.expect(queue.offer(3) == false);
    try testing.expect(queue.poll().? == 1);
    try testing.expect(queue.poll().? == 2);
}
