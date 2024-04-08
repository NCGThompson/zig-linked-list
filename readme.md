I got a school assignment that required implementing a linked list in a systems
language, so I decided to try out Zig.

I triet to code in a way idiomatic to Zig. For example, the main struct has
`init` that takes a reference to an allocator as a prameter. Still though, the resulting
struct is a de facto class.

To try out, first [install Zig](https://ziglang.org/learn/getting-started/#installing-zig).
Then, open a shell at the repository root and run the tests with.
``` sh
zig build test
```
To both generate the documentation and build the object files, run:
``` sh
zig build-lib -D optimize=ReleaseSafe src/main.zig -femit-docs
```
The documentation entry point will be at `docs/index.html`.

Basic usage:
```
const std = @import("std");
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var my_list = LinkedList(i64).init(&allocator);
defer my_list.deinit();

my_list.push_tail(5);
my_list.push_head(3);
my_list.insert_at(4, 1);
my_list.insert_at(6, my_list.len);

for (0..my_list.len) |_| {
    std.debug.print("{s}\n", .{my_list.pop_head()});
}
```
