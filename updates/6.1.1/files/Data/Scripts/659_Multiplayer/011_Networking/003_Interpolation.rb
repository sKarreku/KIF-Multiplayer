# ===========================================
# File: 049_ClientInterpolation.rb
# Purpose: Client-side position interpolation
# ===========================================
# Smoothly interpolates remote player positions
# Reduces stuttering when update rate is low
# Creates fluid movement between network updates
# ===========================================

module ClientInterpolation
  module_function

  # Interpolation methods
  INTERPOLATION_LINEAR = :linear
  INTERPOLATION_SMOOTH = :smooth  # Ease-in-ease-out
  INTERPOLATION_SNAP = :snap      # No interpolation (instant)

  # Default interpolation settings
  DEFAULT_METHOD = INTERPOLATION_LINEAR
  DEFAULT_DURATION = 0.15  # 150ms interpolation time

  # Calculate interpolated position between two points
  # @param from_pos [Hash] Start position {:x, :y}
  # @param to_pos [Hash] Target position {:x, :y}
  # @param progress [Float] Progress from 0.0 to 1.0
  # @param method [Symbol] Interpolation method
  # @return [Hash] Interpolated position {:x, :y}
  def interpolate_position(from_pos, to_pos, progress, method = DEFAULT_METHOD)
    # Clamp progress to 0.0-1.0
    progress = [[progress, 0.0].max, 1.0].min

    # Apply easing function based on method
    eased_progress = case method
    when INTERPOLATION_SMOOTH
      smooth_step(progress)
    when INTERPOLATION_SNAP
      progress >= 1.0 ? 1.0 : 0.0
    else  # LINEAR
      progress
    end

    # Interpolate x and y
    {
      x: lerp(from_pos[:x], to_pos[:x], eased_progress),
      y: lerp(from_pos[:y], to_pos[:y], eased_progress)
    }
  end

  # Linear interpolation between two values
  # @param a [Numeric] Start value
  # @param b [Numeric] End value
  # @param t [Float] Progress (0.0 to 1.0)
  # @return [Float] Interpolated value
  def lerp(a, b, t)
    a + (b - a) * t
  end

  # Smooth step interpolation (ease-in-ease-out)
  # @param t [Float] Progress (0.0 to 1.0)
  # @return [Float] Smoothed progress
  def smooth_step(t)
    # Smoothstep formula: 3t² - 2t³
    t * t * (3.0 - 2.0 * t)
  end

  # Calculate progress based on elapsed time
  # @param start_time [Time] Interpolation start time
  # @param duration [Float] Total interpolation duration in seconds
  # @return [Float] Progress from 0.0 to 1.0
  def calculate_progress(start_time, duration)
    elapsed = Time.now - start_time
    progress = elapsed / duration
    [[progress, 0.0].max, 1.0].min
  end

  # Check if interpolation is complete
  # @param start_time [Time] Interpolation start time
  # @param duration [Float] Total interpolation duration in seconds
  # @return [Boolean] True if interpolation finished
  def interpolation_complete?(start_time, duration)
    (Time.now - start_time) >= duration
  end

  # Calculate distance between two positions
  # @param pos1 [Hash] First position {:x, :y}
  # @param pos2 [Hash] Second position {:x, :y}
  # @return [Float] Distance in tiles
  def distance(pos1, pos2)
    dx = pos1[:x] - pos2[:x]
    dy = pos1[:y] - pos2[:y]
    Math.sqrt(dx * dx + dy * dy)
  end

  # Check if positions are close enough to snap (no interpolation needed)
  # @param pos1 [Hash] First position {:x, :y}
  # @param pos2 [Hash] Second position {:x, :y}
  # @param threshold [Float] Distance threshold in tiles
  # @return [Boolean] True if positions are within threshold
  def should_snap?(pos1, pos2, threshold = 0.5)
    distance(pos1, pos2) < threshold
  end

  # Check if position change is too large (teleport detection)
  # @param pos1 [Hash] First position {:x, :y}
  # @param pos2 [Hash] Second position {:x, :y}
  # @param threshold [Float] Distance threshold in tiles
  # @return [Boolean] True if distance exceeds threshold (likely teleport)
  def is_teleport?(pos1, pos2, threshold = 5.0)
    distance(pos1, pos2) > threshold
  end

  # Create interpolation state for a remote player
  # @param current_pos [Hash] Current position {:x, :y}
  # @param target_pos [Hash] New target position {:x, :y}
  # @param duration [Float] Interpolation duration in seconds
  # @return [Hash] Interpolation state
  def create_interpolation_state(current_pos, target_pos, duration = DEFAULT_DURATION)
    {
      from: current_pos.dup,
      to: target_pos.dup,
      start_time: Time.now,
      duration: duration,
      method: DEFAULT_METHOD
    }
  end

  # Update interpolation state and get current interpolated position
  # @param interp_state [Hash] Interpolation state
  # @return [Hash] Current interpolated position {:x, :y}
  def update_interpolation(interp_state)
    return interp_state[:to] if interp_state.nil?

    progress = calculate_progress(interp_state[:start_time], interp_state[:duration])
    interpolate_position(interp_state[:from], interp_state[:to], progress, interp_state[:method])
  end

  # Calculate appropriate interpolation duration based on distance
  # Longer distances get slightly longer interpolation times
  # @param from_pos [Hash] Start position {:x, :y}
  # @param to_pos [Hash] Target position {:x, :y}
  # @return [Float] Recommended interpolation duration in seconds
  def calculate_duration(from_pos, to_pos)
    dist = distance(from_pos, to_pos)

    # Base duration: 150ms
    # Add 20ms per tile moved (up to max 300ms)
    base = 0.15
    per_tile = 0.02
    max_duration = 0.30

    duration = base + (dist * per_tile)
    [duration, max_duration].min
  end

  # Predict future position based on velocity
  # Used for extrapolation when packets are delayed
  # @param current_pos [Hash] Current position {:x, :y}
  # @param previous_pos [Hash] Previous position {:x, :y}
  # @param time_delta [Float] Time elapsed since last update
  # @return [Hash] Predicted position {:x, :y}
  def predict_position(current_pos, previous_pos, time_delta)
    return current_pos if previous_pos.nil? || time_delta <= 0

    # Calculate velocity
    vx = current_pos[:x] - previous_pos[:x]
    vy = current_pos[:y] - previous_pos[:y]

    # Extrapolate position
    {
      x: current_pos[:x] + vx * time_delta,
      y: current_pos[:y] + vy * time_delta
    }
  end
end

# Debug/Test
if __FILE__ == $0
  puts "ClientInterpolation Test Suite"
  puts "=" * 60

  # Test 1: Linear interpolation
  from = { x: 10, y: 20 }
  to = { x: 15, y: 25 }

  puts "Test 1: Linear interpolation"
  puts "  From: (#{from[:x]}, #{from[:y]})"
  puts "  To: (#{to[:x]}, #{to[:y]})"

  [0.0, 0.25, 0.5, 0.75, 1.0].each do |progress|
    pos = ClientInterpolation.interpolate_position(from, to, progress, :linear)
    puts "  Progress #{(progress * 100).to_i}%: (#{pos[:x].round(2)}, #{pos[:y].round(2)})"
  end

  # Test 2: Smooth interpolation
  puts "\nTest 2: Smooth interpolation (ease-in-ease-out)"
  [0.0, 0.25, 0.5, 0.75, 1.0].each do |progress|
    pos = ClientInterpolation.interpolate_position(from, to, progress, :smooth)
    puts "  Progress #{(progress * 100).to_i}%: (#{pos[:x].round(2)}, #{pos[:y].round(2)})"
  end

  # Test 3: Distance calculation
  pos1 = { x: 10, y: 20 }
  pos2 = { x: 13, y: 24 }
  dist = ClientInterpolation.distance(pos1, pos2)
  puts "\nTest 3: Distance calculation"
  puts "  Pos1: (#{pos1[:x]}, #{pos1[:y]})"
  puts "  Pos2: (#{pos2[:x]}, #{pos2[:y]})"
  puts "  Distance: #{dist.round(2)} tiles"
  puts "  Expected: 5.0 tiles"

  # Test 4: Snap detection
  close_pos1 = { x: 10, y: 20 }
  close_pos2 = { x: 10.3, y: 20.2 }
  should_snap = ClientInterpolation.should_snap?(close_pos1, close_pos2, 0.5)
  puts "\nTest 4: Snap detection"
  puts "  Should snap (< 0.5 tiles): #{should_snap}"

  # Test 5: Teleport detection
  far_pos1 = { x: 10, y: 20 }
  far_pos2 = { x: 30, y: 40 }
  is_teleport = ClientInterpolation.is_teleport?(far_pos1, far_pos2, 5.0)
  puts "\nTest 5: Teleport detection"
  puts "  Distance: #{ClientInterpolation.distance(far_pos1, far_pos2).round(2)} tiles"
  puts "  Is teleport (> 5 tiles): #{is_teleport}"

  # Test 6: Duration calculation
  puts "\nTest 6: Duration calculation"
  test_distances = [
    { from: {x: 0, y: 0}, to: {x: 1, y: 0}, name: "1 tile" },
    { from: {x: 0, y: 0}, to: {x: 3, y: 4}, name: "5 tiles" },
    { from: {x: 0, y: 0}, to: {x: 10, y: 0}, name: "10 tiles" },
    { from: {x: 0, y: 0}, to: {x: 20, y: 0}, name: "20 tiles" }
  ]

  test_distances.each do |test|
    duration = ClientInterpolation.calculate_duration(test[:from], test[:to])
    puts "  #{test[:name]}: #{(duration * 1000).round(0)}ms"
  end

  # Test 7: Position prediction
  puts "\nTest 7: Position prediction"
  current = { x: 10, y: 20 }
  previous = { x: 9, y: 19 }
  predicted = ClientInterpolation.predict_position(current, previous, 1.0)
  puts "  Current: (#{current[:x]}, #{current[:y]})"
  puts "  Previous: (#{previous[:x]}, #{previous[:y]})"
  puts "  Predicted (1s ahead): (#{predicted[:x]}, #{predicted[:y]})"
  puts "  Expected: (11, 21)"

  puts "\n" + "=" * 60
  puts "ClientInterpolation module loaded successfully!"
end
