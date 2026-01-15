# ===========================================
# File: 127_PvP_ActionSync.rb
# Purpose: PvP Battle Action Synchronization
# Phase: 5 - Action Synchronization
# ===========================================
# Handles collection, serialization, exchange, and synchronization of player
# battle actions between both PvP participants.
# Adapted from CoopActionSync (021_Coop_ActionSync.rb) for PvP battles.
#===============================================================================

module PvPActionSync
  # Opponent's choice
  @opponent_choice = nil
  @choice_received = false
  @choice_wait_start_time = nil
  @current_turn = 0
  @choice_buffer = {}  # Buffer for choices that arrived early: { turn => choice }

  #-----------------------------------------------------------------------------
  # Convert a choice array to serializable format
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
      serializable_choice[2] = nil if serializable_choice.length > 2
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
        return serialized_choice
      end

    else
      # Other actions don't need reconstruction
      return serialized_choice
    end
  end

  #-----------------------------------------------------------------------------
  # Extract my action from battle (PvP: only one battler per player in Phase 4)
  #-----------------------------------------------------------------------------
  def self.extract_my_action(battle)
    # Phase 4: Always 1v1, so my battler is index 0
    my_battler_idx = 0
    battler = battle.battlers[my_battler_idx]

    return nil unless battler

    choice = battle.choices[my_battler_idx]
    if choice && choice.length > 0 && choice[0] != :None
      serializable = serialize_choice(choice, battler)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-ACTION", "Extracted my action: #{serializable.inspect}")
      end

      return serializable
    end

    nil
  end

  #-----------------------------------------------------------------------------
  # Wait for opponent's action and apply it to battle
  #-----------------------------------------------------------------------------
  def self.wait_for_opponent_action(battle, timeout_seconds = 10)
    return false unless defined?(PvPBattleState)
    return false unless PvPBattleState.in_pvp_battle?

    battle_id = PvPBattleState.battle_id
    turn_num = battle.turnCount + 1  # Same as coop: use next turn number

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-ACTION", "Waiting for opponent's action: turn=#{turn_num}")
    end

    # Send my action first
    my_action = extract_my_action(battle)
    if my_action
      send_action(battle_id, turn_num, my_action)
    else
      if defined?(MultiplayerDebug)
        MultiplayerDebug.warn("PVP-ACTION", "No action to send (might be fine for some situations)")
      end
    end

    # Set expected turn
    @current_turn = turn_num

    # Check if choice already in buffer
    if @choice_buffer[turn_num]
      @opponent_choice = @choice_buffer[turn_num]
      @choice_received = true
      @choice_buffer.delete(turn_num)
      @choice_wait_start_time = Time.now

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-ACTION", "Retrieved choice from buffer: #{@opponent_choice.inspect}")
      end
    else
      # Reset state
      @choice_received = false
      @opponent_choice = nil
      @choice_wait_start_time = Time.now

      # Wait for opponent's action
      timeout_time = Time.now + timeout_seconds

      while !@choice_received && Time.now < timeout_time
        Graphics.update if defined?(Graphics)
        Input.update if defined?(Input)
        sleep(0.016)  # ~60 FPS
      end
    end

    # Check if received
    if @choice_received && @opponent_choice
      # Find opponent's battler by matching trainer SID (same as coop)
      opponent_sid = PvPBattleState.opponent_sid
      opponent_battler_idx = nil
      opponent_battler = nil

      battle.battlers.each_with_index do |b, idx|
        next unless b

        # Get trainer for this battler
        trainer = battle.pbGetOwnerFromBattlerIndex(idx)
        next unless trainer

        # Check if this is an NPCTrainer with matching SID
        if trainer.is_a?(NPCTrainer) && trainer.respond_to?(:id)
          if trainer.id.to_s == opponent_sid.to_s
            opponent_battler_idx = idx
            opponent_battler = b
            break
          end
        end
      end

      if opponent_battler && opponent_battler_idx
        # Deserialize choice (reconstruct move object if needed)
        full_choice = deserialize_choice(@opponent_choice, opponent_battler)

        # Set opponent's choice
        battle.choices[opponent_battler_idx] = full_choice

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-ACTION", "Applied opponent's action to battler #{opponent_battler_idx}: #{full_choice.inspect}")
        end

        return true
      else
        if defined?(MultiplayerDebug)
          MultiplayerDebug.error("PVP-ACTION", "Opponent battler not found (SID: #{opponent_sid})")
        end
        return false
      end
    else
      # Timeout
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-ACTION", "Action sync timeout after #{timeout_seconds}s")
      end
      return false
    end
  end

  #-----------------------------------------------------------------------------
  # Send my action to opponent
  #-----------------------------------------------------------------------------
  def self.send_action(battle_id, turn_num, choice)
    begin
      # Serialize action
      data = {
        turn: turn_num,
        choice: choice
      }

      raw = Marshal.dump(data)
      hex = BinHex.encode(raw) if defined?(BinHex)

      # Send to opponent
      message = "PVP_CHOICE:#{battle_id}|#{hex}"
      MultiplayerClient.send_data(message, rate_limit_type: :CHOICE) if defined?(MultiplayerClient)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-ACTION", "Sent action to opponent: turn=#{turn_num}, choice=#{choice.inspect}")
      end

      return true
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-ACTION", "Failed to send action: #{e.message}")
      end
      return false
    end
  end

  #-----------------------------------------------------------------------------
  # Receive opponent's action from network
  #-----------------------------------------------------------------------------
  def self.receive_action(battle_id, hex_data)
    begin
      # Deserialize action
      raw = BinHex.decode(hex_data.to_s) if defined?(BinHex)

      # SAFE MARSHAL: Size limit + validation
      max_size = 10_000
      data = SafeMarshal.load(raw, max_size: max_size) if defined?(SafeMarshal)
      SafeMarshal.validate(data) if defined?(SafeMarshal)

      unless data.is_a?(Hash)
        raise "Decoded action data is not a Hash (got #{data.class})"
      end

      turn = data[:turn]
      choice = data[:choice]

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-ACTION-NET", "Received action: turn=#{turn}, choice=#{choice.inspect}")
      end

      # Validate battle context
      if defined?(PvPBattleState)
        unless PvPBattleState.battle_id == battle_id
          if defined?(MultiplayerDebug)
            MultiplayerDebug.warn("PVP-ACTION", "Battle ID mismatch")
          end
          return false
        end
      end

      # Check if this is for the current turn
      if @current_turn > 0 && turn.to_i == @current_turn
        @opponent_choice = choice
        @choice_received = true

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-ACTION", "Stored opponent's choice for turn #{turn}")
        end
      else
        # Buffer for later (action arrived before wait_for_opponent_action was called)
        @choice_buffer[turn.to_i] = choice

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-ACTION", "Buffered choice for turn #{turn}: #{choice.inspect}")
        end
      end

      return true
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-ACTION", "Failed to receive action: #{e.message}")
      end
      return false
    end
  end

  #-----------------------------------------------------------------------------
  # Reset action sync state
  #-----------------------------------------------------------------------------
  def self.reset_sync_state
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-ACTION", "Resetting action sync state")
    end

    @opponent_choice = nil
    @choice_received = false
    @choice_wait_start_time = nil
    @current_turn = 0
    @choice_buffer = {}
  end
end

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("PVP-ACTION", "PvP action sync module loaded")
end
