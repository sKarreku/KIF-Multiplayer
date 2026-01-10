#===============================================================================
# MODULE 6: Coop Battle RNG Seed Synchronization
#===============================================================================
# Ensures deterministic random number generation across all clients by
# synchronizing the RNG seed before each turn's attack phase
#===============================================================================

module CoopRNGSync
  # Received seed state
  @current_seed = nil
  @seed_received = false
  @seed_wait_start_time = nil
  @expected_turn = nil  # Track which turn we're waiting for
  @seed_buffer = {}  # Buffer for seeds that arrived before we started waiting: { turn => seed }

  #-----------------------------------------------------------------------------
  # Generate RNG seed (initiator only)
  # Uses: current timestamp + turn number + random component
  # Result: 31-bit positive integer (safe for Ruby's srand)
  #-----------------------------------------------------------------------------
  def self.generate_seed(turn_num)
    # Combine multiple sources of entropy
    time_component = (Time.now.to_f * 1000).to_i  # Milliseconds since epoch
    turn_component = turn_num * 1000
    micro_component = Time.now.usec

    # Mix components and ensure positive 31-bit integer
    seed = (time_component + turn_component + micro_component) & 0x7FFFFFFF

    ##MultiplayerDebug.info("SEED-GENERATE", "Turn #{turn_num}: Generated seed #{seed}")
    ##MultiplayerDebug.info("SEED-GENERATE", "  Components: time=#{time_component}, turn=#{turn_component}, usec=#{micro_component}")
    ##MultiplayerDebug.info("SEED-GENERATE", "  Binary: 0x#{seed.to_s(16)}, Valid: #{(seed >= 0 && seed <= 0x7FFFFFFF)}")

    seed
  end

  #-----------------------------------------------------------------------------
  # Initiator: Generate seed and broadcast to all allies
  # reset_counter: If false, don't reset RNG debug counter (for mid-turn resyncs)
  #-----------------------------------------------------------------------------
  def self.sync_seed_as_initiator(battle, turn_num = nil, reset_counter = true)
    return true unless defined?(CoopBattleState)
    return true unless CoopBattleState.in_coop_battle?

    ally_sids = CoopBattleState.get_ally_sids
    return true if ally_sids.empty?  # Solo battle

    battle_id = CoopBattleState.battle_id
    turn_num = turn_num || battle.turnCount  # Use provided turn or fallback to battle's turnCount

    ##MultiplayerDebug.info("COOP-RNG", "=" * 70)
    ##MultiplayerDebug.info("COOP-RNG", "RNG SEED SYNC (Initiator)")
    ##MultiplayerDebug.info("COOP-RNG", "  Battle ID: #{battle_id}")
    ##MultiplayerDebug.info("COOP-RNG", "  Turn: #{turn_num}")
    ##MultiplayerDebug.info("COOP-RNG", "  Reset Counter: #{reset_counter}")
    ##MultiplayerDebug.info("COOP-RNG", "=" * 70)

    # Generate seed
    seed = generate_seed(turn_num)
    @current_seed = seed

    # Broadcast to all allies
    begin
      ally_sids.each do |ally_sid|
        message = "COOP_RNG_SEED:#{battle_id}|#{turn_num}|#{seed}"
        MultiplayerClient.send_data(message, rate_limit_type: :RNG) if defined?(MultiplayerClient)
        ##MultiplayerDebug.info("SEED-SEND", "→ Sending to SID#{ally_sid}: battle=#{battle_id}, turn=#{turn_num}, seed=#{seed}")
      end
    rescue => e
      ##MultiplayerDebug.error("COOP-RNG", "Failed to broadcast seed: #{e.class}: #{e.message}")
      return false
    end

    # Apply seed locally
    begin
      # Store battle RNG instance for deterministic battle-only RNG
      @battle_rng = Random.new(seed)
      prev_seed = srand(seed)
      ##MultiplayerDebug.info("SEED-APPLY-INIT", "Applied locally: srand(#{seed}) + Random.new(#{seed})")
      ##MultiplayerDebug.info("SEED-APPLY-INIT", "  Previous seed: #{prev_seed}")

      # Log to RNG file with caller info
      if defined?(RNGLog)
        role = defined?(CoopBattleState) && CoopBattleState.am_i_initiator? ? "INIT" : "NON"
        caller_info = caller[0..2].map { |c| c.gsub(/.*Scripts\//, "") }.join(" <- ")
        RNGLog.write("[SEED][#{role}][T#{turn_num}] srand(#{seed})+Random.new prev=#{prev_seed} FROM: #{caller_info}")
      end
    rescue => e
      ##MultiplayerDebug.error("COOP-RNG", "Failed to apply seed: #{e.class}: #{e.message}")
      return false
    end

    # Update debug HUD
    if defined?(CoopBattleDebugHUD)
      CoopBattleDebugHUD.update_rng_seed(seed)
    end

    # Reset RNG debug counter for this turn (only if requested)
    if reset_counter && defined?(CoopRNGDebug)
      CoopRNGDebug.reset_counter(turn_num)
    end

    ##MultiplayerDebug.info("COOP-RNG", "RNG seed sync complete (Initiator)")
    true
  end

  #-----------------------------------------------------------------------------
  # Non-Initiator: Wait for and apply seed from initiator
  # reset_counter: If false, don't reset RNG debug counter (for mid-turn resyncs)
  #-----------------------------------------------------------------------------
  def self.sync_seed_as_receiver(battle, turn_num = nil, timeout_seconds = 5, reset_counter = true)
    return true unless defined?(CoopBattleState)
    return true unless CoopBattleState.in_coop_battle?

    battle_id = CoopBattleState.battle_id
    turn_num = turn_num || battle.turnCount  # Use provided turn or fallback to battle's turnCount

    ##MultiplayerDebug.info("COOP-RNG", "=" * 70)
    ##MultiplayerDebug.info("COOP-RNG", "RNG SEED SYNC (Non-Initiator)")
    ##MultiplayerDebug.info("COOP-RNG", "  Battle ID: #{battle_id}")
    ##MultiplayerDebug.info("COOP-RNG", "  Turn: #{turn_num}")
    ##MultiplayerDebug.info("COOP-RNG", "  Reset Counter: #{reset_counter}")
    ##MultiplayerDebug.info("COOP-RNG", "  Waiting for seed from initiator...")
    ##MultiplayerDebug.info("COOP-RNG", "=" * 70)

    # Set expected turn BEFORE resetting state
    @expected_turn = turn_num

    # Check if seed already in buffer (arrived early)
    if @seed_buffer[turn_num]
      retrieved_seed = @seed_buffer[turn_num]
      ##MultiplayerDebug.info("SEED-BUFFER-RETRIEVE", "Retrieved from buffer: turn=#{turn_num}, seed=#{retrieved_seed}")
      ##MultiplayerDebug.info("SEED-BUFFER-RETRIEVE", "  Buffer state before: #{@seed_buffer.inspect}")
      @current_seed = retrieved_seed
      @seed_received = true
      @seed_buffer.delete(turn_num)  # Remove from buffer
      ##MultiplayerDebug.info("SEED-BUFFER-RETRIEVE", "  Buffer state after: #{@seed_buffer.inspect}")
      @seed_wait_start_time = Time.now  # Set this to avoid nil error later
    else
      # Reset state (but keep expected_turn)
      @seed_received = false
      @current_seed = nil
      @seed_wait_start_time = Time.now

      # Wait for seed
      timeout_time = Time.now + timeout_seconds
      frame_count = 0

      while !@seed_received && Time.now < timeout_time
        # Update graphics
        Graphics.update if defined?(Graphics)
        Input.update if defined?(Input)

        # Periodic logging
        frame_count += 1
        if frame_count % 60 == 0
          elapsed = (Time.now - @seed_wait_start_time).round(1)
          ##MultiplayerDebug.info("COOP-RNG", "Still waiting for seed... #{elapsed}s elapsed")
        end

        sleep(0.016)  # ~60 FPS
      end
    end

    # Check if received
    if @seed_received && @current_seed
      # Apply seed
      begin
        ##MultiplayerDebug.info("SEED-APPLY-RECV", "About to apply: srand(#{@current_seed})")
        # Store battle RNG instance for deterministic battle-only RNG
        @battle_rng = Random.new(@current_seed)
        prev_seed = srand(@current_seed)
        ##MultiplayerDebug.info("SEED-APPLY-RECV", "Applied: srand(#{@current_seed}) + Random.new(#{@current_seed}), previous_seed=#{prev_seed}")

        # Log to RNG file with caller info
        if defined?(RNGLog)
          role = defined?(CoopBattleState) && CoopBattleState.am_i_initiator? ? "INIT" : "NON"
          caller_info = caller[0..2].map { |c| c.gsub(/.*Scripts\//, "") }.join(" <- ")
          RNGLog.write("[SEED][#{role}][T#{turn_num}] srand(#{@current_seed})+Random.new prev=#{prev_seed} FROM: #{caller_info}")
        end
      rescue => e
        ##MultiplayerDebug.error("COOP-RNG", "Failed to apply seed: #{e.class}: #{e.message}")
        return false
      end

      # Send acknowledgment
      begin
        ack_message = "COOP_RNG_SEED_ACK:#{battle_id}|#{turn_num}"
        MultiplayerClient.send_data(ack_message) if defined?(MultiplayerClient)
        ##MultiplayerDebug.info("COOP-RNG", "Sent RNG seed ACK")
      rescue => e
        ##MultiplayerDebug.warn("COOP-RNG", "Failed to send ACK: #{e.class}: #{e.message}")
        # Non-critical, continue anyway
      end

      # Update debug HUD
      if defined?(CoopBattleDebugHUD)
        CoopBattleDebugHUD.update_rng_seed(@current_seed)
      end

      # Reset RNG debug counter for this turn (only if requested)
      if reset_counter && defined?(CoopRNGDebug)
        CoopRNGDebug.reset_counter(turn_num)
      end

      wait_duration = @seed_wait_start_time ? (Time.now - @seed_wait_start_time).round(3) : 0.0
      ##MultiplayerDebug.info("COOP-RNG", "RNG seed sync complete (Non-Initiator): #{wait_duration}s")

      # Clear expected_turn so next sync can start fresh
      @expected_turn = nil

      true
    else
      # Timeout
      ##MultiplayerDebug.error("COOP-RNG", "=" * 70)
      ##MultiplayerDebug.error("COOP-RNG", "RNG SEED TIMEOUT")
      ##MultiplayerDebug.error("COOP-RNG", "  Timeout: #{timeout_seconds}s")
      ##MultiplayerDebug.error("COOP-RNG", "  Seed received: #{@seed_received}")
      ##MultiplayerDebug.error("COOP-RNG", "=" * 70)

      if defined?(CoopBattleDebugHUD)
        CoopBattleDebugHUD.set_message("RNG SEED TIMEOUT!")
      end

      false
    end
  end

  #-----------------------------------------------------------------------------
  # Receive seed from initiator (called from network handler)
  #-----------------------------------------------------------------------------
  def self.receive_seed(battle_id, turn, seed)
    ##MultiplayerDebug.info("SEED-RECEIVE-NET", "=" * 70)
    ##MultiplayerDebug.info("SEED-RECEIVE-NET", "Received from network:")
    ##MultiplayerDebug.info("SEED-RECEIVE-NET", "  battle_id=#{battle_id} (#{battle_id.class})")
    ##MultiplayerDebug.info("SEED-RECEIVE-NET", "  turn=#{turn} (#{turn.class})")
    ##MultiplayerDebug.info("SEED-RECEIVE-NET", "  seed=#{seed} (#{seed.class})")
    ##MultiplayerDebug.info("SEED-RECEIVE-NET", "  @expected_turn=#{@expected_turn}")
    ##MultiplayerDebug.info("SEED-RECEIVE-NET", "  Buffer state: #{@seed_buffer.inspect}")
    ##MultiplayerDebug.info("SEED-RECEIVE-NET", "=" * 70)

    # Validate battle context
    if defined?(CoopBattleState)
      unless CoopBattleState.validate_battle_context(battle_id, turn)
        ##MultiplayerDebug.warn("COOP-RNG", "Battle context validation failed for seed")
        return false
      end
    end

    # Check if we're currently waiting for this specific turn
    if @expected_turn && @expected_turn == turn.to_i
      # Perfect timing - we're waiting for this seed right now!
      @current_seed = seed.to_i
      @seed_received = true
      ##MultiplayerDebug.info("SEED-BUFFER-STORE", "✓ Stored immediately: turn=#{turn}, seed=#{@current_seed}")
      ##MultiplayerDebug.info("SEED-BUFFER-STORE", "  Matched expected_turn=#{@expected_turn}")
    elsif @expected_turn && @expected_turn != turn.to_i
      # We're waiting for a different turn - this might be for a future sync
      seed_int = seed.to_i
      ##MultiplayerDebug.info("SEED-BUFFER-STORE", "Buffering for turn #{turn}: seed=#{seed_int}")
      ##MultiplayerDebug.info("SEED-BUFFER-STORE", "  Expected turn was #{@expected_turn}, got #{turn}")
      ##MultiplayerDebug.info("SEED-BUFFER-STORE", "  Buffer before: #{@seed_buffer.inspect}")
      @seed_buffer[turn.to_i] = seed_int
      ##MultiplayerDebug.info("SEED-BUFFER-STORE", "  Buffer after: #{@seed_buffer.inspect}")
    else
      # @expected_turn is nil - not currently waiting, buffer it
      seed_int = seed.to_i
      ##MultiplayerDebug.info("SEED-BUFFER-STORE", "Early arrival, buffering: turn=#{turn}, seed=#{seed_int}")
      ##MultiplayerDebug.info("SEED-BUFFER-STORE", "  No active wait (@expected_turn=nil)")
      ##MultiplayerDebug.info("SEED-BUFFER-STORE", "  Buffer before: #{@seed_buffer.inspect}")
      @seed_buffer[turn.to_i] = seed_int
      ##MultiplayerDebug.info("SEED-BUFFER-STORE", "  Buffer after: #{@seed_buffer.inspect}")
    end

    true
  end

  #-----------------------------------------------------------------------------
  # Verify seed matches expected value (for debugging)
  #-----------------------------------------------------------------------------
  def self.verify_seed(expected_seed, actual_seed, context)
    if expected_seed != actual_seed
      ##MultiplayerDebug.error("SEED-MISMATCH", "=" * 70)
      ##MultiplayerDebug.error("SEED-MISMATCH", "SEED MISMATCH DETECTED!")
      ##MultiplayerDebug.error("SEED-MISMATCH", "  Context: #{context}")
      ##MultiplayerDebug.error("SEED-MISMATCH", "  Expected: #{expected_seed} (0x#{expected_seed.to_s(16)})")
      ##MultiplayerDebug.error("SEED-MISMATCH", "  Actual:   #{actual_seed} (0x#{actual_seed.to_s(16)})")
      ##MultiplayerDebug.error("SEED-MISMATCH", "  Diff:     #{(actual_seed - expected_seed).abs}")
      ##MultiplayerDebug.error("SEED-MISMATCH", "=" * 70)
      return false
    end
    return true
  end

  #-----------------------------------------------------------------------------
  # Reset RNG sync state
  #-----------------------------------------------------------------------------
  def self.reset_sync_state
    ##MultiplayerDebug.info("SEED-RESET", "=" * 70)
    ##MultiplayerDebug.info("SEED-RESET", "RESET RNG SYNC STATE CALLED")
    ##MultiplayerDebug.info("SEED-RESET", "  State BEFORE reset:")
    ##MultiplayerDebug.info("SEED-RESET", "    @current_seed = #{@current_seed}")
    ##MultiplayerDebug.info("SEED-RESET", "    @seed_received = #{@seed_received}")
    ##MultiplayerDebug.info("SEED-RESET", "    @expected_turn = #{@expected_turn}")
    ##MultiplayerDebug.info("SEED-RESET", "    @seed_buffer = #{@seed_buffer.inspect}")

    @current_seed = nil
    @seed_received = false
    @seed_wait_start_time = nil
    @expected_turn = nil
    @seed_buffer = {}

    ##MultiplayerDebug.info("SEED-RESET", "  State AFTER reset:")
    ##MultiplayerDebug.info("SEED-RESET", "    @seed_buffer = #{@seed_buffer.inspect} (should be empty {})")
    ##MultiplayerDebug.info("SEED-RESET", "RNG sync state reset complete")
    ##MultiplayerDebug.info("SEED-RESET", "=" * 70)
  end

  #-----------------------------------------------------------------------------
  # Get current seed (for debugging)
  #-----------------------------------------------------------------------------
  def self.current_seed
    @current_seed
  end

  #-----------------------------------------------------------------------------
  # Get battle RNG instance (deterministic RNG for battle calculations)
  #-----------------------------------------------------------------------------
  def self.battle_rng
    @battle_rng
  end

  #-----------------------------------------------------------------------------
  # Export sync statistics
  #-----------------------------------------------------------------------------
  def self.export_sync_stats
    {
      current_seed: @current_seed,
      seed_received: @seed_received,
      wait_duration: @seed_wait_start_time ? (Time.now - @seed_wait_start_time).round(3) : nil
    }
  end

  #-----------------------------------------------------------------------------
  # Test RNG determinism (debugging utility)
  # Generates 10 random numbers and logs them
  #-----------------------------------------------------------------------------
  def self.test_determinism(label = "TEST")
    results = []
    10.times do |i|
      r = rand(100)
      results << r
    end

    ##MultiplayerDebug.info("COOP-RNG-TEST", "[#{label}] Seed=#{@current_seed}, Results: #{results.inspect}")
    results
  end
end

#===============================================================================
# Integration Examples
#===============================================================================

# Example: In attack phase (011_Battle_Phase_Attack.rb)
# if CoopBattleState.in_coop_battle?
#   if CoopBattleState.am_i_initiator?
#     CoopRNGSync.sync_seed_as_initiator(self)
#   else
#     success = CoopRNGSync.sync_seed_as_receiver(self)
#     unless success
#       pbDisplay("RNG sync failed!")
#       @decision = 3
#       return
#     end
#   end
# end

# Example: Network handler in 002_Client.rb
# elsif data.start_with?("COOP_RNG_SEED:")
#   battle_id, turn, seed = data.sub("COOP_RNG_SEED:", "").split("|", 3)
#   CoopRNGSync.receive_seed(battle_id, turn.to_i, seed.to_i)

##MultiplayerDebug.info("MODULE-6", "CoopRNGSync loaded successfully")
