const builtin = @import("builtin");

pub const BoundedMpmcQueue = @import("bounded_queues/bounded_mpmc_queue.zig").BoundedMpmcQueue;
pub const BoundedMpscQueue = @import("bounded_queues/bounded_mpsc_queue.zig").BoundedMpscQueue;
pub const BoundedSpmcQueue = @import("bounded_queues/bounded_spmc_queue.zig").BoundedSpmcQueue;

pub const VyukovBoundedSpscQueue = @import("bounded_queues/vyukov_bounded_spsc_queue.zig").VyukovBoundedSpscQueue;
pub const RigtorpBoundedSpscQueue = @import("bounded_queues/rigtorp_bounded_spsc_queue.zig").RigtorpBoundedSpscQueue;

pub const BoundedSpscQueue = switch (builtin.cpu.arch) {
    .x86 => RigtorpBoundedSpscQueue, // TODO: test
    .x86_64 => RigtorpBoundedSpscQueue,
    .aarch64, .aarch64_be => VyukovBoundedSpscQueue,
    .arm => VyukovBoundedSpscQueue, // TODO: test
    else => RigtorpBoundedSpscQueue,
};

pub const BoundedMpmcMutexQueue = @import("bounded_queues/bounded_mpmc_mutex_queue.zig").BoundedMpmcMutexQueue;
