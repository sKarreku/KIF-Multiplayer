# ===========================================
# File: 047_DeltaCompression.rb
# Purpose: Delta compression for network updates
# ===========================================
# Sends only the changed fields instead of full state
# Reduces bandwidth usage significantly
# ===========================================

module DeltaCompression
  module_function

  # Compare two state hashes and return only the differences
  # @param old_state [Hash] Previous state snapshot
  # @param new_state [Hash] Current state snapshot
  # @return [Hash] Hash containing only changed fields
  def calculate_delta(old_state, new_state)
    return new_state if old_state.nil? || old_state.empty?

    delta = {}
    new_state.each do |key, value|
      # Include field if it's new or changed
      if !old_state.key?(key) || old_state[key] != value
        delta[key] = value
      end
    end

    delta
  end

  # Apply delta to a base state to get the new state
  # @param base_state [Hash] Base state to apply delta to
  # @param delta [Hash] Delta containing changed fields
  # @return [Hash] New state with delta applied
  def apply_delta(base_state, delta)
    return delta if base_state.nil? || base_state.empty?

    new_state = base_state.dup
    delta.each do |key, value|
      new_state[key] = value
    end

    new_state
  end

  # Encode delta for network transmission
  # @param delta [Hash] Delta to encode
  # @return [String] Compact string representation
  def encode_delta(delta)
    return "" if delta.nil? || delta.empty?

    parts = []
    delta.each do |key, value|
      parts << "#{key}=#{value}"
    end

    parts.join(",")
  end

  # Decode delta from network transmission
  # @param encoded [String] Encoded delta string
  # @return [Hash] Decoded delta hash
  def decode_delta(encoded)
    return {} if encoded.nil? || encoded.empty?

    delta = {}
    encoded.split(",").each do |part|
      key, value = part.split("=", 2)
      next unless key && value

      # Convert to appropriate types
      delta[key.to_sym] = parse_value(value)
    end

    delta
  end

  # Parse value from string to appropriate type
  # @param value [String] String value to parse
  # @return [Object] Parsed value (Integer, Float, String, Symbol)
  def parse_value(value)
    # Try integer
    return value.to_i if value =~ /\A-?\d+\z/

    # Try float
    return value.to_f if value =~ /\A-?\d+\.\d+\z/

    # Return as string
    value
  end

  # Calculate compression ratio
  # @param original_size [Integer] Size of original data
  # @param compressed_size [Integer] Size of compressed data
  # @return [Float] Compression ratio (0.0 to 1.0, lower is better)
  def compression_ratio(original_size, compressed_size)
    return 0.0 if original_size == 0
    compressed_size.to_f / original_size.to_f
  end

  # Check if delta is worth sending (has changes)
  # @param delta [Hash] Delta to check
  # @return [Boolean] True if delta has changes
  def has_changes?(delta)
    !delta.nil? && !delta.empty?
  end

  # Estimate bandwidth savings
  # @param full_state [Hash] Full state that would be sent
  # @param delta [Hash] Delta that will be sent instead
  # @return [Hash] Statistics about bandwidth savings
  def estimate_savings(full_state, delta)
    full_encoded = encode_delta(full_state)
    delta_encoded = encode_delta(delta)

    full_size = full_encoded.bytesize
    delta_size = delta_encoded.bytesize
    saved = full_size - delta_size
    ratio = compression_ratio(full_size, delta_size)

    {
      full_size: full_size,
      delta_size: delta_size,
      bytes_saved: saved,
      compression_ratio: ratio,
      percent_saved: ((1.0 - ratio) * 100).round(1)
    }
  end
end

# Debug/Test
if __FILE__ == $0
  puts "DeltaCompression Test Suite"
  puts "=" * 40

  # Test 1: Calculate delta
  old_state = { x: 10, y: 20, map: 1, face: 0 }
  new_state = { x: 12, y: 20, map: 1, face: 1 }

  delta = DeltaCompression.calculate_delta(old_state, new_state)
  puts "Test 1: Calculate delta"
  puts "  Old state: #{old_state.inspect}"
  puts "  New state: #{new_state.inspect}"
  puts "  Delta: #{delta.inspect}"
  puts "  Expected: {:x=>12, :face=>1}"
  puts "  Pass: #{delta == { x: 12, face: 1 }}"

  # Test 2: Apply delta
  base_state = { x: 10, y: 20, map: 1, face: 0 }
  delta = { x: 12, face: 1 }
  result = DeltaCompression.apply_delta(base_state, delta)
  puts "\nTest 2: Apply delta"
  puts "  Base state: #{base_state.inspect}"
  puts "  Delta: #{delta.inspect}"
  puts "  Result: #{result.inspect}"
  puts "  Expected: {:x=>12, :y=>20, :map=>1, :face=>1}"
  puts "  Pass: #{result == { x: 12, y: 20, map: 1, face: 1 }}"

  # Test 3: Encode/Decode
  delta = { x: 12, y: 20, face: 1 }
  encoded = DeltaCompression.encode_delta(delta)
  decoded = DeltaCompression.decode_delta(encoded)
  puts "\nTest 3: Encode/Decode"
  puts "  Original: #{delta.inspect}"
  puts "  Encoded: #{encoded}"
  puts "  Decoded: #{decoded.inspect}"
  puts "  Pass: #{delta == decoded}"

  # Test 4: Bandwidth savings
  full_state = { x: 10, y: 20, map: 1, face: 0, clothes: 5, hat: 2 }
  delta = { x: 12 }
  savings = DeltaCompression.estimate_savings(full_state, delta)
  puts "\nTest 4: Bandwidth savings"
  puts "  Full state size: #{savings[:full_size]} bytes"
  puts "  Delta size: #{savings[:delta_size]} bytes"
  puts "  Bytes saved: #{savings[:bytes_saved]} bytes"
  puts "  Percent saved: #{savings[:percent_saved]}%"

  puts "\n" + "=" * 40
  puts "DeltaCompression module loaded successfully!"
end
