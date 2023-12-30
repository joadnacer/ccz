const std = @import("std");
const Atomic = std.atomic.Atomic;
const Ordering = std.atomic.Ordering;

pub inline fn isPowerOfTwo(n: usize) bool {
    return n & (n - 1) == 0;
}

pub inline fn tryCASAddOne(atomic_ptr: *Atomic(usize), val: usize, success_ordering: Ordering) ?usize {
    return atomic_ptr.tryCompareAndSwap(val, val + 1, success_ordering, Ordering.Monotonic);
}
