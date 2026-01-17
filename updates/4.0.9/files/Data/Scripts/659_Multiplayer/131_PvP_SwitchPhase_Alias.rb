# ===========================================
# File: 130_PvP_SwitchPhase_Alias.rb
# Purpose: PvP Battle Switch Phase Alias - Synchronize Pokemon Switches
# Phase: 6 - Switch Synchronization
# ===========================================
# Wraps pbSwitchInBetween to synchronize Pokemon switch choices when a Pokemon faints
# in PvP battles. This prevents desync where one client auto-switches while the other
# waits for player input.
#
# Problem: When opponent's Pokemon faints in PvP battles:
#   - On your screen: Auto-switches to next Pokemon (AI decision)
#   - On opponent's screen: Prompts player to choose which Pokemon to switch to
#   - Result: DESYNC if different Pokemon are chosen
#
# Solution:
#   - When opponent's Pokemon faints, wait for their switch choice
#   - When your Pokemon faints, send the switch choice to opponent
#   - Both clients use the synchronized switch choice
#
# Adapted from coop pattern (031_Coop_SwitchPhase_Alias.rb)
#===============================================================================

class PokeBattle_Battle
  # Save original method if not already saved
  unless defined?(pvp_original_pbSwitchInBetween)
    alias pvp_original_pbSwitchInBetween pbSwitchInBetween
  end

  #-----------------------------------------------------------------------------
  # Wrap pbSwitchInBetween to synchronize switch choices
  # Called when a Pokemon faints and needs to be replaced
  #-----------------------------------------------------------------------------
  def pbSwitchInBetween(idxBattler, canCancel = false, canChooseCurrent = false)
    # If not in PvP battle, use original behavior
    unless defined?(PvPBattleState) && PvPBattleState.in_pvp_battle?
      return pvp_original_pbSwitchInBetween(idxBattler, canCancel, canChooseCurrent)
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-SWITCH-PHASE", "=== SWITCH IN BETWEEN ===")
      MultiplayerDebug.info("PVP-SWITCH-PHASE", "  Battler Index: #{idxBattler}")
    end

    battler = @battlers[idxBattler]
    owner = pbGetOwnerFromBattlerIndex(idxBattler)

    # Determine if this is opponent's Pokemon
    is_opponent = false
    opponent_sid = PvPBattleState.opponent_sid

    if owner.is_a?(NPCTrainer) && owner.respond_to?(:id)
      # Check if this NPCTrainer is the opponent
      is_opponent = (owner.id.to_s == opponent_sid.to_s)
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-SWITCH-PHASE", "  Owner: #{owner.class.name}")
      MultiplayerDebug.info("PVP-SWITCH-PHASE", "  Is Opponent: #{is_opponent}")
    end

    if is_opponent
      # OPPONENT'S POKEMON - Wait for their switch choice
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-SWITCH-PHASE", "Waiting for opponent's switch choice...")
      end

      idxPartyNew = PvPSwitchSync.wait_for_switch(idxBattler, 120) if defined?(PvPSwitchSync)

      # Check if opponent forfeited (returns -1)
      if idxPartyNew == -1
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-SWITCH-PHASE", "Opponent forfeited during switch - we win!")
        end
        pbDisplay(_INTL("Your opponent forfeited!"))
        return -1  # Signal no switch needed, battle ending
      elsif idxPartyNew.nil?
        # Timeout - fallback to auto-switch
        if defined?(MultiplayerDebug)
          MultiplayerDebug.error("PVP-SWITCH-PHASE", "Timeout! Using fallback auto-switch")
        end
        idxPartyNew = pvp_original_pbSwitchInBetween(idxBattler, canCancel, canChooseCurrent)
      else
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-SWITCH-PHASE", "Received opponent's choice: party index #{idxPartyNew}")
        end
      end

      return idxPartyNew

    else
      # MY POKEMON - Get my choice and send it to opponent
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-SWITCH-PHASE", "My Pokemon switching, choosing and broadcasting...")
      end

      begin
        idxPartyNew = pvp_original_pbSwitchInBetween(idxBattler, canCancel, canChooseCurrent)

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-SWITCH-PHASE", "pbSwitchInBetween returned: #{idxPartyNew.inspect}")
        end

        if idxPartyNew >= 0
          if defined?(MultiplayerDebug)
            MultiplayerDebug.info("PVP-SWITCH-PHASE", "My choice: party index #{idxPartyNew}, sending to opponent...")
          end

          if defined?(PvPSwitchSync)
            PvPSwitchSync.send_switch_choice(idxBattler, idxPartyNew)
            if defined?(MultiplayerDebug)
              MultiplayerDebug.info("PVP-SWITCH-PHASE", "✓ Switch choice sent successfully")
            end
          else
            if defined?(MultiplayerDebug)
              MultiplayerDebug.error("PVP-SWITCH-PHASE", "✗ PvPSwitchSync not defined!")
            end
          end
        else
          if defined?(MultiplayerDebug)
            MultiplayerDebug.warn("PVP-SWITCH-PHASE", "No valid switch available (returned #{idxPartyNew})")
          end
        end

        return idxPartyNew
      rescue => e
        if defined?(MultiplayerDebug)
          MultiplayerDebug.error("PVP-SWITCH-PHASE", "✗ Exception in MY switch: #{e.message}")
          MultiplayerDebug.error("PVP-SWITCH-PHASE", "Backtrace: #{e.backtrace.first(5).join('\n')}")
        end
        raise
      end
    end
  end

  # Hook into pbOnActiveOne to resync RNG before switch-in effects (like coop)
  unless defined?(pvp_original_pbOnActiveOne)
    alias pvp_original_pbOnActiveOne pbOnActiveOne if method_defined?(:pbOnActiveOne)
  end

  def pbOnActiveOne(battler)
    if defined?(PvPBattleState) && PvPBattleState.in_pvp_battle?
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-SWITCH-PHASE", "Switch-in effects for battler #{battler.index} (#{battler.pokemon.name})")
      end

      # CRITICAL: Resync RNG seed BEFORE switch-in effects
      # This ensures abilities, entry hazards, and items trigger identically
      # Skip at Turn 0 to preserve initial seed
      # ONLY resync when it's MY Pokemon switching in (to avoid double-sync race condition)
      # ALSO skip for voluntary switches (they don't need RNG sync, only forced switches when Pokemon faint)
      owner = pbGetOwnerFromBattlerIndex(battler.index)
      is_my_pokemon = owner && !owner.is_a?(NPCTrainer)  # My Pokemon = Player-owned, not NPCTrainer

      # Simple detection: Check if we're in the attack phase
      # Voluntary switches happen BEFORE attack phase (during command phase)
      # Forced switches happen AFTER attack phase (when Pokemon faint)
      # We can detect this by checking if @phase exists and is attack phase
      is_in_attack_phase = defined?(@phase) && (@phase == :attack || @phase == 4)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-SWITCH-PHASE", "  In attack phase: #{is_in_attack_phase}")
        MultiplayerDebug.info("PVP-SWITCH-PHASE", "  @phase: #{defined?(@phase) ? @phase : 'undefined'}")
      end

      # Only sync RNG for switches during/after attack phase (forced switches)
      # Skip sync for switches during command phase (voluntary switches)
      if defined?(PvPRNGSync) && @turnCount > 0 && is_my_pokemon && is_in_attack_phase
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-SWITCH-PHASE", "Resyncing RNG before MY switch-in effects...")
        end

        # Use negative sync ID to avoid collision with turn numbers
        sync_id = -((@turnCount * 100) + battler.index + 1)

        if PvPBattleState.is_initiator?
          PvPRNGSync.sync_seed_as_initiator(self, sync_id)
        else
          success = PvPRNGSync.sync_seed_as_receiver(self, sync_id, 3)
          unless success
            if defined?(MultiplayerDebug)
              MultiplayerDebug.error("PVP-SWITCH-PHASE", "RNG resync failed before switch-in!")
            end
          end
        end

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-SWITCH-PHASE", "RNG resynced (sync_id=#{sync_id})")
        end
      elsif defined?(PvPRNGSync) && @turnCount > 0 && !is_my_pokemon
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-SWITCH-PHASE", "Opponent's switch-in, waiting for RNG resync from them...")
        end
        # Opponent will trigger the resync on their end
      end
    end

    # Call original (triggers entry hazards, abilities, etc.)
    pvp_original_pbOnActiveOne(battler)
  end
end

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("PVP-SWITCH-ALIAS", "PvP switch phase alias loaded")
end
