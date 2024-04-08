const std = @import("std");
const testing = std.testing;

/// A generic doubly-linked list implementation containing values of type T
///
/// Basic usage:
/// ```
/// const std = @import("std");
/// var gpa = std.heap.GeneralPurposeAllocator(.{}){};
/// const allocator = gpa.allocator();
///
/// var my_list = LinkedList(i64).init(&allocator);
/// defer my_list.deinit();
///
/// my_list.push_tail(5);
/// my_list.push_head(3);
/// my_list.insert_at(4, 1);
/// my_list.insert_at(6, my_list.len);
///
/// for (0..my_list.len) |_| {
///     std.debug.print("{s}\n", .{my_list.pop_head()});
/// }
/// ```
///
/// This struct is intended to be interacted with through its public methods.
/// The only field that should be used externally is `len`, and it should
/// only be read, not written to. Assuming no fields are modified, the only
/// known way to break it is with an out of bounds index.
pub fn LinkedList(comptime T: type) type {
    return struct {
        allocator: *const std.mem.Allocator,
        head: ?*Node(T),
        tail: ?*Node(T),
        len: usize,
        seek_pointer: ?*Node(T),
        seek_index: usize,

        pub fn init(allocator: *const std.mem.Allocator) LinkedList(T) {
            return LinkedList(T){
                .allocator = allocator,
                .head = null,
                .tail = null,
                .len = 0,
                .seek_pointer = null,
                .seek_index = 0,
            };
        }

        /// Remove all contained values and free all memory.
        /// After running this function, it is safe to run `init` again.
        /// If T has a destroy method itself, consider `deinit_with`
        pub fn deinit(self: *LinkedList(T)) void {
            self.deinit_with(struct {
                fn lambda(_: *T) void {}
            }.lambda);
        }

        /// Same as `deinit` but executes a function on each contained value.
        /// Useful if T itself owns memory that needs to be freed.
        pub fn deinit_with(self: *LinkedList(T), comptime destroyer: fn (value: *T) void) void {
            var next = self.head;
            while (next) |ptr| {
                next = ptr.next;
                destroyer(&ptr.value);
                self.allocator.destroy(ptr);
            }
            self.head = null;
            self.tail = null;
            self.len = 0;
            self.seek_pointer = null;
            self.seek_index = 0;
        }

        /// `my_list.push_head(new_value)` is equivalent to `my_list.insert_at(new_value, 0)`.
        pub fn push_head(self: *LinkedList(T), value: T) !void {
            const new = Node(T).init_heap(value, self.allocator) catch |err| return err;
            if (self.head) |old| {
                old.prev = new;
                new.next = old;
            } else {
                self.tail = new;
            }
            self.head = new;
            self.len += 1;
            self.index_if_some(self.seek_index + 1);
        }

        /// `my_list.push_head(new_value)` is equivalent to `my_list.insert_at(new_value, my_list.len)`.
        pub fn push_tail(self: *LinkedList(T), value: T) !void {
            const new = Node(T).init_heap(value, self.allocator) catch |err| return err;
            if (self.tail) |old| {
                old.next = new;
                new.prev = old;
            } else {
                self.head = new;
            }
            self.tail = new;

            self.len += 1;
        }

        /// Caller must ensure index <= len.
        pub fn insert_at(self: *LinkedList(T), value: T, index: usize) !void {
            if (index > self.len) {
                return;
            } else if (index == self.len) {
                self.push_tail(value);
                return;
            }

            const old: *Node(T) = self.find(index);
            const prev_next = if (old.prev) |prev| {
                prev.next;
            } else {
                debug_assert(index == 0);
                self.head;
            };

            const new = Node(T).init_heap(value, self.allocator) catch |err| return err;

            old.prev = new;
            prev_next = new;
            new.next = old;
            new.prev = old.prev;

            self.len += 1;
            if (self.seek_pointer != null and self.seek_index >= index) {
                self.seek_index += 1;
            }
        }

        /// `my_list.pop_head()` is equivalent to `my_list.pop_at(0)`.
        ///
        /// Caller must ensure len > 0.
        pub fn pop_head(self: *LinkedList(T)) T {
            const node = self.head.?;

            if (self.seek_pointer == node) {
                self.seek_pointer = null;
            }

            if (node.next) |next| {
                next.prev = null;
            } else {
                self.tail = null;
            }
            self.head = node.next;

            self.len -= 1;
            if (self.seek_pointer != null) {
                self.seek_index -= 1;
            }

            const out = node.value;
            self.allocator.destroy(node);
            return out;
        }

        /// `my_list.pop_tail()` is equivalent to `my_list.pop_at(my_list.len)`.
        ///
        /// Caller must ensure len > 0.
        pub fn pop_tail(self: *LinkedList(T)) T {
            const node = self.tail.?;

            if (self.seek_pointer == node) {
                self.seek_pointer = null;
            }

            if (node.prev) |prev| {
                prev.next = null;
                self.tail = prev;
            } else {
                self.head = null;
                self.tail = null;
            }

            self.len -= 1;

            const out = node.value;
            self.allocator.destroy(node);
            return out;
        }

        /// Caller must ensure index < len.
        pub fn pop_at(self: *LinkedList(T), index: usize) T {
            const node = self.find(index);

            if (node.prev) |prev| {
                prev.next = null;
            } else {
                self.head = null;
            }
            if (node.next) |next| {
                next.prev = null;
            } else {
                self.tail = null;
            }

            self.len -= 1;
            if (self.seek_pointer != null and self.seek_index > index) {
                self.seek_index -= 1;
            }

            const out = node.value;
            self.allocator.destroy(node);
            return out;
        }

        /// Caller must ensure index < len.
        ///
        /// Lifetime: Methods rearranging list items don't physically
        /// move the items in memory, so pointers are valid as long as the
        /// item remains in the list.
        pub fn get(self: *LinkedList(T), index: usize) *T {
            const node = self.find(index).?;
            return &node.value;
        }

        /// Overwrite the existing value at the index, and return the old value.
        ///
        /// This is just an abstraction around `get`, which may be preffered
        /// preffered for some uses.
        pub fn update(self: *LinkedList(T), value: T, index: usize) T {
            const target = self.get(index);
            const old = target.*;
            target.* = value;
            return old;
        }

        /// In adition to the "head" of the list and the "tail" of the
        /// list, the struct can have a third index/pointer pair to use
        /// as a bookmark. When querying a specific index with a method,
        /// the method will find the closest "bookmark" to start from.
        ///
        /// This function does not effect behavior in any way, but could
        /// improve performance when doing bulk operations on big lists.
        /// If you wan't to get the sum of all list items for example,
        /// this would be the simplest way but completes in O(len^2) time:
        /// ```
        /// var sum = 0;
        /// for (0..my_list.len) |i| {
        ///     sum += my_list.get(i).*;
        /// }
        /// ```
        /// while this should complete in O(len) time:
        /// ```
        /// var sum = 0;
        /// for (0..my_list.len) |i| {
        ///     my_list.seek_to(i);
        ///     sum += my_list.get(i).*;
        /// }
        /// ```
        /// Note that removing the item the "bookmark" is on will reset
        /// the bookmark:
        /// ```
        /// my_list.seek_to(i);
        /// _ = my_list.pop_at(i);
        /// ```
        pub fn seek_to(self: *LinkedList(T), index: usize) void {
            self.seek_pointer = self.find(index);
            self.seek_index = index;
        }

        /// true is good, false is bad.
        pub fn validate(self: *LinkedList(T)) bool {
            if (self.len == 0) {
                return self.head == null and self.tail == null and self.seek_pointer == null;
            }

            var node = if (self.head) |next| next else return false;
            for (0..self.len - 1) |i| {
                if (self.seek_pointer != null and self.seek_index == i and
                    self.seek_pointer != node)
                {
                    return false;
                }
                node = if (node.next) |next| next else return false;
            }

            if (self.seek_pointer != null) {
                if (self.seek_index >= self.len or
                    (self.seek_index == self.len - 1 and self.seek_pointer != node))
                {
                    return false;
                }
            }

            return node.next == null and self.tail == node;
        }

        fn find(self: *const LinkedList(T), index: usize) ?*Node(T) {
            if (index >= self.len) {
                return null;
            }

            // Determine the fastest way to get to the index
            const si = if (self.seek_pointer != null) self.seek_index else std.math.maxInt(usize);
            const comp_arr = [4]usize{
                index,
                self.len - 1 - index,
                index -% si,
                si -% index,
            };
            const min_index = std.mem.indexOfMin(usize, &comp_arr);
            const min_value = comp_arr[min_index];

            var node = if (min_index == 0)
                self.head.?
            else if (min_index == 1)
                self.tail.?
            else
                self.seek_pointer.?;

            if (min_index & 1 == 0) {
                for (0..min_value) |_| {
                    node = node.next.?;
                }
            } else {
                for (0..min_value) |_| {
                    node = node.prev.?;
                }
            }

            return node;
        }
    };
}

fn Node(comptime T: type) type {
    return struct {
        value: T,
        next: ?*Node(T),
        prev: ?*Node(T),

        fn init_heap(value: T, allocator: *const std.mem.Allocator) !*Node(T) {
            const out = allocator.create(Node(T)) catch |err| return err;
            out.* = Node(T){ .value = value, .next = null, .prev = null };
            return out;
        }
    };
}

/// Like assert, but does not produce undefined behavior.
/// Used to check that list len matches the head and tail states,
/// which isn't truely necessary for the functions to work.
///
/// Note that it takes a bool, not a function, but the evaluation of
/// the predicate will usually be elided in optimized builds.
fn debug_assert(ok: bool) void {
    if (std.debug.runtime_safety) {
        std.debug.assert(ok);
    }
}

test "initialization" {
    const alloc = std.testing.allocator;
    var a = LinkedList(usize).init(&alloc);

    try testing.expect(a.validate());
    try a.push_tail(5);
    try testing.expect(a.validate());
    a.deinit();
}

test "complex_type" {
    var alloc = std.testing.allocator;

    var a1 = LinkedList(usize).init(&alloc);
    try a1.push_tail(5);
    try testing.expect(a1.validate());

    var a2 = LinkedList(usize).init(&alloc);
    try a2.push_tail(4);
    try testing.expect(a2.validate());

    var b = LinkedList(LinkedList(usize)).init(&alloc);
    try testing.expect(b.validate());
    try b.push_tail(a1);
    try testing.expect(b.validate());
    try b.push_tail(a2);
    try testing.expect(b.validate());

    b.deinit_with(LinkedList(usize).deinit);
}

// This test intentionally sets the list to an invalid state
// so that the only way `find` can find find an index is if it takes
// the optimal path.
test "seeking" {
    var alloc = std.testing.allocator;

    var a = LinkedList(usize).init(&alloc);
    defer a.deinit();

    for (0..12) |i| {
        try a.push_tail(i);
    }

    try testing.expectEqual(@as(usize, 11), a.pop_tail());
    try testing.expect(a.validate());
    try testing.expectEqual(@as(usize, 11), a.len);

    a.seek_to(5);
    try testing.expectEqual(@as(usize, 5), a.seek_pointer.?.value);
    try testing.expectEqual(@as(usize, 5), a.seek_index);

    var separator1 = a.head.?.next.?.next.?;
    var separator2 = separator1.next.?;
    var separator4 = a.tail.?.prev.?.prev.?;
    var separator3 = separator4.prev.?;

    separator1.next = null;
    separator2.prev = null;
    separator3.next = null;
    separator4.prev = null;
    defer separator1.next = separator2; // Needed to dealloc later
    defer separator3.next = separator4;

    for (0..11) |i| {
        try testing.expectEqual(@as(usize, i), a.get(i).*);
    }
}
