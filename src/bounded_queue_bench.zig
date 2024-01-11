const std = @import("std");
const ccz = @import("ccz.zig");

const total_rounds = 100_000_000;
const buffer_capacity = 8192;

const BoundedMpmcQueue = ccz.BoundedMpmcQueue(u64, buffer_capacity);
const BoundedMpscQueue = ccz.BoundedMpscQueue(u64, buffer_capacity);
const BoundedSpmcQueue = ccz.BoundedSpmcQueue(u64, buffer_capacity);
const BoundedSpscQueue = ccz.VyukovBoundedSpscQueue(u64, buffer_capacity); // TODO: bench both
const BoundedMpmcMutexQueue = ccz.BoundedMpmcMutexQueue(u64, buffer_capacity);

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    const num_args = args.len - 1;

    if (num_args == 0) return try bench(1);

    for (0..num_args) |i| {
        const num_threads = try std.fmt.parseInt(u32, args[i + 1], 10);

        try bench(num_threads);
    }
}

fn bench(num_threads: u32) !void {
    try std.io.getStdOut().writer().print("=== Num Threads={} ===\n", .{num_threads});

    try mpmc_queue_bench(num_threads);

    try mpsc_queue_bench(num_threads);

    // this bench currently requires all consumers to read same amount of data
    try spmc_queue_bench(num_threads);

    try spsc_queue_bench();

    try mpmc_mutex_queue_bench(num_threads);
}

// Benchmarks would be a lot more concise if using a BoundedQueue interface to avoid code duplication
// but zig interfaces unfortunately cause a performance hit (significant on SPSC benchmark)
// Worth revisiting in the future
fn mpmc_queue_bench(num_threads: u32) !void {
    var queue = BoundedMpmcQueue.init();

    var workers: []std.Thread = try std.heap.page_allocator.alloc(std.Thread, num_threads * 2);

    defer std.heap.page_allocator.free(workers);

    const begin_time = std.time.nanoTimestamp();

    for (0..num_threads) |i| {
        workers[i] = try std.Thread.spawn(.{}, mpmcWriteWorker, .{ &queue, total_rounds / num_threads });
    }

    for (num_threads..num_threads * 2) |i| {
        workers[i] = try std.Thread.spawn(.{}, mpmcReadWorker, .{ &queue, total_rounds / num_threads });
    }

    for (0..num_threads * 2) |i| workers[i].join();

    const end_time = std.time.nanoTimestamp();

    try std.io.getStdOut().writer().print("time={d: >10.2}us test=mpmc_queue num_write_threads={} num_read_threads={}\n", .{
        @as(f32, @floatFromInt(end_time - begin_time)) / 1000.0, num_threads, num_threads,
    });
}

fn mpmcWriteWorker(queue: *BoundedMpmcQueue, t_rounds: u32) !void {
    var round: u64 = 0;

    while (round < t_rounds) {
        var res = queue.offer(round);

        while (!res) {
            res = queue.offer(round);
        }

        round += 1;
    }
}

fn mpmcReadWorker(queue: *BoundedMpmcQueue, t_rounds: u32) !void {
    var rounds = t_rounds;

    while (rounds > 0) {
        const res = queue.poll();

        if (res != null) {
            rounds -= 1;
        }
    }
}

fn mpsc_queue_bench(num_write_threads: u32) !void {
    var queue = BoundedMpscQueue.init();

    var workers: []std.Thread = try std.heap.page_allocator.alloc(std.Thread, num_write_threads + 1);

    defer std.heap.page_allocator.free(workers);

    const begin_time = std.time.nanoTimestamp();

    for (0..num_write_threads) |i| {
        workers[i] = try std.Thread.spawn(.{}, mpscWriteWorker, .{ &queue, total_rounds / num_write_threads });
    }

    workers[num_write_threads] = try std.Thread.spawn(.{}, mpscReadWorker, .{ &queue, (total_rounds / num_write_threads) * num_write_threads });

    for (0..num_write_threads + 1) |i| workers[i].join();

    const end_time = std.time.nanoTimestamp();

    try std.io.getStdOut().writer().print("time={d: >10.2}us test=mpsc_queue num_write_threads={} num_read_threads=1\n", .{
        @as(f32, @floatFromInt(end_time - begin_time)) / 1000.0, num_write_threads,
    });
}

fn mpscWriteWorker(queue: *BoundedMpscQueue, t_rounds: u32) !void {
    var round: u64 = 0;

    while (round < t_rounds) {
        var res = queue.offer(round);

        while (!res) {
            res = queue.offer(round);
        }

        round += 1;
    }
}

fn mpscReadWorker(queue: *BoundedMpscQueue, t_rounds: u32) !void {
    var rounds = t_rounds;

    while (rounds > 0) {
        const res = queue.poll();

        if (res != null) {
            rounds -= 1;
        }
    }
}

fn spmc_queue_bench(num_read_threads: u32) !void {
    var queue = BoundedSpmcQueue.init();

    var workers: []std.Thread = try std.heap.page_allocator.alloc(std.Thread, num_read_threads * 2);

    defer std.heap.page_allocator.free(workers);

    const begin_time = std.time.nanoTimestamp();

    workers[0] = try std.Thread.spawn(.{}, spmcWriteWorker, .{ &queue, (total_rounds / num_read_threads) * num_read_threads });

    for (1..num_read_threads + 1) |i| {
        workers[i] = try std.Thread.spawn(.{}, spmcReadWorker, .{ &queue, total_rounds / num_read_threads });
    }

    for (0..num_read_threads + 1) |i| workers[i].join();

    const end_time = std.time.nanoTimestamp();

    try std.io.getStdOut().writer().print("time={d: >10.2}us test=spmc_queue num_write_threads=1 num_read_threads={}\n", .{
        @as(f32, @floatFromInt(end_time - begin_time)) / 1000.0, num_read_threads,
    });
}

fn spmcWriteWorker(queue: *BoundedSpmcQueue, t_rounds: u32) !void {
    var round: u64 = 0;

    while (round < t_rounds) {
        var res = queue.offer(round);

        while (!res) {
            res = queue.offer(round);
        }

        round += 1;
    }
}

fn spmcReadWorker(queue: *BoundedSpmcQueue, t_rounds: u32) !void {
    var rounds = t_rounds;

    while (rounds > 0) {
        const res = queue.poll();

        if (res != null) {
            rounds -= 1;
        }
    }
}

fn spsc_queue_bench() !void {
    var queue = BoundedSpscQueue.init();

    var workers: []std.Thread = try std.heap.page_allocator.alloc(std.Thread, 2);

    defer std.heap.page_allocator.free(workers);

    const begin_time = std.time.nanoTimestamp();

    workers[0] = try std.Thread.spawn(.{}, spscWriteWorker, .{ &queue, total_rounds });
    workers[1] = try std.Thread.spawn(.{}, spscReadWorker, .{ &queue, total_rounds });

    for (0..2) |i| workers[i].join();

    const end_time = std.time.nanoTimestamp();

    try std.io.getStdOut().writer().print("time={d: >10.2}us test=spsc_queue num_write_threads=1 num_read_threads=1\n", .{
        @as(f32, @floatFromInt(end_time - begin_time)) / 1000.0,
    });
}

fn spscWriteWorker(queue: *BoundedSpscQueue, t_rounds: u32) !void {
    var round: u64 = 0;

    while (round < t_rounds) {
        var res = queue.offer(round);

        while (!res) {
            res = queue.offer(round);
        }

        round += 1;
    }
}

fn spscReadWorker(queue: *BoundedSpscQueue, t_rounds: u32) !void {
    var rounds = t_rounds;

    while (rounds > 0) {
        const res = queue.poll();

        if (res != null) {
            rounds -= 1;
        }
    }
}

fn mpmc_mutex_queue_bench(num_threads: u32) !void {
    var queue = BoundedMpmcMutexQueue.init();

    var workers: []std.Thread = try std.heap.page_allocator.alloc(std.Thread, num_threads * 2);

    defer std.heap.page_allocator.free(workers);

    const begin_time = std.time.nanoTimestamp();

    for (0..num_threads) |i| {
        workers[i] = try std.Thread.spawn(.{}, mpmcMutexWriteWorker, .{ &queue, total_rounds / num_threads });
    }

    for (num_threads..num_threads * 2) |i| {
        workers[i] = try std.Thread.spawn(.{}, mpmcMutexReadWorker, .{ &queue, total_rounds / num_threads });
    }

    for (0..num_threads * 2) |i| workers[i].join();

    const end_time = std.time.nanoTimestamp();

    try std.io.getStdOut().writer().print("time={d: >10.2}us test=mpmc_mutex_queue num_write_threads={} num_read_threads={}\n", .{
        @as(f32, @floatFromInt(end_time - begin_time)) / 1000.0, num_threads, num_threads,
    });
}

fn mpmcMutexWriteWorker(queue: *BoundedMpmcMutexQueue, t_rounds: u32) !void {
    var round: u64 = 0;

    while (round < t_rounds) {
        var res = queue.offer(round);

        while (!res) {
            res = queue.offer(round);
        }

        round += 1;
    }
}

fn mpmcMutexReadWorker(queue: *BoundedMpmcMutexQueue, t_rounds: u32) !void {
    var rounds = t_rounds;

    while (rounds > 0) {
        const res = queue.poll();

        if (res != null) {
            rounds -= 1;
        }
    }
}
