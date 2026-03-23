#===============================================================================
# MODULE 3 & 5: Coop Battle Action Synchronization
#===============================================================================
# Handles collection, serialization, exchange, and synchronization of player
# battle actions across all participants in a coop battle
#===============================================================================

module CoopActionSync
  # Pending actions from remote players
  @pending_actions = {}  # { sid => action_data_hash }
  @expected_sids = []
  @sync_complete = false
  @sync_start_time = nil
  @current_turn = 0  # Track what turn we're currently waiting for

  # Remote player actions (for monkey-patching AI)
  @remote_player_actions = {}  # { sid => { battler_index => choice } }
  @remote_mega_flags = {}      # { sid => { battler_index => true } }

  # Future actions queue (actions received for future turns)
  # Format: { sid => { turn_number => action_data_hash } }
  @future_actions = {}

  #-----------------------------------------------------------------------------
  # Convert a choice array to serializable format
  # Replaces move objects with move indices to avoid Viewport serialization issues
  #-----------------------------------------------------------------------------
  def self.serialize_choice(choice, battler)
    return nil unless choice && choice.length > 0

    action_type = choice[0]
    serializable_choice = [action_type]

    case action_type
    when :UseMove
      # choice = [:UseMove, move_index, move_object, target_index]
      # We only need: [:UseMove, move_index, nil, target_index]
      move_index = choice[1]
      target_index = choice[3] if choice.length > 3
      serializable_choice = [:UseMove, move_index, nil, target_index]

    when :UseItem
      # choice = [:UseItem, item_id, item_target_index, move_target_index]
      serializable_choice = choice[0..3]

    when :SwitchOut
      # choice = [:SwitchOut, party_index, nil, -1]
      serializable_choice = choice[0..3]

    when :Run
      # choice = [:Run, nil, nil, nil]
      serializable_choice = [:Run, nil, nil, nil]

    else
      # For any other action type, try to copy without the move object
      serializable_choice = choice.dup
      serializable_choice[2] = nil if serializable_choice.length > 2  # Remove move object
    end

    serializable_choice
  end

  #-----------------------------------------------------------------------------
  # Reconstruct choice with move object from serialized format
  #-----------------------------------------------------------------------------
  def self.deserialize_choice(serialized_choice, battler)
    return nil unless serialized_choice && serialized_choice.length > 0

    action_type = serialized_choice[0]

    case action_type
    when :UseMove
      # Reconstruct: [:UseMove, move_index, move_object, target_index]
      move_index = serialized_choice[1]
      target_index = serialized_choice[3]

      # Get the actual move object from the battler
      if battler && battler.moves && move_index && move_index < battler.moves.length
        move_object = battler.moves[move_index]
        return [:UseMove, move_index, move_object, target_index]
      else
        # Fallback if we can't find the move
        return serialized_choice
      end

    else
      # Other actions don't need reconstruction
      return serialized_choice
    end
  end

  #-----------------------------------------------------------------------------
  # Extract player-controlled battler actions from battle
  # Returns: { battler_index => [action_type, param1, param2, target, priority] }
  #-----------------------------------------------------------------------------
  # Mega evolution flags extracted alongside actions
  @my_mega_flags = {}  # { battler_index => true/false }

  def self.extract_my_actions(battle)
    my_actions = {}
    @my_mega_flags = {}

    battle.battlers.each_with_index do |b, idx|
      next unless b && battle.pbOwnedByPlayer?(idx)

      # Check if this battler has mega evolution registered
      side  = b.idxOwnSide
      owner = battle.pbGetOwnerIndexFromBattlerIndex(idx)
      mega_val = battle.megaEvolution[side][owner] rescue nil
      MultiplayerDebug.info("COOP-MEGA", "extract: battler #{idx} side=#{side} owner=#{owner} megaEvolution=#{mega_val.inspect}")
      if mega_val == idx
        @my_mega_flags[idx] = true
        MultiplayerDebug.info("COOP-MEGA", "extract: *** MEGA FLAG SET for battler #{idx} ***")
      end

      # Get the choice for this battler
      choice = battle.choices[idx]
      if choice && choice.length > 0
        # Skip wasted turn choices (failed run attempts) - they shouldn't be sent
        # :None means the turn is wasted (NPCTrainers are skipped in AI phase now)
        if choice[0] == :None
          ##MultiplayerDebug.info("COOP-ACTION", "Skipping :None action for battler #{idx} (wasted turn)")
          next
        end

        # Convert to serializable format (removes move objects)
        serializable = serialize_choice(choice, b)
        my_actions[idx] = serializable
        ##MultiplayerDebug.info("COOP-ACTION", "Extracted action for battler #{idx}: #{serializable.inspect}")
      end
    end

    ##MultiplayerDebug.info("COOP-ACTION", "Extracted #{my_actions.length} player actions from battle")
    my_actions
  end

  #-----------------------------------------------------------------------------
  # Extract ALL actions (player + AI + remote players)
  # Used to send complete action set to allies so they can monkey-patch AI
  #-----------------------------------------------------------------------------
  def self.extract_all_actions_for_sync(battle)
    all_actions = {}
    my_sid = MultiplayerClient.session_id.to_s if defined?(MultiplayerClient)

    battle.battlers.each_with_index do |b, idx|
      next unless b

      # Only include actions for battlers owned by this client's player
      if battle.pbOwnedByPlayer?(idx)
        choice = battle.choices[idx]
        if choice && choice.length > 0
          all_actions[idx] = choice.dup
          ##MultiplayerDebug.info("COOP-ACTION", "Including local player action for battler #{idx}: #{choice.inspect}")
        end
      end
    end

    ##MultiplayerDebug.info("COOP-ACTION", "Extracted #{all_actions.length} actions for sync (only local player)")
    all_actions
  end

  #-----------------------------------------------------------------------------
  # Serialize actions to network format
  # Returns: hex-encoded string ready for transmission
  #-----------------------------------------------------------------------------
  def self.serialize_actions(turn_num, choices_hash, include_timestamp: true)
    timestamp_ms = include_timestamp ? (Time.now.to_f * 1000).to_i : nil

    data = {
      turn: turn_num,
      sid: MultiplayerClient.session_id.to_s,
      timestamp: timestamp_ms,
      choices: choices_hash
    }

    begin
      # Use JSON instead of Marshal for security
      # Convert symbol keys to strings for JSON compatibility
      json_data = {
        "turn" => data[:turn],
        "sid" => data[:sid],
        "timestamp" => data[:timestamp],
        "choices" => {},
        "mega" => {}
      }

      # Include mega evolution flags
      MultiplayerDebug.info("COOP-MEGA", "serialize: @my_mega_flags=#{(@my_mega_flags || {}).inspect}")
      (@my_mega_flags || {}).each do |battler_idx, flag|
        json_data["mega"][battler_idx.to_s] = flag if flag
      end

      # Convert choices hash: integer keys to strings, symbol values to tagged format
      data[:choices].each do |battler_idx, choice|
        choice_arr = choice.map do |v|
          if v.is_a?(Symbol)
            { "__sym__" => v.to_s }
          else
            v
          end
        end
        json_data["choices"][battler_idx.to_s] = choice_arr
      end

      json_str = MiniJSON.dump(json_data) if defined?(MiniJSON)
      hex = BinHex.encode(json_str) if defined?(BinHex)

      ##MultiplayerDebug.info("COOP-ACTION", "Serialized actions for turn #{turn_num}: #{json_str.length} bytes → #{hex.length} hex chars")

      return hex
    rescue => e
      ##MultiplayerDebug.error("COOP-ACTION", "Failed to serialize actions: #{e.class}: #{e.message}")
      return nil
    end
  end

  #-----------------------------------------------------------------------------
  # Deserialize received actions from hex format
  # Returns: hash with :turn, :sid, :timestamp, :choices
  #-----------------------------------------------------------------------------
  def self.deserialize_actions(hex_data, from_sid = nil)
    begin
      # Rate limiting check
      if from_sid && defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:check_marshal_rate_limit)
        unless MultiplayerClient.check_marshal_rate_limit(from_sid)
          ##MultiplayerDebug.warn("COOP-ACTION", "Dropped actions from #{from_sid} - rate limit exceeded")
          return nil
        end
      end

      # Size limit check (50KB max)
      max_size = 50_000
      if hex_data.to_s.length > max_size * 2  # Hex is 2x the binary size
        ##MultiplayerDebug.warn("COOP-ACTION", "Action data too large: #{hex_data.to_s.length} chars")
        return nil
      end

      json_str = BinHex.decode(hex_data.to_s) if defined?(BinHex)

      # Use JSON instead of Marshal for security
      json_data = MiniJSON.parse(json_str) if defined?(MiniJSON)

      unless json_data.is_a?(Hash)
        raise "Decoded action data is not a Hash (got #{json_data.class})"
      end

      # Convert back to symbol keys format expected by the rest of the code
      data = {
        turn: json_data["turn"],
        sid: json_data["sid"],
        timestamp: json_data["timestamp"],
        choices: {}
      }

      # Convert choices: string keys back to integers, tagged symbols back to symbols
      if json_data["choices"].is_a?(Hash)
        json_data["choices"].each do |battler_idx_str, choice_arr|
          battler_idx = battler_idx_str.to_i
          choice = choice_arr.map do |v|
            if v.is_a?(Hash) && v["__sym__"]
              v["__sym__"].to_sym
            else
              v
            end
          end
          data[:choices][battler_idx] = choice
        end
      end

      # Parse mega evolution flags
      data[:mega] = {}
      MultiplayerDebug.info("COOP-MEGA", "deserialize: raw mega json=#{json_data["mega"].inspect}")
      if json_data["mega"].is_a?(Hash)
        json_data["mega"].each do |battler_idx_str, flag|
          data[:mega][battler_idx_str.to_i] = flag if flag
        end
      end
      MultiplayerDebug.info("COOP-MEGA", "deserialize: parsed mega=#{data[:mega].inspect}")

      ##MultiplayerDebug.info("COOP-ACTION", "Deserialized actions from SID#{data[:sid]}: turn=#{data[:turn]}, choices=#{data[:choices].length}")

      return data
    rescue => e
      ##MultiplayerDebug.error("COOP-ACTION", "Failed to deserialize actions: #{e.class}: #{e.message}")
      return nil
    end
  end

  #-----------------------------------------------------------------------------
  # Validate action data integrity
  #-----------------------------------------------------------------------------
  def self.validate_actions(data, expected_turn, expected_battle_id = nil)
    # Check structure
    unless data.is_a?(Hash) && data[:turn] && data[:sid] && data[:choices]
      ##MultiplayerDebug.warn("COOP-ACTION", "Invalid action data structure")
      return false
    end

    # Check turn number
    unless data[:turn] == expected_turn
      ##MultiplayerDebug.warn("COOP-ACTION", "Turn mismatch! Expected: #{expected_turn}, Got: #{data[:turn]}")
      return false
    end

    # Check battle context if provided
    if expected_battle_id && defined?(CoopBattleState)
      unless CoopBattleState.validate_battle_context(expected_battle_id, expected_turn)
        ##MultiplayerDebug.warn("COOP-ACTION", "Battle context validation failed")
        return false
      end
    end

    # Check if sender is an ally
    if defined?(CoopBattleState)
      unless CoopBattleState.is_ally?(data[:sid])
        ##MultiplayerDebug.warn("COOP-ACTION", "Received actions from non-ally: SID#{data[:sid]}")
        return false
      end
    end

    ##MultiplayerDebug.info("COOP-ACTION", "Action data validated successfully")
    true
  end

  #-----------------------------------------------------------------------------
  # Send my actions to all allies
  #-----------------------------------------------------------------------------
  def self.send_my_actions(battle, my_actions)
    return false unless defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:send_data)
    return false unless defined?(CoopBattleState)

    battle_id = CoopBattleState.battle_id
    turn_num = battle.turnCount + 1  # Next turn

    hex = serialize_actions(turn_num, my_actions)
    return false unless hex

    message = "COOP_ACTION:#{battle_id}|#{turn_num}|#{hex}"
    MultiplayerClient.send_data(message, rate_limit_type: :ACTION)

    ##MultiplayerDebug.info("COOP-ACTION", "Sent #{my_actions.length} actions to server: turn=#{turn_num}, bytes=#{hex.length}")

    # Update debug HUD
    if defined?(CoopBattleDebugHUD)
      CoopBattleDebugHUD.set_message("Sent actions for turn #{turn_num}")
    end

    true
  end

  #-----------------------------------------------------------------------------
  # Broadcast that a run attempt failed and battler choice should be cleared
  #-----------------------------------------------------------------------------
  def self.broadcast_failed_run(battle_id, turn, battler_idx)
    return unless defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:send_data)

    message = "COOP_RUN_FAILED:#{battle_id}|#{turn}|#{battler_idx}"
    MultiplayerClient.send_data(message)
    ##MultiplayerDebug.info("COOP-RUN", "Broadcasted failed run for battler #{battler_idx}")
  end

  #-----------------------------------------------------------------------------
  # Receive failed run notification and clear the battler's choice
  #-----------------------------------------------------------------------------
  def self.receive_failed_run(battle, battle_id, turn, battler_idx)
    ##MultiplayerDebug.info("COOP-RUN", "Received failed run notification: battler=#{battler_idx}")

    # Clear the battler's choice
    if battle && battle.instance_variable_get(:@choices)
      choices = battle.instance_variable_get(:@choices)
      if choices[battler_idx]
        # Set to :None - NPCTrainers are now skipped in AI phase via pbCommandPhaseLoop override
        choices[battler_idx][0] = :None
        choices[battler_idx][1] = 0
        choices[battler_idx][2] = nil
        choices[battler_idx][3] = -1
        ##MultiplayerDebug.info("COOP-RUN", "  Cleared battler #{battler_idx} choice on non-initiator")
      end
    end
  end

  #-----------------------------------------------------------------------------
  # Receive actions from a remote player (called from network handler)
  #-----------------------------------------------------------------------------
  def self.receive_action(from_sid, battle_id, turn, hex_data)
    ##MultiplayerDebug.info("COOP-ACTION", "Received action from #{from_sid}: battle=#{battle_id}, turn=#{turn}")

    # Deserialize (with rate limiting)
    data = deserialize_actions(hex_data, from_sid)
    return false unless data

    # Validate basic structure and battle context
    unless data.is_a?(Hash) && data[:turn] && data[:sid] && data[:choices]
      ##MultiplayerDebug.warn("COOP-ACTION", "Invalid action data structure from #{from_sid}")
      return false
    end

    # Check if sender is an ally
    if defined?(CoopBattleState)
      unless CoopBattleState.is_ally?(data[:sid])
        ##MultiplayerDebug.warn("COOP-ACTION", "Received actions from non-ally: SID#{data[:sid]}")
        return false
      end
    end

    # CRITICAL: Handle turn mismatch (fast client sending future actions)
    received_turn = data[:turn]
    expected_turn = @current_turn  # Use the turn we're currently waiting for

    ##MultiplayerDebug.info("COOP-ACTION", "Turn check: received=#{received_turn}, expected=#{expected_turn}, current_turn=#{@current_turn}")

    if received_turn > expected_turn
      # Future action - queue it for later (even if expected_turn is still 0)
      ##MultiplayerDebug.info("COOP-ACTION", "⏰ EARLY ACTION from #{from_sid}: received turn #{received_turn}, expected #{expected_turn}")
      ##MultiplayerDebug.info("COOP-ACTION", "   Queueing for future use (speed mismatch handling or pre-battle arrival)")

      # Initialize future actions hash for this SID if needed
      @future_actions[from_sid.to_s] ||= {}
      @future_actions[from_sid.to_s][received_turn] = data
      MultiplayerDebug.info("COOP-MEGA", "future_queue: stored for #{from_sid} turn #{received_turn}, mega=#{data[:mega].inspect}")

      ##MultiplayerDebug.info("COOP-ACTION", "   Queued action for turn #{received_turn}. Future queue: #{@future_actions.keys.length} SIDs")

      return true  # Success, but don't mark as complete yet

    elsif received_turn < expected_turn
      # Old action - reject it
      ##MultiplayerDebug.warn("COOP-ACTION", "⏰ STALE ACTION from #{from_sid}: received turn #{received_turn}, expected #{expected_turn}")
      ##MultiplayerDebug.warn("COOP-ACTION", "   Rejecting old action (client is behind)")
      return false
    end

    # Turn matches - store it
    sid_key = from_sid.to_s
    @pending_actions[sid_key] = data
    @remote_player_actions[sid_key] = data[:choices]
    @remote_mega_flags[sid_key] = data[:mega] || {}
    MultiplayerDebug.info("COOP-MEGA", "receive: stored mega flags for #{sid_key}: #{@remote_mega_flags[sid_key].inspect}")

    ##MultiplayerDebug.info("COOP-ACTION", "✓ Stored action for current turn #{turn} from #{from_sid}")

    # Record latency if timestamp available
    if data[:timestamp] && defined?(CoopBattleDebugHUD)
      CoopBattleDebugHUD.record_latency(from_sid.to_s, data[:timestamp])
    end

    # Update debug HUD
    if defined?(CoopBattleDebugHUD)
      CoopBattleDebugHUD.update_action_status(from_sid.to_s, :received)
    end

    # Check if all received
    check_sync_complete

    ##MultiplayerDebug.info("COOP-ACTION", "Stored actions from #{from_sid}. Pending: #{@pending_actions.length}/#{@expected_sids.length}")
    ##MultiplayerDebug.info("COOP-ACTION", "Expected SIDs: #{@expected_sids.inspect}")
    ##MultiplayerDebug.info("COOP-ACTION", "Pending keys: #{@pending_actions.keys.inspect}")

    true
  end

  #-----------------------------------------------------------------------------
  # Check if all expected actions have been received
  #-----------------------------------------------------------------------------
  def self.check_sync_complete
    if @expected_sids.all? { |sid| @pending_actions.key?(sid.to_s) }
      @sync_complete = true
      ##MultiplayerDebug.info("COOP-ACTION", "All actions received! Sync complete.")

      if defined?(CoopBattleDebugHUD)
        CoopBattleDebugHUD.mark_sync_complete
      end
    end
  end

  #-----------------------------------------------------------------------------
  # Wait for all allies to send their actions
  # This is the main blocking loop that synchronizes turn start
  #-----------------------------------------------------------------------------
  def self.wait_for_all_actions(battle, timeout_seconds = 30)
    return true unless defined?(CoopBattleState)
    return true unless CoopBattleState.in_coop_battle?

    ally_sids = CoopBattleState.get_ally_sids
    return true if ally_sids.empty?  # Solo battle, no sync needed

    battle_id = CoopBattleState.battle_id
    turn_num = battle.turnCount + 1

    ##MultiplayerDebug.info("COOP-SYNC", "=" * 70)
    ##MultiplayerDebug.info("COOP-SYNC", "TURN SYNC STARTED")
    ##MultiplayerDebug.info("COOP-SYNC", "  Battle ID: #{battle_id}")
    ##MultiplayerDebug.info("COOP-SYNC", "  Turn: #{turn_num}")
    ##MultiplayerDebug.info("COOP-SYNC", "  Waiting for: #{ally_sids.join(', ')}")
    ##MultiplayerDebug.info("COOP-SYNC", "=" * 70)

    # Extract and send my actions first
    my_actions = extract_my_actions(battle)
    unless send_my_actions(battle, my_actions)
      ##MultiplayerDebug.error("COOP-SYNC", "Failed to send actions!")
      return false
    end

    # Initialize sync state
    @expected_sids = ally_sids.dup
    # DON'T reset @pending_actions - keep actions that were already received!
    # @pending_actions = {}
    @sync_complete = false
    @sync_start_time = Time.now
    @current_turn = turn_num  # Set the turn we're waiting for

    ##MultiplayerDebug.info("COOP-SYNC", "Set current_turn = #{@current_turn} for turn matching")

    # CRITICAL: Check future actions queue for early submissions (speed mismatch handling)
    # If fast clients already sent actions for this turn, pull them from the future queue
    ally_sids.each do |sid|
      sid_key = sid.to_s
      if @future_actions[sid_key] && @future_actions[sid_key][turn_num]
        # Found a queued action for this turn!
        queued_action = @future_actions[sid_key][turn_num]
        @pending_actions[sid_key] = queued_action
        @remote_player_actions[sid_key] = queued_action[:choices]
        @remote_mega_flags[sid_key] = queued_action[:mega] || {}
        MultiplayerDebug.info("COOP-MEGA", "future_queue PULL: #{sid_key} turn #{turn_num}, mega=#{@remote_mega_flags[sid_key].inspect}")
        @future_actions[sid_key].delete(turn_num)  # Remove from queue
        ##MultiplayerDebug.info("COOP-SYNC", "⏰ Retrieved early action from #{sid} (was queued from previous turn)")
      end
    end

    # Check if we already have some actions from before the wait started
    already_received = ally_sids.select { |sid| @pending_actions.key?(sid.to_s) }
    if already_received.any?
      ##MultiplayerDebug.info("COOP-SYNC", "Already have actions from: #{already_received.join(', ')}")
    end

    # Check if sync is already complete (all actions received before we started waiting)
    check_sync_complete
    if @sync_complete
      ##MultiplayerDebug.info("COOP-SYNC", "All actions already received! No wait needed.")
      ##MultiplayerDebug.info("COOP-SYNC", "=" * 70)
      ##MultiplayerDebug.info("COOP-SYNC", "TURN SYNC COMPLETE (instant)")
      ##MultiplayerDebug.info("COOP-SYNC", "  All #{@expected_sids.length} allies responded")
      ##MultiplayerDebug.info("COOP-SYNC", "=" * 70)
      return true
    end

    # Reset debug HUD status
    if defined?(CoopBattleDebugHUD)
      CoopBattleDebugHUD.reset_action_status
      CoopBattleDebugHUD.update_turn(turn_num)
      CoopBattleDebugHUD.set_message("Waiting for #{ally_sids.length} allies...")
    end

    # Wait loop
    timeout_time = Time.now + timeout_seconds
    frame_count = 0

    while !@sync_complete && Time.now < timeout_time
      # Update graphics to prevent freezing
      Graphics.update if defined?(Graphics)
      Input.update if defined?(Input)

      # CRITICAL: Check if battle ended (e.g., ally ran away successfully)
      if battle.decision != 0
        ##MultiplayerDebug.info("COOP-SYNC", "Battle ended during action sync (decision=#{battle.decision})")
        ##MultiplayerDebug.info("COOP-SYNC", "Breaking action sync wait loop")
        return true  # Exit sync immediately
      end

      # Check for F9 toggle (debug HUD)
      if defined?(CoopBattleDebugHUD)
        CoopBattleDebugHUD.check_toggle_input
      end

      # Periodic status updates (every 60 frames = ~1 second)
      frame_count += 1
      if frame_count % 60 == 0
        elapsed = (Time.now - @sync_start_time).round(1)
        pending_count = @pending_actions.length
        total_count = @expected_sids.length
        received_sids = @pending_actions.keys
        missing_sids = @expected_sids.reject { |sid| @pending_actions.key?(sid.to_s) }

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("COOP-SYNC", "Waiting... #{elapsed}s elapsed, #{pending_count}/#{total_count} received")
          MultiplayerDebug.info("COOP-SYNC", "  Received from: #{received_sids.join(', ')}")
          MultiplayerDebug.info("COOP-SYNC", "  Missing from: #{missing_sids.join(', ')}")
        end

        # File logging for 3-player diagnostics
        if defined?(CoopFileLogger) && elapsed >= 2.0
          CoopFileLogger.log("ACTION-WAIT", "Turn #{turn_num}: #{elapsed}s elapsed, #{pending_count}/#{total_count} received")
          CoopFileLogger.log("ACTION-WAIT", "  Received: #{received_sids.inspect}")
          CoopFileLogger.log("ACTION-WAIT", "  Missing: #{missing_sids.inspect}")
        end
      end

      # Small sleep to prevent CPU spinning
      sleep(0.016)  # ~60 FPS
    end

    # Check result
    if @sync_complete
      sync_duration = (Time.now - @sync_start_time).round(3)
      ##MultiplayerDebug.info("COOP-SYNC", "=" * 70)
      ##MultiplayerDebug.info("COOP-SYNC", "TURN SYNC COMPLETE")
      ##MultiplayerDebug.info("COOP-SYNC", "  Duration: #{sync_duration}s")
      ##MultiplayerDebug.info("COOP-SYNC", "  All #{@expected_sids.length} allies responded")
      ##MultiplayerDebug.info("COOP-SYNC", "=" * 70)

      if defined?(CoopBattleDebugHUD)
        CoopBattleDebugHUD.set_message("Sync complete! (#{sync_duration}s)")
      end

      return true
    else
      # Timeout
      missing_sids = @expected_sids.reject { |sid| @pending_actions.key?(sid.to_s) }
      received_sids = @pending_actions.keys

      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("COOP-SYNC", "=" * 70)
        MultiplayerDebug.error("COOP-SYNC", "TURN SYNC TIMEOUT")
        MultiplayerDebug.error("COOP-SYNC", "  Timeout: #{timeout_seconds}s")
        MultiplayerDebug.error("COOP-SYNC", "  Received: #{@pending_actions.length}/#{@expected_sids.length}")
        MultiplayerDebug.error("COOP-SYNC", "  Missing: #{missing_sids.join(', ')}")
        MultiplayerDebug.error("COOP-SYNC", "=" * 70)
      end

      # File logging for 3-player diagnostics
      if defined?(CoopFileLogger)
        CoopFileLogger.log_separator("ACTION SYNC TIMEOUT")
        CoopFileLogger.log("TIMEOUT", "Turn #{turn_num}: Action sync TIMEOUT after #{timeout_seconds}s")
        CoopFileLogger.log("TIMEOUT", "Expected from: #{@expected_sids.inspect}")
        CoopFileLogger.log("TIMEOUT", "Received from: #{received_sids.inspect}")
        CoopFileLogger.log("TIMEOUT", "MISSING from: #{missing_sids.inspect}")
        CoopFileLogger.dump_state
      end

      if defined?(CoopBattleDebugHUD)
        CoopBattleDebugHUD.set_message("TIMEOUT! Missing: #{missing_sids.join(', ')}")
      end

      return false
    end
  end

  #-----------------------------------------------------------------------------
  # Apply remote player actions to AI-controlled battlers (monkey-patch)
  # This overwrites AI decisions with the real choices from remote players
  # Returns: Array of local battler indices that need mega evolution
  #-----------------------------------------------------------------------------
  def self.apply_remote_player_actions(battle)
    return [] unless defined?(CoopBattleState)
    return [] unless CoopBattleState.in_coop_battle?

    applied_count = 0
    mega_indices = []  # Local battler indices that need mega evolution

    # For each remote player's actions
    @remote_player_actions.each do |sid, actions|
      # Build ordered queue of actions sorted by remote battler index
      action_queue = actions.sort_by { |remote_idx, _| remote_idx }

      # Mega flags for this remote player
      mega_flags = @remote_mega_flags[sid.to_s] || {}

      queue_pos = 0

      # Find which local battlers belong to this remote SID
      battle.battlers.each_with_index do |b, idx|
        begin
          next unless b
          trainer = battle.pbGetOwnerFromBattlerIndex(idx)
          next unless trainer
        rescue => e
          next
        end

        next unless trainer.is_a?(NPCTrainer) && trainer.respond_to?(:id)
        next unless trainer.id.to_s == sid.to_s

        # This battler belongs to the remote player
        if queue_pos < action_queue.length
          remote_idx, remote_choice = action_queue[queue_pos]
          queue_pos += 1

          if battle.choices[idx]
            reconstructed = deserialize_choice(remote_choice, b)
            battle.choices[idx] = reconstructed
            applied_count += 1

            # Set mega evolution flag so pbAttackPhaseMegaEvolution handles it
            if mega_flags[remote_idx]
              side  = b.idxOwnSide
              owner = battle.pbGetOwnerIndexFromBattlerIndex(idx)
              battle.megaEvolution[side][owner] = idx
              MultiplayerDebug.info("COOP-MEGA", "Remote battler #{remote_idx} (local #{idx}) — set megaEvolution flag")
            end
          end
        else
          # No more actions in queue — remote player skipped this battler
          if battle.choices[idx]
            battle.choices[idx] = [:None, 0, nil, -1]
            applied_count += 1
          end
        end
      end
    end

    MultiplayerDebug.info("COOP-ACTION", "Applied #{applied_count} remote actions, #{mega_indices.length} pending mega evolutions")
    mega_indices
  end

  #-----------------------------------------------------------------------------
  # Get received actions (for debugging/analysis)
  #-----------------------------------------------------------------------------
  def self.get_pending_actions
    @pending_actions.dup
  end

  #-----------------------------------------------------------------------------
  # Reset sync state (call at turn end)
  # IMPORTANT: Does NOT clear future_actions - those are preserved for next turn!
  #-----------------------------------------------------------------------------
  def self.reset_sync_state
    @pending_actions = {}
    @expected_sids = []
    @sync_complete = false
    @sync_start_time = nil
    # DO NOT reset @current_turn here - it tracks the last completed turn
    @remote_player_actions = {}
    @remote_mega_flags = {}
    @my_mega_flags = {}
    # DO NOT clear @future_actions here - preserve for next turn!

    ##MultiplayerDebug.info("COOP-ACTION", "Sync state reset (preserving future actions queue, current_turn=#{@current_turn})")
  end

  #-----------------------------------------------------------------------------
  # Full reset including future actions (call only at battle start/end)
  #-----------------------------------------------------------------------------
  def self.full_reset
    @pending_actions = {}
    @expected_sids = []
    @sync_complete = false
    @sync_start_time = nil
    @current_turn = 0
    @remote_player_actions = {}
    @remote_mega_flags = {}
    @my_mega_flags = {}
    @future_actions = {}  # Clear future actions queue

    ##MultiplayerDebug.info("COOP-ACTION", "FULL sync state reset (including future actions queue)")
  end

  #-----------------------------------------------------------------------------
  # Export sync statistics (for debugging)
  #-----------------------------------------------------------------------------
  def self.export_sync_stats
    {
      sync_complete: @sync_complete,
      expected_count: @expected_sids.length,
      received_count: @pending_actions.length,
      pending_sids: @expected_sids.dup,
      received_sids: @pending_actions.keys,
      sync_duration: @sync_start_time ? (Time.now - @sync_start_time).round(3) : nil
    }
  end

  #-----------------------------------------------------------------------------
  # Get current turn number (for logging)
  #-----------------------------------------------------------------------------
  def self.current_turn
    @current_turn || 0
  end
end

#===============================================================================
# Integration Examples
#===============================================================================

# Example: In command phase (010_Battle_Phase_Command.rb)
# if CoopBattleState.in_coop_battle?
#   success = CoopActionSync.wait_for_all_actions(self)
#   unless success
#     pbDisplay("Connection lost. Ending battle...")
#     @decision = 3  # Forfeit
#     return
#   end
# end

# Example: Network handler in 002_Client.rb
# elsif data.start_with?("COOP_ACTION:")
#   battle_id, turn, hex = data.sub("COOP_ACTION:", "").split("|", 3)
#   CoopActionSync.receive_action(from_sid, battle_id, turn.to_i, hex)

##MultiplayerDebug.info("MODULE-3", "CoopActionSync loaded successfully")
