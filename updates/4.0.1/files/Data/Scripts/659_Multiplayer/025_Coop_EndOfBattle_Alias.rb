#===============================================================================
# MODULE 9: End of Battle Alias - Battle State Cleanup
#===============================================================================
# Wraps pbEndOfBattle to properly cleanup coop battle state tracking
# Ensures battle ID, participants, and timers are reset after battle ends
#===============================================================================

class PokeBattle_Battle
  # Save original method
  alias coop_original_pbEndOfBattle pbEndOfBattle

  def pbEndOfBattle
    # Check if battle was aborted due to disconnect (before calling original)
    abort_reason = @coop_abort_reason rescue nil

    # Call original end of battle (all vanilla cleanup logic)
    result = coop_original_pbEndOfBattle

    # Clear forceSingleBattle flag after battle ends
    $PokemonTemp.forceSingleBattle = false

    # Show accumulated platinum rewards from wild battle (if any)
    if defined?(MultiplayerClient) && MultiplayerClient.instance_variable_defined?(:@wild_platinum_accumulated)
      accumulated = MultiplayerClient.instance_variable_get(:@wild_platinum_accumulated)
      if accumulated && accumulated > 0
        # Check if platinum toast is enabled (default: true)
        toast_enabled = MultiplayerClient.instance_variable_get(:@platinum_toast_enabled)
        toast_enabled = true if toast_enabled.nil?

        if toast_enabled
          MultiplayerClient.enqueue_toast(_INTL("Earned {1} Platinum!", accumulated))
          ##MultiplayerDebug.info("WILD-PLAT", "Showed total platinum earned: #{accumulated}")
        else
          ##MultiplayerDebug.info("WILD-PLAT", "Platinum toast disabled, earned #{accumulated} (silent)")
        end
      end
      # Reset accumulator for next battle
      MultiplayerClient.instance_variable_set(:@wild_platinum_accumulated, 0)
    end

    # Show disconnect message if battle was aborted (safe to call here in main thread)
    if abort_reason
      begin
        pbMessage(_INTL("{1}", abort_reason))
        ##MultiplayerDebug.info("COOP-ABORT", "Showed disconnect message: #{abort_reason}")
      rescue => e
        ##MultiplayerDebug.warn("COOP-ABORT", "Failed to show disconnect message: #{e.message}")
      end
    end

    # MODULE 2: Coop Battle State Cleanup + MODULE 22: Whiteout Handling
    # Check if this is a coop battle and if player whited out
    if defined?(CoopBattleState) && CoopBattleState.active?
      # Notify server battle ended (clear queue slot)
      if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:send_data)
        MultiplayerClient.send_data("COOP_BATTLE_END")
      end

      if CoopBattleState.did_i_whiteout?
        # Player whited out - handle teleport, money loss, etc.
        handle_coop_whiteout
      else
        # Normal battle end - clean up state
        CoopBattleState.end_battle
        ##MultiplayerDebug.info("COOP-STATE", "Battle state cleaned up after battle end")
      end

      # Push fresh party snapshot after battle ends (levels/HP/EXP updated)
      # This ensures the next battle uses updated party data
      if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:coop_push_party_now!)
        begin
          MultiplayerClient.coop_push_party_now!
          ##MultiplayerDebug.info("COOP-END-BATTLE", "Pushed fresh party snapshot after battle end")
        rescue => e
          ##MultiplayerDebug.warn("COOP-END-BATTLE", "Failed to push party snapshot: #{e.message}")
        end
      end

      # Clear stale battle sync flags (joined SIDs) for next battle
      if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:reset_battle_sync)
        begin
          MultiplayerClient.reset_battle_sync
          ##MultiplayerDebug.info("COOP-END-BATTLE", "Cleared battle sync flags (joined SIDs)")
        rescue => e
          ##MultiplayerDebug.warn("COOP-END-BATTLE", "Failed to reset battle sync: #{e.message}")
        end
      end

      # Clear stale RNG seed buffer for next battle
      if defined?(CoopRNGSync) && CoopRNGSync.respond_to?(:reset_sync_state)
        begin
          CoopRNGSync.reset_sync_state
          ##MultiplayerDebug.info("COOP-END-BATTLE", "Cleared RNG seed buffer")
        rescue => e
          ##MultiplayerDebug.warn("COOP-END-BATTLE", "Failed to reset RNG sync state: #{e.message}")
        end
      end
    end

    return result
  end

  #-----------------------------------------------------------------------------
  # Handle whiteout aftermath for coop battles
  # Called when the local player's entire party fainted
  #-----------------------------------------------------------------------------
  def handle_coop_whiteout
    ##MultiplayerDebug.info("COOP-WHITEOUT", "=" * 70)
    ##MultiplayerDebug.info("COOP-WHITEOUT", "WHITEOUT AFTERMATH")
    ##MultiplayerDebug.info("COOP-WHITEOUT", "=" * 70)

    # 1. Heal all Pokemon (vanilla whiteout behavior)
    ##MultiplayerDebug.info("COOP-WHITEOUT", "Healing all Pokemon...")
    $Trainer.party.each { |pkmn| pkmn.heal if pkmn }

    # 2. Lose half money (vanilla whiteout behavior)
    if $Trainer.money > 0
      lost_money = ($Trainer.money / 2).floor
      $Trainer.money -= lost_money
      ##MultiplayerDebug.info("COOP-WHITEOUT", "Lost #{lost_money} money from whiteout")
    end

    # 3. Set teleport destination (Pokemon Center or home)
    pbCancelVehicles
    pbRemoveDependencies if defined?(pbRemoveDependencies)
    $game_switches[Settings::STARTING_OVER_SWITCH] = true if defined?(Settings::STARTING_OVER_SWITCH)

    if $PokemonGlobal && $PokemonGlobal.pokecenterMapId && $PokemonGlobal.pokecenterMapId >= 0
      # Teleport to last Pokemon Center
      ##MultiplayerDebug.info("COOP-WHITEOUT", "Setting teleport to Pokemon Center: Map #{$PokemonGlobal.pokecenterMapId}")

      $game_temp.player_transferring = true
      $game_temp.player_new_map_id = $PokemonGlobal.pokecenterMapId
      $game_temp.player_new_x = $PokemonGlobal.pokecenterX
      $game_temp.player_new_y = $PokemonGlobal.pokecenterY
      $game_temp.player_new_direction = $PokemonGlobal.pokecenterDirection
    else
      # No Pokemon Center visited - fall back to home (vanilla behavior)
      homedata = GameData::Metadata.get.home
      if homedata
        ##MultiplayerDebug.info("COOP-WHITEOUT", "No Pokemon Center set - teleporting to home: Map #{homedata[0]}")

        $game_temp.player_transferring = true
        $game_temp.player_new_map_id = homedata[0]
        $game_temp.player_new_x = homedata[1]
        $game_temp.player_new_y = homedata[2]
        $game_temp.player_new_direction = homedata[3]
      else
        ##MultiplayerDebug.warn("COOP-WHITEOUT", "WARNING: No Pokemon Center and no home data - player stays in place")
      end
    end

    # 4. Display whiteout message
    if $PokemonGlobal && $PokemonGlobal.pokecenterMapId && $PokemonGlobal.pokecenterMapId >= 0
      message = _INTL("{1} scurried to a Pokémon Center, protecting the exhausted and fainted Pokémon from further harm...", $Trainer.name)
    else
      message = _INTL("{1} scurried home, protecting the exhausted and fainted Pokémon from further harm...", $Trainer.name)
    end
    pbMessage(message)

    # 5. Clean up battle state AFTER message is dismissed
    CoopBattleState.end_battle
    ##MultiplayerDebug.info("COOP-WHITEOUT", "Whiteout aftermath complete")
    ##MultiplayerDebug.info("COOP-WHITEOUT", "=" * 70)
  end
end

##MultiplayerDebug.info("MODULE-9", "End of battle alias loaded - battle state cleanup enabled")
