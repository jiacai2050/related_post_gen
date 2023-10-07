const std = @import("std");

const Post = struct { _id: []const u8, title: []const u8, tags: [][]const u8 };
const Posts = []Post;
const TopPosts = struct { _id: *const []const u8, tags: *const [][]const u8, related: []*Post };
const PostsWithSharedTag = struct { post: usize, tags: usize };
const stdout = std.io.getStdOut().writer();

fn lessthan(context: void, lhs: usize, rhs: usize) bool {
    _ = context;
    return lhs < rhs;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file = try std.fs.cwd().openFile("../posts.json", .{});
    defer file.close();
    const ArrPosts = std.ArrayList(usize);
    var map = std.StringHashMap(ArrPosts).init(allocator);
    var json_reader = std.json.reader(allocator, file.reader());
    const parsed = try std.json.parseFromTokenSource(Posts, allocator, &json_reader, .{});

    const start = try std.time.Instant.now();

    for (parsed.value, 0..) |post_ele, i| {
        for (post_ele.tags) |tag| {
            var get_or_put = try map.getOrPut(tag);
            if (get_or_put.found_existing) {
                try get_or_put.value_ptr.*.append(i);
            } else {
                var temp = ArrPosts.init(allocator);
                try temp.append(i);
                get_or_put.value_ptr.* = temp;
            }
        }
    }

    var op = try std.ArrayList(TopPosts).initCapacity(allocator, parsed.value.len);
    var tagged_post_count: []usize = try allocator.alloc(usize, parsed.value.len);

    for (parsed.value, 0..) |post, post_index| {
        // reset tagged_post_count
        @memset(tagged_post_count, 0);

        for (post.tags) |tag| {
            for (map.get(tag).?.items) |i_t| {
                tagged_post_count[i_t] += 1;
            }
        }

        tagged_post_count[post_index] = 0; // Don't count self

        var top_5 = [_]PostsWithSharedTag{.{ .post = 0, .tags = 0 }} ** 5;
        var min_tags: usize = 0;
        for (tagged_post_count, 0..) |count, j| {
            if (count > min_tags) {

                // Find the position to insert
                var pos: usize = 0;
                while (top_5[pos].tags >= count) {
                    pos += 1;
                }

                std.mem.copyForwards(PostsWithSharedTag, top_5[pos + 1 ..], top_5[pos .. top_5.len - 1]);
                top_5[pos] = PostsWithSharedTag{ .post = j, .tags = count };
                min_tags = top_5[4].tags;
            }
        }

        // Convert indexes back to Post pointers
        var top_posts = [_]*Post{undefined} ** 5;

        var i: usize = 0;
        for (top_5) |tagged_post| {
            if (tagged_post.tags == 0) {
                continue;
            }
            top_posts[i] = &parsed.value[tagged_post.post];
            i += 1;
        }

        try op.append(.{ ._id = &post._id, .tags = &post.tags, .related = top_posts[0..i] });
    }
    const end = try std.time.Instant.now();
    try stdout.print("Processing time (w/o IO): {d}ms\n", .{@divFloor(end.since(start), std.time.ns_per_ms)});

    const op_file = try std.fs.cwd().createFile("../related_posts_zig.json", .{});
    defer op_file.close();
    var buffered_writer = std.io.bufferedWriter(op_file.writer());
    try std.json.stringify(try op.toOwnedSlice(), .{}, buffered_writer.writer());
    try buffered_writer.flush();
}
