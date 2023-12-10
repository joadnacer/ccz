### Concurrent Collections for Zig

A hopefully growing library of zig concurrent collections.

Benchmarks can be run as follows:
`zig run -O ReleaseFast src/[benchmark_file.zig] -- [num_threads...]`

For example:
`zig run -O ReleaseFast src/bounded_queue_bench.zig -- 1 5 10 100`

Note that the num_threads arguments will only be applied where possible - for example in `bounded_queue_bench`, this will only be applied to the MPSC queue's producers and not to its consumers.