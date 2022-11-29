const std = @import("std");

// NOTE: In smart contract context don't really have to free memory before execution ends
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();

// Import host functions provided by NEAR runtime.
// See https://github.com/near/near-sdk-rs/blob/78c16447486285fd952765ef3e727e16d6c8c867/near-sdk/src/environment/env.rs#L117
extern fn input(register_id: u64) void;
extern fn read_register(register_id: u64, ptr: u64) void;
extern fn register_len(register_id: u64) u64;
extern fn value_return(value_len: u64, value_ptr: u64) void;
extern fn log_utf8(len: u64, ptr: u64) void;

// Helper wrapper functions for interacting with the host
fn log(str: []const u8) void {
    log_utf8(str.len, @ptrToInt(str.ptr));
}

fn valueReturn(value: []const u8) void {
    value_return(value.len, @ptrToInt(value.ptr));
}

fn readRegisterAlloc(register_id: u64) []u8 {
    const len = @truncate(usize, register_len(register_id));
    // TODO: Explicit NEAR-compatible panic instead of unreachable?
    const bytes = allocator.alloc(u8, len) catch unreachable;
    read_register(register_id, @ptrToInt(bytes.ptr));
    return bytes;
}

fn base64EncodeAlloc(data: []const u8) []const u8 {
    const encoder = std.base64.standard.Encoder;
    const dataSize = encoder.calcSize(data.len);
    const dataBuffer = allocator.alloc(u8, dataSize) catch unreachable;
    return encoder.encode(dataBuffer, data);
}

fn joinAlloc(parts: anytype) []const u8 {
    var totalSize: usize = 0;
    inline for (parts) |part| {
        totalSize += part.len;
    }
    const result = allocator.alloc(u8, totalSize) catch unreachable;
    var offset: usize = 0;
    inline for (parts) |part| {
        std.mem.copy(u8, result[offset..offset + part.len], part);
        offset += part.len;
    }
    return result;
}

// Main entry point for web4 contract.
export fn web4_get() void {
    // Store method arguments blob in a register 0
    input(0);

    // Read method arguments blob from register 0
    const inputData = readRegisterAlloc(0);

    // Parse method arguments JSON
    // NOTE: Parsing using TokenStream results in smaller binary than deserializing into object
    var requestStream = std.json.TokenStream.init(inputData);
    var lastString: [] const u8 = "";
    var path = while (requestStream.next() catch unreachable) |token| {
        switch (token) {
            .String => |stringToken| {
                const str = stringToken.slice(requestStream.slice, requestStream.i - 1);
                if (std.mem.eql(u8, lastString, "path")) {
                    break str;
                }
                lastString = str;
            },
            else => {},
        }
    } else "/";

    // Log request path
    log(joinAlloc(.{"path: ", path}));

    // Render response
    const body = joinAlloc(.{"Hello from <b>", path, "</b>!"});

    // Construct response object
    const base64Body = base64EncodeAlloc(body);
    const responseData = joinAlloc(.{
        \\{
        \\  "status": 200,
        \\  "contentType": "text/html",
        \\  "body":
        , "\"",
        base64Body,
        "\"",
        \\ }
    });

    // Return method result
    valueReturn(responseData);
}
