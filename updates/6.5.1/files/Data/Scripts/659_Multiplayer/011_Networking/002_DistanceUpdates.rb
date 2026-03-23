# ===========================================
# File: 048_DistanceBasedUpdates.rb
# Purpose: Distance-based update rate optimization
# ===========================================
# Adjusts update frequency based on player distance
# Far players = slower updates (less bandwidth)
# Near players = faster updates (smooth movement)
# ===========================================

module DistanceBasedUpdates
  module_function

  # Update rate tiers based on distance
  # Distance measured in tiles (map coordinates)
  UPDATE_TIERS = [
    { max_distance: 5,   interval: 0.05 },  # Very close: 20 Hz (50ms)
    { max_distance: 10,  interval: 0.10 },  # Close: 10 Hz (100ms)
    { max_distance: 20,  interval: 0.20 },  # Medium: 5 Hz (200ms)
    { max_distance: 40,  interval: 0.50 },  # Far: 2 Hz (500ms)
    { max_distance: Float::INFINITY, interval: 1.0 }  # Very far: 1 Hz (1000ms)
  ]

  # Calculate distance between two positions
  # @param pos1 [Hash] Position with :x, :y, :map keys
  # @param pos2 [Hash] Position with :x, :y, :map keys
  # @return [Float] Distance in tiles, or infinity if different maps
  def calculate_distance(pos1, pos2)
    # Different maps = infinite distance
    return Float::INFINITY if pos1[:map] != pos2[:map]

    # Same map = Euclidean distance
    dx = pos1[:x].to_f - pos2[:x].to_f
    dy = pos1[:y].to_f - pos2[:y].to_f
    Math.sqrt(dx * dx + dy * dy)
  end

  # Get recommended update interval based on distance
  # @param distance [Float] Distance in tiles
  # @return [Float] Update interval in seconds
  def get_update_interval(distance)
    UPDATE_TIERS.each do |tier|
      return tier[:interval] if distance <= tier[:max_distance]
    end

    # Fallback (shouldn't reach here due to infinity tier)
    1.0
  end

  # Calculate update interval between local player and remote player
  # @param local_pos [Hash] Local player position {:x, :y, :map}
  # @param remote_pos [Hash] Remote player position {:x, :y, :map}
  # @return [Float] Update interval in seconds
  def calculate_update_interval(local_pos, remote_pos)
    distance = calculate_distance(local_pos, remote_pos)
    get_update_interval(distance)
  end

  # Check if enough time has elapsed for an update
  # @param last_update_time [Time] Last update timestamp
  # @param required_interval [Float] Required interval in seconds
  # @return [Boolean] True if update should be sent
  def should_update?(last_update_time, required_interval)
    return true if last_update_time.nil?
    (Time.now - last_update_time) >= required_interval
  end

  # Calculate update priorities for multiple remote players
  # Returns hash of {player_id => interval}
  # @param local_pos [Hash] Local player position
  # @param remote_players [Hash] Hash of {player_id => position}
  # @return [Hash] Hash of {player_id => interval}
  def calculate_priorities(local_pos, remote_players)
    priorities = {}
    remote_players.each do |player_id, remote_pos|
      distance = calculate_distance(local_pos, remote_pos)
      priorities[player_id] = {
        distance: distance,
        interval: get_update_interval(distance)
      }
    end
    priorities
  end

  # Get distance tier name for debugging
  # @param distance [Float] Distance in tiles
  # @return [String] Tier name
  def get_tier_name(distance)
    return "VERY_CLOSE" if distance <= 5
    return "CLOSE" if distance <= 10
    return "MEDIUM" if distance <= 20
    return "FAR" if distance <= 40
    return "VERY_FAR"
  end

  # Calculate bandwidth savings estimate
  # @param distance [Float] Distance in tiles
  # @param baseline_rate [Float] Baseline update rate (default 10 Hz)
  # @return [Hash] Statistics about bandwidth savings
  def estimate_savings(distance, baseline_rate = 10.0)
    baseline_interval = 1.0 / baseline_rate
    optimized_interval = get_update_interval(distance)

    # Updates per second
    baseline_ups = baseline_rate
    optimized_ups = 1.0 / optimized_interval

    # Reduction
    reduction_ratio = optimized_ups / baseline_ups
    percent_saved = ((1.0 - reduction_ratio) * 100).round(1)

    {
      distance: distance.round(1),
      tier: get_tier_name(distance),
      baseline_interval: baseline_interval,
      optimized_interval: optimized_interval,
      baseline_ups: baseline_ups,
      optimized_ups: optimized_ups.round(2),
      percent_saved: percent_saved
    }
  end
end

# Debug/Test
if __FILE__ == $0
  puts "DistanceBasedUpdates Test Suite"
  puts "=" * 60

  # Test 1: Calculate distance
  pos1 = { x: 10, y: 20, map: 1 }
  pos2 = { x: 13, y: 24, map: 1 }
  distance = DistanceBasedUpdates.calculate_distance(pos1, pos2)
  puts "Test 1: Calculate distance"
  puts "  Pos1: (10, 20) on map 1"
  puts "  Pos2: (13, 24) on map 1"
  puts "  Distance: #{distance.round(2)} tiles"
  puts "  Expected: 5.0 tiles"
  puts "  Pass: #{(distance - 5.0).abs < 0.01}"

  # Test 2: Different maps
  pos3 = { x: 10, y: 20, map: 2 }
  distance2 = DistanceBasedUpdates.calculate_distance(pos1, pos3)
  puts "\nTest 2: Different maps"
  puts "  Distance: #{distance2}"
  puts "  Expected: Infinity"
  puts "  Pass: #{distance2 == Float::INFINITY}"

  # Test 3: Update intervals for each tier
  puts "\nTest 3: Update intervals by distance"
  [0, 3, 7, 15, 30, 50, 100].each do |dist|
    interval = DistanceBasedUpdates.get_update_interval(dist)
    tier = DistanceBasedUpdates.get_tier_name(dist)
    ups = (1.0 / interval).round(2)
    puts "  Distance #{dist} tiles: #{interval}s (#{ups} Hz) - #{tier}"
  end

  # Test 4: Bandwidth savings
  puts "\nTest 4: Bandwidth savings estimates"
  [5, 10, 20, 40, 100].each do |dist|
    savings = DistanceBasedUpdates.estimate_savings(dist)
    puts "  #{savings[:tier]} (#{savings[:distance]} tiles):"
    puts "    Baseline: #{savings[:baseline_ups]} Hz"
    puts "    Optimized: #{savings[:optimized_ups]} Hz"
    puts "    Savings: #{savings[:percent_saved]}%"
  end

  # Test 5: Multiple players
  puts "\nTest 5: Priority calculation for multiple players"
  local = { x: 10, y: 10, map: 1 }
  remotes = {
    "Player1" => { x: 12, y: 11, map: 1 },  # Close
    "Player2" => { x: 25, y: 10, map: 1 },  # Medium
    "Player3" => { x: 60, y: 10, map: 1 },  # Very far
    "Player4" => { x: 10, y: 10, map: 2 }   # Different map
  }

  priorities = DistanceBasedUpdates.calculate_priorities(local, remotes)
  priorities.each do |player_id, data|
    tier = DistanceBasedUpdates.get_tier_name(data[:distance])
    puts "  #{player_id}: #{data[:distance].round(1)} tiles -> #{data[:interval]}s (#{tier})"
  end

  puts "\n" + "=" * 60
  puts "DistanceBasedUpdates module loaded successfully!"
end
