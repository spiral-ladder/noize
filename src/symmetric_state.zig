//! Contains the implementation for the symmetric state object.
//!
//! See: http://www.noiseprotocol.org/noise.html#the-symmetricstate-object
const std = @import("std");

const BoundedArray = std.BoundedArray;
const Allocator = std.mem.Allocator;

const CipherState = @import("./cipher.zig").CipherState;
const CipherChoice = @import("./cipher.zig").CipherChoice;

const Hash = @import("hash.zig").Hash;
const MAXHASHLEN = @import("hash.zig").MAXHASHLEN;
const HashSha256 = @import("hash.zig").HashSha256;
const HashSha512 = @import("hash.zig").HashSha512;
const HashBlake2b = @import("hash.zig").HashBlake2b;
const HashBlake2s = @import("hash.zig").HashBlake2s;
const HashChoice = @import("hash.zig").HashChoice;

const Sha256 = std.crypto.hash.sha2.Sha256;
const ChaCha20Poly1305 = std.crypto.aead.chacha_poly.ChaCha20Poly1305;

const Protocol = struct {
    const Self = @This();

    pattern: []const u8,
    dh: []const u8,
    cipher: CipherChoice,
    hash: HashChoice,
};

// Constructs a `Protocol` from a `protocol_name` byte sequence.
pub fn protocolFromName(protocol_name: []const u8) Protocol {
    var split_it = std.mem.splitScalar(u8, protocol_name, '_');
    _ = split_it.next().?;
    const pattern = split_it.next().?;
    const dh = split_it.next().?;
    const cipher = std.meta.stringToEnum(CipherChoice, split_it.next().?).?;
    const hash = std.meta.stringToEnum(HashChoice, split_it.next().?).?;
    std.debug.assert(split_it.next() == null);

    return .{
        .pattern = pattern,
        .dh = dh,
        .cipher = cipher,
        .hash = hash,
    };
}

pub const SymmetricState = struct {
    allocator: Allocator,
    cipher_choice: [10]u8,
    cipher_state: CipherState,
    ck: BoundedArray(u8, MAXHASHLEN),
    h: BoundedArray(u8, MAXHASHLEN),

    hasher: Hasher,

    const Self = @This();

    const Hasher = struct {
        choice: HashChoice,
        len: usize,

        fn hash(self: *Hasher, input: []const u8) !BoundedArray(u8, MAXHASHLEN) {
            var out = BoundedArray(u8, MAXHASHLEN).init(0) catch unreachable;
            if (self.choice == .SHA256 or self.choice == .BLAKE2s) {
                const hash_out = switch (self.choice) {
                    .SHA256 => HashSha256.hash(input),
                    .BLAKE2s => HashBlake2s.hash(input),
                    else => @panic("Hash not set"),
                };
                try out.appendSlice(&hash_out);
            } else {
                const hash_out = switch (self.choice) {
                    .SHA512 => HashSha512.hash(input),
                    .BLAKE2b => HashBlake2b.hash(input),
                    else => @panic("Hash not set"),
                };
                try out.appendSlice(&hash_out);
            }

            return out;
        }

        fn HKDF(
            self: *Hasher,
            chaining_key: []const u8,
            input_key_material: []const u8,
            num_outputs: u8,
        ) !struct {
            BoundedArray(u8, MAXHASHLEN),
            BoundedArray(u8, MAXHASHLEN),
            ?BoundedArray(u8, MAXHASHLEN),
        } {
            std.debug.assert(chaining_key.len == self.len);
            std.debug.assert(input_key_material.len == 0 or input_key_material.len == 32);

            var out1 = BoundedArray(u8, MAXHASHLEN).init(0) catch unreachable;
            var out2 = BoundedArray(u8, MAXHASHLEN).init(0) catch unreachable;
            var out3: ?BoundedArray(u8, MAXHASHLEN) = if (num_outputs == 3) BoundedArray(u8, MAXHASHLEN).init(0) catch unreachable else null;

            if (self.choice == .SHA256) {
                const hkdf_out = HashSha256.HKDF(chaining_key, input_key_material, num_outputs);
                try out1.appendSlice(&hkdf_out[0]);
                try out2.appendSlice(&hkdf_out[1]);
                if (out3) |*o| try o.*.appendSlice(&hkdf_out[2].?);
            } else if (self.choice == .BLAKE2s) {
                const hkdf_out = HashBlake2s.HKDF(chaining_key, input_key_material, num_outputs);
                try out1.appendSlice(&hkdf_out[0]);
                try out2.appendSlice(&hkdf_out[1]);
                if (out3) |*o| try o.*.appendSlice(&hkdf_out[2].?);
            } else if (self.choice == .SHA512) {
                const hkdf_out =
                    HashSha512.HKDF(chaining_key, input_key_material, num_outputs);
                try out1.appendSlice(&hkdf_out[0]);
                try out2.appendSlice(&hkdf_out[1]);
                if (out3) |*o| try o.*.appendSlice(&hkdf_out[2].?);
            } else if (self.choice == .BLAKE2b) {
                const hkdf_out = HashBlake2b.HKDF(chaining_key, input_key_material, num_outputs);
                try out1.appendSlice(&hkdf_out[0]);
                try out2.appendSlice(&hkdf_out[1]);
                if (out3) |*o| try o.*.appendSlice(&hkdf_out[2].?);
            }

            return .{ out1, out2, out3 };
        }
    };

    pub fn init(allocator: Allocator, protocol_name: []const u8) !Self {
        const protocol = protocolFromName(protocol_name);

        const hash_len: usize = switch (protocol.hash) {
            .SHA256, .BLAKE2s => 32,
            .SHA512, .BLAKE2b => MAXHASHLEN,
        };

        var hasher = Hasher{ .len = hash_len, .choice = protocol.hash };

        var h = BoundedArray(u8, MAXHASHLEN).init(0) catch unreachable;
        var ck = BoundedArray(u8, MAXHASHLEN).init(0) catch unreachable;
        if (protocol_name.len <= hash_len) {
            var data: [MAXHASHLEN]u8 = undefined;
            @memcpy(data[0..protocol_name.len], protocol_name[0..protocol_name.len]);
            for (protocol_name.len..hash_len) |i| {
                data[i] = 0;
            }
            try h.appendSlice(data[0..hash_len]);
        } else {
            h = try hasher.hash(protocol_name);
        }
        var split_it = std.mem.splitScalar(u8, protocol_name, '_');
        _ = split_it.next().?;
        _ = split_it.next().?;
        _ = split_it.next().?;
        var cipher_choice = [_]u8{0} ** 10;
        const cipher_choice_st = split_it.next().?;
        std.mem.copyForwards(u8, &cipher_choice, cipher_choice_st);

        const cipher_state = CipherState.init(&cipher_choice, [_]u8{0} ** 32);
        try ck.appendSlice(h.constSlice());

        return .{
            .allocator = allocator,
            .cipher_choice = cipher_choice,
            .cipher_state = cipher_state,
            .ck = ck,
            .h = h,
            .hasher = hasher,
        };
    }

    pub fn mixKey(
        self: *Self,
        input_key_material: []const u8,
    ) !void {
        // Sets ck, temp_k = HKDF(ck, input_key_material, 2).
        // If HASHLEN is MAXHASHLEN, then truncates temp_k to 32 bytes.
        // Calls InitializeKey(temp_k).
        const output = try self.hasher.HKDF(self.ck.constSlice(), input_key_material, 2);

        self.ck = output[0];
        var temp_k: [32]u8 = undefined;
        @memcpy(&temp_k, output[1].constSlice()[0..32]);
        self.cipher_state = CipherState.init(&self.cipher_choice, temp_k);
    }

    pub fn mixHash(self: *Self, data: []const u8) !void {
        const h_with_data = try std.mem.concat(self.allocator, u8, &[_][]const u8{ self.h.constSlice(), data });
        defer self.allocator.free(h_with_data);
        self.h = try self.hasher.hash(h_with_data);
    }

    /// Used for pre-shared symmetric key (or PSK) mode to support protocols where both parties
    /// have a 32-byte shared secret key.
    pub fn mixKeyAndHash(self: *Self, input_key_material: []const u8) !void {
        const output = try self.hasher.HKDF(self.ck.constSlice(), input_key_material, 3);

        self.ck = output[0];
        try self.mixHash(output[1].constSlice());
        var temp_k: [32]u8 = undefined;
        @memcpy(&temp_k, output[2].?.constSlice()[0..32]);
        self.cipher_state = CipherState.init(&self.cipher_choice, temp_k);
    }

    pub fn encryptAndHash(self: *Self, ciphertext: []u8, plaintext: []const u8) ![]const u8 {
        //Sets ciphertext = EncryptWithAd(h, plaintext), calls MixHash(ciphertext), and returns ciphertext. Note that if k is empty, the EncryptWithAd() call will set ciphertext equal to plaintext.
        const slice = try self.cipher_state.encryptWithAd(ciphertext, self.h.constSlice(), plaintext);
        try self.mixHash(slice);
        return slice;
    }

    /// Sets ciphertext = EncryptWithAd(h, plaintext), calls MixHash(ciphertext), and returns ciphertext. Note that if k is empty, the EncryptWithAd() call will set ciphertext equal to plaintext.
    pub fn decryptAndHash(self: *Self, plaintext: []u8, ciphertext: []const u8) ![]const u8 {
        const decrypted = try self.cipher_state.decryptWithAd(plaintext, self.h.constSlice(), ciphertext);
        try self.mixHash(ciphertext);
        return decrypted;
    }

    pub fn split(
        self: *Self,
    ) !struct { CipherState, CipherState } {
        //
        //    Sets temp_k1, temp_k2 = HKDF(ck, zerolen, 2).
        //    If HASHLEN is MAXHASHLEN, then truncates temp_k1 and temp_k2 to 32 bytes.
        //    Creates two new CipherState objects c1 and c2.
        //    Calls c1.InitializeKey(temp_k1) and c2.InitializeKey(temp_k2).
        //    Returns the pair (c1, c2).
        const output = try self.hasher.HKDF(self.ck.constSlice(), &[_]u8{}, 2);

        var temp_k1: [32]u8 = undefined;
        var temp_k2: [32]u8 = undefined;
        @memcpy(&temp_k1, output[0].constSlice()[0..32]);
        @memcpy(&temp_k2, output[1].constSlice()[0..32]);

        const c1 = CipherState.init(&self.cipher_choice, temp_k1);
        const c2 = CipherState.init(&self.cipher_choice, temp_k2);

        return .{ c1, c2 };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

test "init symmetric state" {
    var symmetric_state = try SymmetricState.init(
        std.testing.allocator,
        "Noise_XX_25519_AESGCM_SHA256",
    );
    const ck = [_]u8{1} ** 32;
    const ikm = [_]u8{};
    const allocator = std.testing.allocator;
    const output = try symmetric_state.hasher.HKDF(&ck, &ikm, 3);
    errdefer allocator.free(&output[0]);

    defer symmetric_state.deinit();
}
