# ===========================================
# File: 009_PureMD5.rb
# Purpose: Pure Ruby MD5 Implementation
# ===========================================
# Pure Ruby implementation of MD5 hash algorithm
# No external dependencies (no 'digest', no 'openssl')
# Works in game's embedded Ruby environment
# ===========================================

module PureMD5
  # MD5 constants
  S = [
    7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
    5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
    4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
    6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21
  ].freeze

  K = [
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
  ].freeze

  module_function

  # Calculate MD5 hash of a string
  # Returns: 32-character hexadecimal string
  def hexdigest(string)
    # Convert string to binary if needed
    msg = string.force_encoding('ASCII-8BIT') rescue string.b

    # Initialize hash values
    a0 = 0x67452301
    b0 = 0xefcdab89
    c0 = 0x98badcfe
    d0 = 0x10325476

    # Pre-processing: adding padding bits
    msg_len = msg.bytesize
    msg += "\x80".force_encoding('ASCII-8BIT')

    # Pad with zeros until length ≡ 448 (mod 512)
    while (msg.bytesize % 64) != 56
      msg += "\x00".force_encoding('ASCII-8BIT')
    end

    # Append original message length in bits as 64-bit little-endian
    msg += [msg_len * 8].pack('Q<')

    # Process message in 512-bit chunks
    (0...msg.bytesize).step(64) do |chunk_start|
      chunk = msg[chunk_start, 64]

      # Break chunk into sixteen 32-bit little-endian words
      m = chunk.unpack('V16')

      # Initialize working variables
      a = a0
      b = b0
      c = c0
      d = d0

      # Main loop
      64.times do |i|
        if i < 16
          f = (b & c) | ((~b) & d)
          g = i
        elsif i < 32
          f = (d & b) | ((~d) & c)
          g = (5 * i + 1) % 16
        elsif i < 48
          f = b ^ c ^ d
          g = (3 * i + 5) % 16
        else
          f = c ^ (b | (~d))
          g = (7 * i) % 16
        end

        # Ensure values stay within 32-bit range
        f = (f + a + K[i] + m[g]) & 0xffffffff
        a = d
        d = c
        c = b
        b = (b + left_rotate(f, S[i])) & 0xffffffff
      end

      # Add this chunk's hash to result so far
      a0 = (a0 + a) & 0xffffffff
      b0 = (b0 + b) & 0xffffffff
      c0 = (c0 + c) & 0xffffffff
      d0 = (d0 + d) & 0xffffffff
    end

    # Produce final hash value (little-endian)
    digest = [a0, b0, c0, d0].pack('V4')

    # Convert to hexadecimal string
    digest.unpack('H*')[0]
  end

  # Calculate MD5 hash of a file
  # Returns: 32-character hexadecimal string
  def file_hexdigest(file_path)
    content = File.read(file_path)
    hexdigest(content)
  rescue => e
    # Return error indicator if file can't be read
    "error_reading_file_#{e.class}"
  end

  # Left rotate a 32-bit integer
  def left_rotate(value, shift)
    ((value << shift) | (value >> (32 - shift))) & 0xffffffff
  end
end

# Debug/Test (only runs if this file is executed directly)
if __FILE__ == $0
  puts "PureMD5 Test Suite"
  puts "=" * 40

  # Test 1: Empty string
  hash1 = PureMD5.hexdigest("")
  expected1 = "d41d8cd98f00b204e9800998ecf8427e"
  puts "Test 1 (empty): #{hash1 == expected1 ? 'PASS' : 'FAIL'}"
  puts "  Got:      #{hash1}"
  puts "  Expected: #{expected1}"

  # Test 2: Simple string
  hash2 = PureMD5.hexdigest("abc")
  expected2 = "900150983cd24fb0d6963f7d28e17f72"
  puts "Test 2 ('abc'): #{hash2 == expected2 ? 'PASS' : 'FAIL'}"
  puts "  Got:      #{hash2}"
  puts "  Expected: #{expected2}"

  # Test 3: Longer string
  hash3 = PureMD5.hexdigest("The quick brown fox jumps over the lazy dog")
  expected3 = "9e107d9d372bb6826bd81d3542a419d6"
  puts "Test 3 (fox): #{hash3 == expected3 ? 'PASS' : 'FAIL'}"
  puts "  Got:      #{hash3}"
  puts "  Expected: #{expected3}"

  puts "=" * 40
  puts "PureMD5 module loaded successfully!"
end
