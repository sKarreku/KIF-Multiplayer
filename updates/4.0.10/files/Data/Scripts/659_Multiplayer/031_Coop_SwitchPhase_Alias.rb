#===============================================================================
# MODULE 14: Battle Switch Phase Alias - Synchronize Pokemon Switches
#===============================================================================
# Wraps pbEORSwitch and pbGetReplacementPokemonIndex to synchronize Pokemon
# switch choices when a Pokemon faints in coop battles. This prevents desync
# where one client auto-switches to the next Pokemon while another client waits
# for player input.
#
# Problem: When a remote player's Pokemon faints in coop battles:
#   - On initiator: Auto-switches to next Pokemon (AI decision via pbSwitchInBetween)
#   - On non-initiator (owner): Prompts player to choose which Pokemon to switch to
#   - Result: DESYNC if different Pokemon are chosen
#
# Solution:
#   - When a remote player's Pokemon faints, wait for their switch choice
#   - When a local player's Pokemon faints, send the switch choice to allies
#   - All clients use the synchronized switch choice
#===============================================================================

class PokeBattle_Battle
  # Save original method
  alias coop_original_pbSwitchInBetween pbSwitchInBetween

  #-----------------------------------------------------------------------------
  # Wrap pbSwitchInBetween to synchronize switch choices
  # This is called for NPCTrainers (remote players) in line 161 of pbEORSwitch
  #-----------------------------------------------------------------------------
  def pbSwitchInBetween(idxBattler, canCancel = false, canChooseCurrent = false)
    # If not in coop battle, use original behavior
    unless defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      return coop_original_pbSwitchInBetween(idxBattler, canCancel, canChooseCurrent)
    end

    # Mark RNG phase for debugging
    if defined?(CoopRNGDebug)
      CoopRNGDebug.set_phase("SWITCH_CHOOSING")
      CoopRNGDebug.checkpoint("before_switch_choice_#{idxBattler}")
    end

    ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "=" * 70)
    ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "SWITCH IN BETWEEN")
    ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "  Battler Index: #{idxBattler}")
    ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "  Can Cancel: #{canCancel}")
    ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "  Can Choose Current: #{canChooseCurrent}")

    battler = @battlers[idxBattler]
    ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "  Battler: #{battler.pokemon.name}")

    # Determine the owner
    owner = pbGetOwnerFromBattlerIndex(idxBattler)
    my_sid = MultiplayerClient.session_id.to_s

    # Check if this is a remote player's Pokemon (NPCTrainer with different SID)
    is_remote_player = false
    is_enemy = false
    owner_sid = nil

    if owner.is_a?(NPCTrainer)
      owner_sid = owner.id
      is_enemy = opposes?(idxBattler)  # Check if this is an enemy trainer (CPU opponent)
      is_remote_player = (owner_sid != my_sid) && !is_enemy  # Remote ally, NOT enemy CPU
    end

    ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "  Owner: #{owner.class.name}")
    ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "  Owner SID: #{owner_sid}")
    ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "  My SID: #{my_sid}")
    ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "  Is Enemy: #{is_enemy}")
    ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "  Is Remote Player: #{is_remote_player}")

    if is_enemy
      # CASE 0: Enemy CPU trainer switching - use AI immediately, don't wait for network
      ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "🎯 Enemy CPU switching - using AI")
      idxPartyNew = coop_original_pbSwitchInBetween(idxBattler, canCancel, canChooseCurrent)
      ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "=" * 70)
      return idxPartyNew

    elsif is_remote_player
      # CASE 1: Remote player's Pokemon switching on my client
      # Wait for the remote player to choose their switch
      ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "⏳ WAITING for remote player #{owner_sid} to choose switch")

      idxPartyNew = CoopSwitchSync.wait_for_switch(owner_sid, 30)

      if idxPartyNew.nil?
        # Timeout - fallback to auto-switch
        ##MultiplayerDebug.error("COOP-SWITCH-PHASE", "⏰ TIMEOUT waiting for switch from #{owner_sid}, using fallback")
        idxPartyNew = coop_original_pbSwitchInBetween(idxBattler, canCancel, canChooseCurrent)
      else
        ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "✓ Received switch choice from #{owner_sid}: party index #{idxPartyNew}")
      end

      ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "=" * 70)
      return idxPartyNew

    elsif owner_sid == my_sid
      # CASE 2: My Pokemon switching (I control this NPCTrainer)
      # Get my choice and broadcast it
      ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "📤 MY Pokemon switching, choosing and broadcasting")

      idxPartyNew = coop_original_pbSwitchInBetween(idxBattler, canCancel, canChooseCurrent)

      if idxPartyNew >= 0
        ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "  My choice: party index #{idxPartyNew}")
        CoopSwitchSync.send_switch_choice(idxBattler, idxPartyNew)
      else
        ##MultiplayerDebug.warn("COOP-SWITCH-PHASE", "  No valid switch available (party index: #{idxPartyNew})")
      end

      ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "=" * 70)
      return idxPartyNew

    else
      # CASE 3: Player-owned Pokemon - in coop battles, we need to broadcast this choice!
      # On the owner's client, the owner is Player (not NPCTrainer)
      # But other clients see it as NPCTrainer and are waiting for our choice
      ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "📤 Player-owned Pokemon (LOCAL player), choosing and broadcasting")

      idxPartyNew = coop_original_pbSwitchInBetween(idxBattler, canCancel, canChooseCurrent)

      # Broadcast the choice to allies (they're waiting for it!)
      if idxPartyNew >= 0
        ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "  My choice: party index #{idxPartyNew}")
        CoopSwitchSync.send_switch_choice(idxBattler, idxPartyNew)
      else
        ##MultiplayerDebug.warn("COOP-SWITCH-PHASE", "  No valid switch available (party index: #{idxPartyNew})")
      end

      # Checkpoint after switch choice made
      CoopRNGDebug.checkpoint("after_switch_choice_#{idxBattler}") if defined?(CoopRNGDebug)

      ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "=" * 70)
      return idxPartyNew
    end
  end

  # Hook into pbReplace to track when Pokemon actually switches in
  alias coop_original_pbReplace pbReplace if method_defined?(:pbReplace)

  def pbReplace(idxBattler, idxParty, batonPass = false)
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      # Mark the switch-in phase
      if defined?(CoopRNGDebug)
        CoopRNGDebug.set_phase("SWITCH_IN_#{idxBattler}")
        CoopRNGDebug.checkpoint("before_replace_#{idxBattler}_with_#{idxParty}")
      end

      ##MultiplayerDebug.info("COOP-SWITCH-PHASE", ">>> REPLACING battler #{idxBattler} with party #{idxParty}")
    end

    # Call original
    result = coop_original_pbReplace(idxBattler, idxParty, batonPass)

    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      # Checkpoint after replacement (before switch-in effects)
      CoopRNGDebug.checkpoint("after_replace_#{idxBattler}") if defined?(CoopRNGDebug)
    end

    result
  end

  # Hook into pbOnActiveOne to track switch-in effects
  alias coop_original_pbOnActiveOne pbOnActiveOne if method_defined?(:pbOnActiveOne)

  def pbOnActiveOne(battler)
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      if defined?(CoopRNGDebug)
        CoopRNGDebug.set_phase("SWITCH_IN_EFFECTS_#{battler.index}")
        CoopRNGDebug.checkpoint("before_switch_in_effects_#{battler.index}")
      end

      ##MultiplayerDebug.info("COOP-SWITCH-PHASE", ">>> SWITCH-IN EFFECTS for battler #{battler.index} (#{battler.pokemon.name})")

      # CRITICAL FIX: Resync RNG seed RIGHT BEFORE switch-in effects!
      # This is where abilities, entry hazards, and items trigger - all RNG-dependent
      # EXCEPT at Turn 0: Skip resync to preserve Turn 0 seed for pbCalculatePriority
      if defined?(CoopRNGSync) && @turnCount > 0
        ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "🔄 RESYNCING RNG before switch-in effects...")

        # Use a special turn identifier for switch-in resyncs
        # Format: NEGATIVE to avoid collision with actual turn numbers (which are positive)
        # This ensures unique sync point per switch without interfering with turn counting
        sync_id = -((turnCount * 100) + battler.index + 1)

        if CoopBattleState.am_i_initiator?
          # Initiator generates and broadcasts seed (reset_counter = false for mid-turn sync)
          CoopRNGSync.sync_seed_as_initiator(self, sync_id, false)
        else
          # Non-initiator waits for seed (reset_counter = false for mid-turn sync)
          success = CoopRNGSync.sync_seed_as_receiver(self, sync_id, 3, false)
          unless success
            ##MultiplayerDebug.error("COOP-SWITCH-PHASE", "⚠️ RNG resync failed before switch-in!")
          end
        end

        ##MultiplayerDebug.info("COOP-SWITCH-PHASE", "✓ RNG resynced before switch-in effects (sync_id=#{sync_id})")
      end
    end

    # Call original (this triggers entry hazards, abilities, etc.)
    result = coop_original_pbOnActiveOne(battler)

    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      # CRITICAL CHECKPOINT: After all switch-in effects
      CoopRNGDebug.checkpoint("after_switch_in_effects_#{battler.index}") if defined?(CoopRNGDebug)
    end

    result
  end
end

##MultiplayerDebug.info("MODULE-14", "Battle switch phase alias loaded - switch choices synchronized + RNG checkpoints added")
