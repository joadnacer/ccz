const std = @import("std");
const utils = @import("utils.zig");
const testing = std.testing;
const assert = std.debug.assert;
const Atomic = std.atomic.Atomic;
const Ordering = std.atomic.Ordering;

const cache_line = std.atomic.cache_line;

/// Array based bounded single producer single consumer queue
/// This is a modification of Dmitry Vyukov's https://www.1024cores.net/home/lock-free-algorithms/queues/bounded-mpmc-queue
pub fn VyukovBoundedSpscQueue(comptime T: type, comptime buffer_size: usize) type {
    assert(utils.isPowerOfTwo(buffer_size));

    const buffer_mask = buffer_size - 1;

    const Cell = struct {
        sequence: Atomic(usize),
        data: T,
    };

    return struct {
        enqueue_pos: usize align(cache_line),
        dequeue_pos: usize align(cache_line),
        buffer: [buffer_size]Cell,

        const Self = @This();

        pub fn init() VyukovBoundedSpscQueue(T, buffer_size) {
            var buf: [buffer_size]Cell = undefined;

            for (&buf, 0..) |*cell, i| {
                cell.sequence = Atomic(usize).init(i);
            }

            return .{
                .enqueue_pos = 0,
                .dequeue_pos = 0,
                .buffer = buf,
            };
        }

        /// Attempts to write to the queue, without overwriting any data
        /// Returns `true` if the data is written, `false` if the queue was full
        pub fn offer(self: *Self, data: T) bool {
            const cell = &self.buffer[self.enqueue_pos & buffer_mask];
            const seq = cell.sequence.load(Ordering.Acquire);
            const diff = @as(i128, seq) - @as(i128, self.enqueue_pos);

            if (diff == 0) {
                self.enqueue_pos += 1;
            } else {
                return false;
            }

            cell.data = data;
            cell.sequence.store(self.enqueue_pos, Ordering.Release); // TODO - check spsc ordering?

            return true;
        }

        /// Attempts to read and remove the head element of the queue
        /// Returns `null` if there was no element to read
        pub fn poll(self: *Self) ?T {
            const cell = &self.buffer[self.dequeue_pos & buffer_mask];
            const seq = cell.sequence.load(Ordering.Acquire);
            const diff = @as(i128, seq) - @as(i128, (self.dequeue_pos + 1));

            if (diff == 0) {
                self.dequeue_pos += 1;
            } else {
                return null;
            }

            cell.sequence.store(self.dequeue_pos + buffer_mask, Ordering.Release); // TODO - check spsc ordering?

            return cell.data;
        }

        /// Attempts to read the head element of the queue, without removing it
        /// Returns `null` if there was no element to read
        pub fn peek(self: *Self) ?T {
            const cell = &self.buffer[self.dequeue_pos & buffer_mask];
            const seq = cell.sequence.load(Ordering.Acquire);
            const diff = @as(i128, seq) - @as(i128, (self.dequeue_pos + 1));

            return if (diff == 0) cell.data else null;
        }
    };
}

test "offer/poll" {
    var queue = VyukovBoundedSpscQueue(u64, 16).init();

    _ = queue.offer(17);
    _ = queue.offer(36);

    try testing.expect(queue.poll().? == 17);
    try testing.expect(queue.poll().? == 36);
}

test "offer/peek/poll" {
    var queue = VyukovBoundedSpscQueue(u64, 16).init();

    _ = queue.offer(17);
    _ = queue.offer(36);

    try testing.expect(queue.peek().? == 17);
    try testing.expect(queue.poll().? == 17);
    try testing.expect(queue.poll().? == 36);
}

test "peek/poll empty" {
    var queue = VyukovBoundedSpscQueue(u64, 16).init();

    try testing.expect(queue.peek() == null);
    try testing.expect(queue.poll() == null);
}

test "peek/poll emptied" {
    var queue = VyukovBoundedSpscQueue(u64, 2).init();

    _ = queue.offer(1);
    _ = queue.offer(2);

    try testing.expect(queue.poll().? == 1);
    try testing.expect(queue.poll().? == 2);
    try testing.expect(queue.poll() == null);
}

test "offer to full" {
    var queue = VyukovBoundedSpscQueue(u64, 2).init();

    _ = queue.offer(1);
    _ = queue.offer(2);

    try testing.expect(queue.offer(3) == false);
    try testing.expect(queue.poll().? == 1);
    try testing.expect(queue.poll().? == 2);
}
