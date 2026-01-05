#===============================================================================
# Co-op Battle Capture - Complete Fix
#===============================================================================
# Fixes three issues:
# 1. Shows correct thrower name in pokeball message
# 2. Marks caught Pokemon with catcher's SID for storage filtering
# 3. Broadcasts capture to other players to prevent overlay freeze
#===============================================================================

class PokeBattle_Battle
  attr_accessor :current_thrower_idx
  attr_accessor :coop_last_catcher  # Store the trainer object who last caught a Pokemon

  alias coop_capture_complete_original_pbThrowPokeBall pbThrowPokeBall

  def pbThrowPokeBall(idxBattler, ball, catch_rate=nil, showPlayer=false)
    # Store thrower index for pbPlayer hook
    # In coop, find who's actually using the item by checking choices
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      @current_thrower_idx = nil
      # Find which player-side battler chose UseItem action
      @battlers.each_with_index do |b, i|
        next if !b || b.opposes?(0)  # Skip nil and enemies
        if @choices[i] && @choices[i][0] == :UseItem
          @current_thrower_idx = i
          break
        end
      end
      @current_thrower_idx ||= idxBattler  # Fallback
    end

    # Track caught count before throw
    caught_before = @caughtPokemon ? @caughtPokemon.length : 0

    # Identify my battlers by SID
    my_battler_indices = []
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      my_sid = MultiplayerClient.session_id.to_s rescue nil
      @battlers.each_with_index do |b, i|
        next if !b || b.opposes?(0)
        owner = pbGetOwnerFromBattlerIndex(i) rescue nil
        next unless owner
        owner_sid = owner.respond_to?(:multiplayer_sid) ? owner.multiplayer_sid.to_s : (owner == $Trainer ? my_sid : nil)
        my_battler_indices << i if owner_sid == my_sid || owner == $Trainer
      end
    end

    # Call original
    result = coop_capture_complete_original_pbThrowPokeBall(idxBattler, ball, catch_rate, showPlayer)

    # Mark catcher SID and broadcast if captured
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      caught_after = @caughtPokemon ? @caughtPokemon.length : 0

      if caught_after > caught_before && @caughtPokemon && @caughtPokemon.length > 0
        caught_pkmn = @caughtPokemon.last

        # Get the trainer who caught it from @current_thrower_idx
        # Don't use caught_pkmn.owner - that's a Pokemon::Owner struct, not the trainer object
        my_sid = MultiplayerClient.session_id.to_s rescue nil
        catcher_trainer = nil

        if @current_thrower_idx && @battlers[@current_thrower_idx]
          owner_idx = pbGetOwnerIndexFromBattlerIndex(@current_thrower_idx) rescue -1
          catcher_trainer = @player[owner_idx] if owner_idx >= 0 && @player && @player[owner_idx]
        end

        if catcher_trainer
          is_mine = (catcher_trainer == $Trainer)
          MultiplayerDebug.info("🎯 CAPTURE-SID", "Pokemon: #{caught_pkmn.name}, catcher: #{catcher_trainer.name}, is_mine: #{is_mine}") if defined?(MultiplayerDebug)

          # Store catcher for pbPlayer hook during pbStorePokemon
          @coop_last_catcher = catcher_trainer

          # Mark SID
          if is_mine
            caught_pkmn.instance_variable_set(:@coop_catcher_sid, my_sid) if my_sid
            MultiplayerDebug.info("✅ CAPTURE-SID", "Marked with my SID: #{my_sid}") if defined?(MultiplayerDebug)
          else
            remote_sid = catcher_trainer.respond_to?(:multiplayer_sid) ? catcher_trainer.multiplayer_sid.to_s : nil
            if remote_sid && !remote_sid.empty?
              caught_pkmn.instance_variable_set(:@coop_catcher_sid, remote_sid)
              MultiplayerDebug.info("✅ CAPTURE-SID", "Marked with remote SID: #{remote_sid}") if defined?(MultiplayerDebug)
            else
              MultiplayerDebug.error("❌ CAPTURE-SID", "Remote trainer has no SID") if defined?(MultiplayerDebug)
            end
          end
        else
          MultiplayerDebug.error("❌ CAPTURE-SID", "Could not determine catcher trainer") if defined?(MultiplayerDebug)
        end

        # Broadcast capture to other players (only if shake_count == 4)
        if result == 4 && defined?(MultiplayerClient) && MultiplayerClient.connected?
          begin
            battle_id = CoopBattleState.battle_id
            my_sid = MultiplayerClient.session_id.to_s
            MultiplayerClient.send_battle_capture_complete(battle_id, my_sid)
          rescue => e
            MultiplayerDebug.error("CAPTURE-SYNC", "Broadcast failed: #{e.message}") if defined?(MultiplayerDebug)
          end
        end
      end
    end

    # Clear thrower index after SID marking
    @current_thrower_idx = nil

    return result
  end

  # Hook pbPlayer to return correct thrower
  alias coop_capture_complete_original_pbPlayer pbPlayer

  def pbPlayer
    # In coop, return the last catcher if available (for rename/sprite prompts)
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle? && @coop_last_catcher
      MultiplayerDebug.info("🎾 PBPLAYER", "Returning last catcher: #{@coop_last_catcher.name}") if defined?(MultiplayerDebug)
      return @coop_last_catcher
    end

    # During ball throw, use current_thrower_idx
    if @current_thrower_idx && defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      battler = @battlers[@current_thrower_idx]
      if battler && battler.pokemonIndex >= 0
        owner_idx = pbGetOwnerIndexFromBattlerIndex(@current_thrower_idx) rescue -1
        if owner_idx >= 0 && @player && @player[owner_idx]
          MultiplayerDebug.info("🎾 PBPLAYER", "Returning thrower: #{@player[owner_idx].name}") if defined?(MultiplayerDebug)
          return @player[owner_idx]
        end
      end
    end

    result = coop_capture_complete_original_pbPlayer
    MultiplayerDebug.info("🎾 PBPLAYER", "Returning original: #{result ? result.name : 'nil'}") if defined?(MultiplayerDebug)
    return result
  end
end

#===============================================================================
# Network Client - Capture Complete Message
#===============================================================================

module MultiplayerClient
  def self.send_battle_capture_complete(battle_id, catcher_sid)
    return unless @client_socket && @connected
    msg = {
      type: "COOP_CAPTURE_COMPLETE",
      battle_id: battle_id,
      catcher_sid: catcher_sid,
      timestamp: Time.now.to_i
    }
    send_message(msg)
  rescue => e
    MultiplayerDebug.error("CAPTURE-SYNC", "Send failed: #{e.message}") if defined?(MultiplayerDebug)
  end

  def self._handle_coop_capture_complete(catcher_sid, battle_id)
    if defined?(CoopBattleState) && CoopBattleState.battle_instance
      battle = CoopBattleState.battle_instance
      battle.instance_variable_set(:@decision, 4)
      # Mark all opponent battlers as fainted
      battle.battlers.each_with_index do |battler, i|
        battler.instance_variable_set(:@hp, 0) if battler && battle.opposes?(i) && !battler.fainted?
      end
    end
  rescue => e
    MultiplayerDebug.error("CAPTURE-RCV", "Handle failed: #{e.message}") if defined?(MultiplayerDebug)
  end

  if defined?(MESSAGE_HANDLERS)
    MESSAGE_HANDLERS["COOP_CAPTURE_COMPLETE"] = lambda do |msg|
      _handle_coop_capture_complete(msg["catcher_sid"], msg["battle_id"])
    end
  end
end
