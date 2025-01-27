const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const MessageToken = enum {
    e,
    s,
    ee,
    es,
    se,
    ss,
    psk,
};

pub const MessagePattern = []const MessageToken;

const PreMessagePattern = enum {
    e,
    s,
    es,
    empty,
};

/// The following handshake patterns represent interactive protocols. These 12 patterns are called the fundamental interactive handshake patterns.
/// The fundamental interactive patterns are named with two characters, which indicate the status of the initiator and responder's static keys. The first and second characters refer to the initiator's and responder's static key respectively.
pub const HandshakePatternName = enum {
    /// N = **N**o static key for recipient
    N,
    /// K = Static key for sender **K**nown to recipient
    K,
    /// X = Static key for sender **X**mitted (transmitted) to recipient
    X,
    /// N = **N**o static key for initiator
    /// N = **N**o static key for responder
    NN,
    /// N = **N**o static key for initiator
    /// K = Static key for responder **K**nown to initiator
    NK,
    /// N = **N**o static key for initiator
    /// X = Static key for responder **X**mitted (transmitted) to initiator
    NX,
    /// K = Static key for initiator **K**nown to responder
    /// N = **N**o static key for responder
    KN,
    /// K = Static key for initiator **K**nown to responder
    /// K = Static key for responder **K**nown to initiator
    KK,
    /// K = Static key for initiator **K**nown to responder
    /// X = Static key for responder **X**mitted (transmitted) to initiator
    KX,
    /// X = Static key for initiator **X**mitted (transmitted) to responder
    /// N = **N**o static key for responder
    XN,
    /// X = Static key for initiator **X**mitted (transmitted) to responder
    /// K = Static key for responder **K**nown to initiator
    XK,
    /// X = Static key for initiator **X**mitted (transmitted) to responder
    /// X = Static key for responder **X**mitted (transmitted) to initiator
    XX,
    /// I = Static key for initiator **I**mmediately transmitted to responder, despite reduced or absent identity hiding
    /// X = Static key for responder **X**mitted (transmitted) to initiator
    IN,
    /// I = Static key for initiator **I**mmediately transmitted to responder, despite reduced or absent identity hiding
    /// N = **N**o static key for responder
    IK,
    /// I = Static key for initiator **I**mmediately transmitted to responder, despite reduced or absent identity hiding
    /// X = Static key for responder **X**mitted (transmitted) to initiator
    IX,
};

pre_message_pattern_initiator: ?PreMessagePattern,
pre_message_pattern_responder: ?PreMessagePattern,
message_patterns: []MessagePattern,

pub const HandshakePattern = @This();

pub fn patternFromName(hs_pattern_name: []const u8) !HandshakePattern {
    const hs_pattern_name_en = std.meta.stringToEnum(HandshakePatternName, hs_pattern_name).?;

    switch (hs_pattern_name_en) {
        .N => {
            var patterns: [1]MessagePattern = .{&[_]MessageToken{ .e, .es }};

            return .{
                .pre_message_pattern_initiator = null,
                .pre_message_pattern_responder = .s,
                .message_patterns = &patterns,
            };
        },
        .NN => {
            var patterns: [2]MessagePattern = .{
                &[_]MessageToken{.e},
                &[_]MessageToken{ .e, .ee },
            };

            return .{
                .pre_message_pattern_initiator = null,
                .pre_message_pattern_responder = null,
                .message_patterns = &patterns,
            };
        },
        .NK => {
            var patterns: [2]MessagePattern = .{
                &[_]MessageToken{ .e, .es },
                &[_]MessageToken{ .e, .ee },
            };

            return .{
                .pre_message_pattern_initiator = null,
                .pre_message_pattern_responder = .s,
                .message_patterns = &patterns,
            };
        },
        .NX => {
            var patterns: [2]MessagePattern = .{
                &[_]MessageToken{.e},
                &[_]MessageToken{ .e, .ee, .s, .es },
            };

            return .{
                .pre_message_pattern_initiator = null,
                .pre_message_pattern_responder = null,
                .message_patterns = &patterns,
            };
        },
        .K => {
            var patterns: [1]MessagePattern = .{&[_]MessageToken{ .e, .es, .ss }};

            return .{
                .pre_message_pattern_initiator = .s,
                .pre_message_pattern_responder = .s,
                .message_patterns = &patterns,
            };
        },
        .KN => {
            var patterns: [2]MessagePattern = [_]MessagePattern{
                &[_]MessageToken{.e},
                &[_]MessageToken{ .e, .ee, .se },
            };

            return .{
                .pre_message_pattern_initiator = .s,
                .pre_message_pattern_responder = null,
                .message_patterns = &patterns,
            };
        },
        .KK => {
            var patterns: [2]MessagePattern = .{
                &[_]MessageToken{ .e, .es, .ss },
                &[_]MessageToken{ .e, .ee, .se },
            };
            return .{
                .pre_message_pattern_initiator = .s,
                .pre_message_pattern_responder = .s,
                .message_patterns = &patterns,
            };
        },
        .KX => {
            var patterns: [2]MessagePattern = .{
                &[_]MessageToken{.e},
                &[_]MessageToken{ .e, .ee, .se, .s, .es },
            };

            return .{
                .pre_message_pattern_initiator = .s,
                .pre_message_pattern_responder = null,
                .message_patterns = &patterns,
            };
        },
        .X => {
            var patterns: [1]MessagePattern = .{&[_]MessageToken{ .e, .es, .s, .ss }};

            return .{
                .pre_message_pattern_initiator = null,
                .pre_message_pattern_responder = .s,
                .message_patterns = &patterns,
            };
        },
        .XN => {
            var patterns: [3]MessagePattern = .{
                &[_]MessageToken{.e},
                &[_]MessageToken{ .e, .ee },
                &[_]MessageToken{ .s, .se },
            };

            return .{
                .pre_message_pattern_initiator = null,
                .pre_message_pattern_responder = null,
                .message_patterns = &patterns,
            };
        },
        .XK => {
            var patterns: [3]MessagePattern = .{
                &[_]MessageToken{ .e, .es },
                &[_]MessageToken{ .e, .ee },
                &[_]MessageToken{ .s, .se },
            };

            return .{
                .pre_message_pattern_initiator = null,
                .pre_message_pattern_responder = .s,
                .message_patterns = &patterns,
            };
        },
        .XX => {
            var patterns: [3]MessagePattern = .{
                &[_]MessageToken{.e},
                &[_]MessageToken{ .e, .ee, .s, .es },
                &[_]MessageToken{ .s, .se },
            };

            return .{
                .pre_message_pattern_initiator = null,
                .pre_message_pattern_responder = null,
                .message_patterns = &patterns,
            };
        },
        .IN => {
            var patterns: [2]MessagePattern = .{
                &[_]MessageToken{ .e, .s },
                &[_]MessageToken{ .e, .ee, .se },
            };

            return .{
                .pre_message_pattern_initiator = null,
                .pre_message_pattern_responder = null,
                .message_patterns = &patterns,
            };
        },
        .IK => {
            var patterns: [2]MessagePattern = .{
                &[_]MessageToken{ .e, .es, .s, .ss },
                &[_]MessageToken{ .e, .ee, .se },
            };

            return .{
                .pre_message_pattern_initiator = null,
                .pre_message_pattern_responder = .s,
                .message_patterns = &patterns,
            };
        },
        .IX => {
            var patterns: [2]MessagePattern = .{
                &[_]MessageToken{ .e, .s },
                &[_]MessageToken{ .e, .ee, .se, .s, .es },
            };

            return .{
                .pre_message_pattern_initiator = null,
                .pre_message_pattern_responder = null,
                .message_patterns = &patterns,
            };
        },
    }
}

pub fn isOneWay(name: HandshakePatternName) bool {
    return switch (name) {
        .N, .X, .K => true,
        else => false,
    };
}
