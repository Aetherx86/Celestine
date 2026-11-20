const std = @import("std");

pub const HEADER_SIZE: usize = 44;

pub const WavFormat = enum {
    pcm16,
    float32,

    pub fn formatTag(self: WavFormat) u16 {
        return switch (self) {
            .pcm16 => 1, // WAVE_FORMAT_PCM
            .float32 => 3, // WAVE_FORMAT_IEEE_FLOAT
        };
    }

    pub fn bitsPerSample(self: WavFormat) u16 {
        return switch (self) {
            .pcm16 => 16,
            .float32 => 32,
        };
    }

    pub fn bytesPerSample(self: WavFormat) u16 {
        return self.bitsPerSample() / 8;
    }
};

pub fn encodeSamplePcm16(sample: f32) i16 {
    if (!std.math.isFinite(sample)) return 0;
    const clamped = std.math.clamp(sample, -1.0, 1.0);
    const scaled = clamped * 32767.0;
    return @intFromFloat(@round(scaled));
}

pub fn writeHeader(
    out: *[HEADER_SIZE]u8,
    sample_rate: u32,
    num_channels: u16,
    num_frames: u32,
    format: WavFormat,
) void {
    const bytes_per_sample: u32 = format.bytesPerSample();
    const block_align: u16 = num_channels * format.bytesPerSample();
    const byte_rate: u32 = sample_rate * @as(u32, block_align);
    const data_bytes: u32 = num_frames * @as(u32, num_channels) * bytes_per_sample;
    const riff_chunk_size: u32 = 36 + data_bytes;

    @memcpy(out[0..4], "RIFF");
    std.mem.writeInt(u32, out[4..8], riff_chunk_size, .little);
    @memcpy(out[8..12], "WAVE");

    @memcpy(out[12..16], "fmt ");
    std.mem.writeInt(u32, out[16..20], 16, .little); // PCM/IEEE fmt chunk size
    std.mem.writeInt(u16, out[20..22], format.formatTag(), .little);
    std.mem.writeInt(u16, out[22..24], num_channels, .little);
    std.mem.writeInt(u32, out[24..28], sample_rate, .little);
    std.mem.writeInt(u32, out[28..32], byte_rate, .little);
    std.mem.writeInt(u16, out[32..34], block_align, .little);
    std.mem.writeInt(u16, out[34..36], format.bitsPerSample(), .little);

    @memcpy(out[36..40], "data");
    std.mem.writeInt(u32, out[40..44], data_bytes, .little);
}

pub fn encodePcm16(allocator: std.mem.Allocator, samples: []const f32, sample_rate: u32) ![]u8 {
    const num_frames: u32 = @intCast(samples.len);
    const total_bytes = HEADER_SIZE + (samples.len * 2);
    const buf = try allocator.alloc(u8, total_bytes);
    errdefer allocator.free(buf);

    writeHeader(buf[0..HEADER_SIZE], sample_rate, 1, num_frames, .pcm16);
    var offset: usize = HEADER_SIZE;
    for (samples) |s| {
        std.mem.writeInt(i16, buf[offset..][0..2], encodeSamplePcm16(s), .little);
        offset += 2;
    }
    return buf;
}

/// Zero-heap-allocation streaming mono WAV writer for fixed-frame synthesis renders.
pub const StreamWriter = struct {
    io: std.Io,
    file: std.Io.File,
    format: WavFormat,

    pub fn create(
        io: std.Io,
        path: []const u8,
        sample_rate: u32,
        total_frames: u32,
        format: WavFormat,
    ) !StreamWriter {
        const file = try std.Io.Dir.cwd().createFile(io, path, .{});
        errdefer file.close(io);

        var header: [HEADER_SIZE]u8 = undefined;
        writeHeader(&header, sample_rate, 1, total_frames, format);
        try file.writeStreamingAll(io, &header);

        return .{
            .io = io,
            .file = file,
            .format = format,
        };
    }

    pub fn writeFrames(self: *StreamWriter, samples: []const f32) !void {
        var scratch: [2048]u8 = undefined;
        var idx: usize = 0;

        switch (self.format) {
            .pcm16 => {
                while (idx < samples.len) {
                    const chunk_frames: usize = @min(samples.len - idx, scratch.len / 2);
                    for (0..chunk_frames) |i| {
                        std.mem.writeInt(i16, scratch[i * 2 ..][0..2], encodeSamplePcm16(samples[idx + i]), .little);
                    }
                    try self.file.writeStreamingAll(self.io, scratch[0 .. chunk_frames * 2]);
                    idx += chunk_frames;
                }
            },
            .float32 => {
                while (idx < samples.len) {
                    const chunk_frames: usize = @min(samples.len - idx, scratch.len / 4);
                    for (0..chunk_frames) |i| {
                        const s = samples[idx + i];
                        const safe: f32 = if (std.math.isFinite(s)) std.math.clamp(s, -1.0, 1.0) else 0.0;
                        const bits: u32 = @bitCast(safe);
                        std.mem.writeInt(u32, scratch[i * 4 ..][0..4], bits, .little);
                    }
                    try self.file.writeStreamingAll(self.io, scratch[0 .. chunk_frames * 4]);
                    idx += chunk_frames;
                }
            },
        }
    }

    pub fn close(self: *StreamWriter) void {
        self.file.close(self.io);
    }
};

test "WAV header and PCM16 encoding" {
    const samples = [_]f32{ 0.0, 1.0, -1.0, 0.5, 2.5, std.math.nan(f32) };
    const wav_bytes = try encodePcm16(std.testing.allocator, &samples, 44100);
    defer std.testing.allocator.free(wav_bytes);

    try std.testing.expectEqual(@as(usize, HEADER_SIZE + samples.len * 2), wav_bytes.len);
    try std.testing.expectEqualStrings("RIFF", wav_bytes[0..4]);
    try std.testing.expectEqualStrings("WAVE", wav_bytes[8..12]);
    try std.testing.expectEqualStrings("fmt ", wav_bytes[12..16]);
    try std.testing.expectEqualStrings("data", wav_bytes[36..40]);

    // Check format tag = 1 (PCM), channels = 1, sample rate = 44100, bits = 16
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, wav_bytes[20..22], .little));
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, wav_bytes[22..24], .little));
    try std.testing.expectEqual(@as(u32, 44100), std.mem.readInt(u32, wav_bytes[24..28], .little));
    try std.testing.expectEqual(@as(u16, 16), std.mem.readInt(u16, wav_bytes[34..36], .little));
    try std.testing.expectEqual(@as(u32, 12), std.mem.readInt(u32, wav_bytes[40..44], .little));

    // Check sample values: 0, 32767, -32767, ~16384, clamped 32767, NaN -> 0
    try std.testing.expectEqual(@as(i16, 0), std.mem.readInt(i16, wav_bytes[44..46], .little));
    try std.testing.expectEqual(@as(i16, 32767), std.mem.readInt(i16, wav_bytes[46..48], .little));
    try std.testing.expectEqual(@as(i16, -32767), std.mem.readInt(i16, wav_bytes[48..50], .little));
    try std.testing.expectEqual(@as(i16, 16384), std.mem.readInt(i16, wav_bytes[50..52], .little));
    try std.testing.expectEqual(@as(i16, 32767), std.mem.readInt(i16, wav_bytes[52..54], .little));
    try std.testing.expectEqual(@as(i16, 0), std.mem.readInt(i16, wav_bytes[54..56], .little));
}

test "WAV float32 header fields" {
    var header: [HEADER_SIZE]u8 = undefined;
    writeHeader(&header, 48000, 1, 1000, .float32);
    try std.testing.expectEqual(@as(u16, 3), std.mem.readInt(u16, header[20..22], .little));
    try std.testing.expectEqual(@as(u16, 32), std.mem.readInt(u16, header[34..36], .little));
    try std.testing.expectEqual(@as(u32, 4000), std.mem.readInt(u32, header[40..44], .little));
    try std.testing.expectEqual(@as(u32, 4036), std.mem.readInt(u32, header[4..8], .little));
}
