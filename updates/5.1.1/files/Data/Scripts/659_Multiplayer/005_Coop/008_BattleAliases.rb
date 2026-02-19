# =============================================================================
# Co-op Battle Aliases
# =============================================================================
# All PokeBattle_Battle monkey-patches for co-op battles.
# Organized by battle flow: Command → Attack → Switch → Run → Exp → End
#
# Source files merged:
#   026_Coop_CommandPhase_Alias.rb  → COMMAND PHASE section
#   024_Coop_AttackPhase_Alias.rb   → ATTACK PHASE section
#   031_Coop_SwitchPhase_Alias.rb   → SWITCH PHASE section
#   040_Coop_RunAway_Alias.rb       → RUN AWAY section
#   032_Coop_GainExp_Alias.rb       → EXP GAIN section
#   028_Coop_ExpGain_Alias.rb       → EXP GAIN section
#   025_Coop_EndOfBattle_Alias.rb   → END OF BATTLE section
# =============================================================================

class PokeBattle_Battle

  # ---------------------------------------------------------------------------
  # COMMAND PHASE
  # ---------------------------------------------------------------------------
  # From: 026_Coop_CommandPhase_Alias.rb
  # Patches: pbCommandPhase, pbCommandPhaseLoop
  # Purpose: Sync action choices + RNG between coop players
  # ---------------------------------------------------------------------------
  alias coop_original_pbCommandPhase pbCommandPhase
  alias coop_original_pbCommandPhaseLoop pbCommandPhaseLoop

  # Override pbCommandPhaseLoop to skip NPCTrainers when isPlayer=false (AI phase)
  # NPCTrainers represent remote players - their actions come from network, not AI
  def pbCommandPhaseLoop(isPlayer)
    # If this is AI phase (isPlayer=false) and we're in coop battle
    if !isPlayer && defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      # Run AI only for enemy Pokemon, skip NPCTrainers (they're already monkey-patched)
      actioned = []
      idxBattler = -1
      loop do
        break if @decision!=0
        idxBattler += 1
        break if idxBattler>=@battlers.length

        # Skip if not a valid battler or not an AI-controlled battler
        next if !@battlers[idxBattler] || pbOwnedByPlayer?(idxBattler)!=isPlayer

        # CRITICAL: Skip ALLY NPCTrainers - their actions are already set by monkey-patch
        # Enemy NPCTrainers (opposing trainers) should still run AI
        # Check if trainer exists first to avoid nil errors
        begin
          trainer = pbGetOwnerFromBattlerIndex(idxBattler)
          if trainer && trainer.is_a?(NPCTrainer)
            # Check if this NPCTrainer is an ally or enemy
            is_opposing = opposes?(idxBattler)
            if is_opposing
              # Enemy NPCTrainer - let AI run
            else
              # Ally NPCTrainer (remote player) - skip AI, actions come from network
              next
            end
          end
        rescue => e
        end

        # Skip if action already chosen
        next if @choices[idxBattler][0]!=:None
        next if !pbCanShowCommands?(idxBattler)

        # AI chooses action for enemy Pokemon
        @battleAI.pbDefaultChooseEnemyCommand(idxBattler)
      end
    else
      # Normal flow - call original method
      coop_original_pbCommandPhaseLoop(isPlayer)
    end
  end

  def pbCommandPhase
    @scene.pbBeginCommandPhase

    # Reset run attempt tracking at start of turn
    CoopRunAwaySync.reset_turn if defined?(CoopRunAwaySync) && defined?(CoopBattleState) && CoopBattleState.in_coop_battle?

    # Reset choices if commands can be shown
    @battlers.each_with_index do |b,i|
      next if !b
      pbClearChoice(i) if pbCanShowCommands?(i)
    end

    # Reset choices to perform Mega Evolution if it wasn't done somehow
    for side in 0...2
      @megaEvolution[side].each_with_index do |megaEvo,i|
        @megaEvolution[side][i] = -1 if megaEvo>=0
      end
    end

    # Choose actions for the round (player first, then AI)
    # Skip action selection if player is in spectator mode (all Pokemon fainted)
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      # Check if LOCAL player (battler 0's owner) has any able Pokemon
      local_battler_idx = 0  # The player-controlled battler
      local_owner_idx = pbGetOwnerIndexFromBattlerIndex(local_battler_idx)

      # Get the local player's trainer
      local_trainer = pbGetOwnerFromBattlerIndex(local_battler_idx)
      local_is_player = local_trainer && local_trainer.is_a?(Player)

      if local_is_player && pbTrainerAllFainted?(local_battler_idx)
        # Don't choose any actions - all the player's Pokemon are fainted
        # The player will just watch the battle continue
      else
        pbCommandPhaseLoop(true)    # Player chooses their actions
      end
    else
      pbCommandPhaseLoop(true)    # Player chooses their actions
    end

    # Check if battle ended during command selection (e.g., forfeit)
    if @decision != 0
      return
    end

    # Synchronize player actions in coop battles
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      # Check if ANY player still has able Pokemon
      has_able_allies = false
      ally_sids = CoopBattleState.get_ally_sids rescue []

      PBDebug.log("[COOP-SYNC] Synchronizing turn actions...")

      # Show waiting message with list of allies (non-blocking, stays on screen)
      ally_sids = CoopBattleState.get_ally_sids rescue []
      if ally_sids.length > 0
        # Get ally names if available, otherwise use SIDs
        waiting_list = ally_sids.map do |sid|
          # Try to find trainer name from battlers
          name = nil
          @battlers.each do |b|
            next unless b
            trainer = pbGetOwnerFromBattlerIndex(b.index) rescue nil
            if trainer && trainer.respond_to?(:id) && trainer.id.to_s == sid.to_s
              name = trainer.name rescue nil
              break if name
            end
          end
          name || "Player #{sid}"
        end

        # Show message on battle scene (stays visible during wait, brief=true)
        @scene.pbDisplayMessage(_INTL("Waiting for {1}...", waiting_list.join(", ")), true)
      end

      success = false

      begin
        if defined?(CoopActionSync)
          success = CoopActionSync.wait_for_all_actions(self)
        else
          PBDebug.log("[COOP-SYNC] WARNING: CoopActionSync not defined!")
          success = true  # Continue without sync
        end
      rescue => e
        PBDebug.log("[COOP-SYNC] ERROR during action sync: #{e.class}: #{e.message}")
        success = false
      end

      # CRITICAL: Check if battle ended during sync (e.g., ally ran away successfully)
      if @decision != 0
        return
      end

      unless success
        PBDebug.log("[COOP-SYNC] Action sync failed or timed out. Forfeiting battle.")
        pbDisplay(_INTL("Connection lost. Ending battle..."))
        @decision = 3  # Forfeit
        return
      end

      # Clear waiting message (reset brief message flag)
      @scene.instance_variable_set(:@briefMessage, false) if @scene
      cw = @scene.sprites["messageWindow"] rescue nil
      if cw
        cw.text = ""
        cw.visible = false
      end

      PBDebug.log("[COOP-SYNC] Action sync complete. Proceeding to AI phase.")

      # DEBUG: Check run attempt flag
      run_was_attempted = defined?(CoopRunAwaySync) && CoopRunAwaySync.run_attempted?

      # CRITICAL: If run was attempted, force RNG re-sync to fix any desync
      # This REPLACES the normal RNG sync (we don't do both)
      if run_was_attempted
        rng_sync_turn = @turnCount + 1

        if defined?(CoopRNGSync)
          if CoopBattleState.am_i_initiator?
            unless CoopRNGSync.sync_seed_as_initiator(self, rng_sync_turn)
              PBDebug.log("[COOP-RUN-RNG] ERROR: Failed to re-sync RNG after run")
              pbDisplay(_INTL("RNG sync failed!"))
              @decision = 3  # Forfeit
              return
            end
          else
            unless CoopRNGSync.sync_seed_as_receiver(self, rng_sync_turn)
              PBDebug.log("[COOP-RUN-RNG] ERROR: Failed to receive RNG re-sync after run")
              pbDisplay(_INTL("RNG sync failed!"))
              @decision = 3  # Forfeit
              return
            end
          end
        end
      else
        # Synchronize RNG seed BEFORE AI runs (only if no run attempt)
        # This ensures enemy AI makes identical decisions on all clients
        rng_sync_turn = @turnCount + 1
        PBDebug.log("[COOP-RNG-CMD] Synchronizing RNG seed for turn #{rng_sync_turn} (before AI)...")

        begin
          if defined?(CoopRNGSync)
            if CoopBattleState.am_i_initiator?
              unless CoopRNGSync.sync_seed_as_initiator(self, rng_sync_turn)
                PBDebug.log("[COOP-RNG-CMD] ERROR: Failed to sync seed as initiator")
                pbDisplay(_INTL("RNG sync failed!"))
                @decision = 3  # Forfeit
                return
              end
            else
              unless CoopRNGSync.sync_seed_as_receiver(self, rng_sync_turn)
                PBDebug.log("[COOP-RNG-CMD] ERROR: Failed to receive seed from initiator")
                pbDisplay(_INTL("RNG sync failed!"))
                @decision = 3  # Forfeit
                return
              end
            end
          end
        rescue => e
          PBDebug.log("[COOP-RNG-CMD] EXCEPTION during RNG sync: #{e.class}: #{e.message}")
          pbDisplay(_INTL("RNG sync error!"))
          @decision = 3
          return
        end

        PBDebug.log("[COOP-RNG-CMD] RNG seed synchronized. Proceeding to AI phase.")

        # DEBUG: Log that AI phase is about to start
        if defined?(RNGLog)
          role = CoopBattleState.am_i_initiator? ? "INIT" : "NON"
          RNGLog.write("[AI-PHASE-START][#{role}][T#{rng_sync_turn}]")
        end
      end

      # Apply remote player actions (monkey-patch AI)
      # This replaces AI decisions with real player choices from remote clients
      if defined?(CoopActionSync)
        begin
          PBDebug.log("[COOP-SYNC] Applying remote player actions (monkey-patch)...")
          CoopActionSync.apply_remote_player_actions(self)
          PBDebug.log("[COOP-SYNC] Remote player actions applied successfully.")
        rescue => e
          PBDebug.log("[COOP-SYNC] ERROR applying remote actions: #{e.class}: #{e.message}")
          # Non-critical - continue with AI decisions
        end
      end
    end

    # DEBUG: Log before AI loop
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle? && defined?(RNGLog)
      role = CoopBattleState.am_i_initiator? ? "INIT" : "NON"
      RNGLog.write("[AI-LOOP-START][#{role}][T#{@turnCount}]")
    end

    pbCommandPhaseLoop(false)   # AI chooses their actions (enemy AI now has synced RNG, ally AI gets patched)

    # DEBUG: Log after AI loop
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle? && defined?(RNGLog)
      role = CoopBattleState.am_i_initiator? ? "INIT" : "NON"
      RNGLog.write("[AI-LOOP-END][#{role}][T#{@turnCount}]")
    end
  end

  # ---------------------------------------------------------------------------
  # ATTACK PHASE
  # ---------------------------------------------------------------------------
  # From: 024_Coop_AttackPhase_Alias.rb
  # Patches: pbAttackPhase
  # Purpose: Reset action sync state after attack execution
  # ---------------------------------------------------------------------------
  alias coop_original_pbAttackPhase pbAttackPhase

  def pbAttackPhase
    @scene.pbBeginAttackPhase

    # IMPORTANT: Capture turn number BEFORE incrementing for RNG sync
    # Action sync uses `turnCount + 1` during command phase
    # So we need to match that same turn number here
    rng_sync_turn = @turnCount + 1

    # Reset certain effects
    @battlers.each_with_index do |b,i|
      next if !b
      b.turnCount += 1 if !b.fainted?
      @successStates[i].clear
      if @choices[i][0]!=:UseMove && @choices[i][0]!=:Shift && @choices[i][0]!=:SwitchOut
        b.effects[PBEffects::DestinyBond] = false
        b.effects[PBEffects::Grudge]      = false
      end
      b.effects[PBEffects::Rage] = false if !pbChoseMoveFunctionCode?(i,"093")   # Rage
    end
    PBDebug.log("")

    # NOTE: RNG is now synced in command phase (before AI runs)
    # No need to sync again here in attack phase

    # Calculate move order for this round
    pbCalculatePriority(true)

    # DEBUG: Log priority order after calculation
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle? && defined?(RNGLog)
      role = CoopBattleState.am_i_initiator? ? "INIT" : "NON"
      priority_order = pbPriority.map { |b| "b#{b.index}" }.join(",")
      RNGLog.write("[PRIORITY][#{role}][T#{@turnCount}] order=#{priority_order}")
    end

    # Perform actions
    pbAttackPhasePriorityChangeMessages
    pbAttackPhaseCall
    pbAttackPhaseSwitch
    return if @decision>0
    pbAttackPhaseItems
    return if @decision>0
    pbAttackPhaseMegaEvolution
    pbAttackPhaseMoves

    # Reset sync state at end of attack phase (after all moves executed)
    # This ensures next turn's command phase will wait for fresh actions
    if defined?(CoopActionSync) && defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      # Use current_turn from action sync (which was set during command phase)
      completed_turn = CoopActionSync.current_turn

      # Report RNG call count for this turn
      if defined?(CoopRNGDebug)
        CoopRNGDebug.report
      end

      CoopActionSync.reset_sync_state
    end
  end

  # ---------------------------------------------------------------------------
  # SWITCH PHASE
  # ---------------------------------------------------------------------------
  # From: 031_Coop_SwitchPhase_Alias.rb
  # Patches: pbSwitchInBetween, pbReplace, pbOnActiveOne
  # Purpose: Sync switch decisions + resync RNG after switches
  # ---------------------------------------------------------------------------
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

    battler = @battlers[idxBattler]

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

    if is_enemy
      # CASE 0: Enemy CPU trainer switching - use AI immediately, don't wait for network
      idxPartyNew = coop_original_pbSwitchInBetween(idxBattler, canCancel, canChooseCurrent)
      return idxPartyNew

    elsif is_remote_player
      # CASE 1: Remote player's Pokemon switching on my client
      # Wait for the remote player to choose their switch
      idxPartyNew = CoopSwitchSync.wait_for_switch(owner_sid, 30)

      if idxPartyNew.nil?
        # Timeout - fallback to auto-switch
        idxPartyNew = coop_original_pbSwitchInBetween(idxBattler, canCancel, canChooseCurrent)
      end

      return idxPartyNew

    elsif owner_sid == my_sid
      # CASE 2: My Pokemon switching (I control this NPCTrainer)
      # Get my choice and broadcast it
      idxPartyNew = coop_original_pbSwitchInBetween(idxBattler, canCancel, canChooseCurrent)

      if idxPartyNew >= 0
        CoopSwitchSync.send_switch_choice(idxBattler, idxPartyNew)
      end

      return idxPartyNew

    else
      # CASE 3: Player-owned Pokemon - in coop battles, we need to broadcast this choice!
      # On the owner's client, the owner is Player (not NPCTrainer)
      # But other clients see it as NPCTrainer and are waiting for our choice
      idxPartyNew = coop_original_pbSwitchInBetween(idxBattler, canCancel, canChooseCurrent)

      # Broadcast the choice to allies (they're waiting for it!)
      if idxPartyNew >= 0
        CoopSwitchSync.send_switch_choice(idxBattler, idxPartyNew)
      end

      # Checkpoint after switch choice made
      CoopRNGDebug.checkpoint("after_switch_choice_#{idxBattler}") if defined?(CoopRNGDebug)

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

      # CRITICAL FIX: Resync RNG seed RIGHT BEFORE switch-in effects!
      # This is where abilities, entry hazards, and items trigger - all RNG-dependent
      # EXCEPT at Turn 0: Skip resync to preserve Turn 0 seed for pbCalculatePriority
      if defined?(CoopRNGSync) && @turnCount > 0
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
        end
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

  # ---------------------------------------------------------------------------
  # RUN AWAY
  # ---------------------------------------------------------------------------
  # From: 040_Coop_RunAway_Alias.rb
  # Patches: pbRun
  # Purpose: Sync run away attempts between coop players
  # ---------------------------------------------------------------------------
  alias coop_original_pbRun pbRun

  def pbRun(idxBattler, duringBattle = false)
    # If not in coop battle, use original behavior
    unless defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      return coop_original_pbRun(idxBattler, duringBattle)
    end

    # Check if this is a trainer battle
    if trainerBattle?
      # COOP TRAINER BATTLE: Forfeit causes whiteout for all players
      # Unlike wild battles, trainer battle forfeit is GUARANTEED to succeed
      if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
        battler = @battlers[idxBattler]

        # Only player's battlers can forfeit
        return coop_original_pbRun(idxBattler, duringBattle) if battler.opposes?

        # Broadcast forfeit to all allies
        battle_id = CoopBattleState.battle_id
        turn = turnCount
        message = "COOP_FORFEIT:#{battle_id}|#{turn}"
        MultiplayerClient.send_data(message) if defined?(MultiplayerClient)

        # Small delay to allow message to send
        sleep(0.05)

        # Display forfeit message
        pbDisplay(_INTL("{1} forfeited the battle!", pbPlayer.name))

        # Mark as loss (will trigger whiteout in pbEndOfBattle)
        @decision = 2

        # Mark that we whited out (for coop battle state tracking)
        if defined?(CoopBattleState)
          CoopBattleState.instance_variable_set(:@whiteout, true)
        end

        return 1  # Return success (forfeit always succeeds)
      else
        # Solo trainer battle - can't run
        return coop_original_pbRun(idxBattler, duringBattle)
      end
    end

    battler = @battlers[idxBattler]

    # Only player's battlers can attempt to run
    if battler.opposes?
      return coop_original_pbRun(idxBattler, duringBattle)
    end

    # Mark that a run was attempted (triggers RNG re-sync after action sync)
    if defined?(CoopRunAwaySync)
      CoopRunAwaySync.mark_run_attempted

      # Broadcast to allies that run was attempted (so they also trigger re-sync)
      battle_id = CoopBattleState.battle_id
      turn = turnCount
      message = "COOP_RUN_ATTEMPTED:#{battle_id}|#{turn}"
      MultiplayerClient.send_data(message) if defined?(MultiplayerClient)
    end

    # Use synchronized run command counter instead of @runCommand
    if defined?(CoopRunAwaySync)
      synced_run_command = CoopRunAwaySync.get_run_command

      # Temporarily override @runCommand for this calculation
      old_run_command = @runCommand
      @runCommand = synced_run_command
    end

    # Call original pbRun - with synced RNG and synced @runCommand, result is deterministic
    result = coop_original_pbRun(idxBattler, duringBattle)

    # Restore original @runCommand (we manage it via CoopRunAwaySync)
    if defined?(CoopRunAwaySync)
      @runCommand = old_run_command
    end

    # Handle result
    if result == 1
      # Success - broadcast to all allies BEFORE ending battle
      battle_id = CoopBattleState.battle_id
      turn = turnCount
      message = "COOP_RUN_SUCCESS:#{battle_id}|#{turn}"
      MultiplayerClient.send_data(message) if defined?(MultiplayerClient)

      # Small delay to allow message to send
      sleep(0.05)

      # @decision already set to 3 by original pbRun
      return 1

    elsif result == -1
      # Failure - increment synchronized counter (initiator only)
      if defined?(CoopRunAwaySync) && CoopBattleState.am_i_initiator?
        # Only initiator increments and broadcasts
        battle_id = CoopBattleState.battle_id
        turn = turnCount
        CoopRunAwaySync.increment_run_command(battle_id, turn)
      end

      # CRITICAL: Clear the battler's choice so they waste their turn
      # The vanilla game goes back to command menu, but in coop we can't do that
      # Set choice to :None - NPCTrainers are now skipped in AI phase via pbCommandPhaseLoop override
      @choices[idxBattler][0] = :None
      @choices[idxBattler][1] = 0
      @choices[idxBattler][2] = nil
      @choices[idxBattler][3] = -1

      # Broadcast the cleared choice to allies so they also clear it
      if defined?(CoopActionSync)
        battle_id = CoopBattleState.battle_id
        turn = turnCount
        # Send cleared action (format: battler_idx => [:None, 0, nil, -1])
        cleared_action = { idxBattler => [:None, 0, nil, -1] }
        CoopActionSync.broadcast_failed_run(battle_id, turn, idxBattler)
      end

      return -1

    else
      # Invalid case (couldn't attempt run)
      return 0
    end
  end

  # ---------------------------------------------------------------------------
  # EXP GAIN
  # ---------------------------------------------------------------------------
  # From: 032_Coop_GainExp_Alias.rb + 028_Coop_ExpGain_Alias.rb
  # Patches: pbGainExp, pbGainExpOne
  # Purpose: Award exp to all trainers, skip outsider boost for allies
  # ---------------------------------------------------------------------------
  alias coop_original_pbGainExp pbGainExp

  def pbGainExp
    # If not in coop battle, use original behavior
    unless defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      return coop_original_pbGainExp
    end

    # In coop battles, we need to award exp to ALL trainers, not just trainer 0
    # IMPORTANT: Force expAll = false in coop to prevent desync between players with different difficulty settings
    expAll = false  # Disabled in coop - only participants get exp
    p1 = pbParty(0)

    p1.each_with_index do |pkmn, i|
      if pkmn
      else
      end
    end

    @battlers.each do |b|
      next unless b && b.opposes? # Can only gain Exp from fainted foes
      next if b.participants.length == 0
      next unless b.fainted? || b.captured

      # Iterate through EACH trainer on side 0
      @party1starts.length.times do |idxTrainer|
        # Debug: Show party range for this trainer
        partyStart = @party1starts[idxTrainer]
        partyEnd = (idxTrainer < @party1starts.length - 1) ? @party1starts[idxTrainer + 1] : p1.length

        # Count the number of participants for THIS trainer
        numPartic = 0
        b.participants.each do |partic|
          next unless p1[partic] && p1[partic].able?
          # Check if this participant belongs to this trainer
          partyStart = @party1starts[idxTrainer]
          partyEnd = (idxTrainer < @party1starts.length - 1) ? @party1starts[idxTrainer + 1] : p1.length
          if partic >= partyStart && partic < partyEnd
            numPartic += 1
          end
        end

        # Find which Pokémon have an Exp Share for THIS trainer
        expShare = []
        if !expAll
          eachInTeam(0, idxTrainer) do |pkmn, i|
            next if !pkmn.able?
            next if !pkmn.hasItem?(:EXPSHARE) && GameData::Item.try_get(@initialItems[0][i]) != :EXPSHARE
            expShare.push(i)
          end
        end

        # Calculate EV and Exp gains for the participants of THIS trainer
        if numPartic > 0 || expShare.length > 0 || expAll
          # Gain EVs and Exp for participants
          eachInTeam(0, idxTrainer) do |pkmn, i|
            next if !pkmn.able?
            next unless b.participants.include?(i) || expShare.include?(i)
            pbGainEVsOne(i, b)
            pbGainExpOne(i, b, numPartic, expShare, expAll)
          end

          # Gain EVs and Exp for all other Pokémon because of Exp All
          if expAll
            showMessage = true
            eachInTeam(0, idxTrainer) do |pkmn, i|
              next if !pkmn.able?
              next if b.participants.include?(i) || expShare.include?(i)
              pbDisplayPaused(_INTL("Your party Pokémon in waiting also got Exp. Points!")) if showMessage
              showMessage = false
              pbGainEVsOne(i, b)
              pbGainExpOne(i, b, numPartic, expShare, expAll, false)
            end
          end
        end
      end

      # Clear the participants array for THIS defeated battler
      # This prevents exp from being awarded multiple times for the same battler
      b.participants = []
    end
  end

  # ---------------------------------------------------------------------------
  # From: 028_Coop_ExpGain_Alias.rb
  # Patches: pbGainExpOne
  # Purpose: Skip outsider exp boost in coop to prevent level desync
  # ---------------------------------------------------------------------------
  alias coop_original_pbGainExpOne pbGainExpOne

  def pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages = true)
    # If not in coop battle, use original behavior
    unless defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      return coop_original_pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages)
    end

    # In coop battles, we reimplement the method WITHOUT the isOutsider boost
    pkmn = pbParty(0)[idxParty]
    return if !pkmn || pkmn.egg?

    growth_rate = pkmn.growth_rate
    level = defeatedBattler.level
    baseExp = defeatedBattler.pokemon.base_exp

    # Determine if participated or has Exp Share
    isPartic = defeatedBattler.participants.include?(idxParty)
    hasExpShare = false
    if !isPartic
      if expShare.is_a?(Array)
        hasExpShare = true if expShare.include?(idxParty)
      else
        hasExpShare = true if pbParty(0)[idxParty].hasItem?(:EXPSHARE)
      end
      return if !hasExpShare
    end

    # Calculate base exp
    exp = 0
    a = level * baseExp

    # Handle case where numPartic is 0 (no participants, but Exp Share or Exp All)
    if numPartic == 0
      if expAll
        # Exp All with no participants - award half exp
        exp = a / 2
      elsif hasExpShare
        # Only Exp Share holders, no participants - award full exp to Exp Share
        exp = a
      else
        # No participants and no way to gain exp - return early
        return
      end
    elsif expAll
      if isPartic
        exp = a / (2 * numPartic)
      elsif hasExpShare
        exp = a / (2 * numPartic) / 2
      end
    elsif isPartic
      exp = a / numPartic
    elsif hasExpShare
      exp = a / (2 * numPartic)
    elsif expAll
      total_exp = a / 2
      if $PokemonSystem.expall_redist == nil || $PokemonSystem.expall_redist == 0
        exp = a / 2
      else
        highest_level = $Trainer.party.max_by(&:level).level
        if $Trainer.party.all? { |pokemon| pokemon.level == highest_level }
          exp = a / 2
        else
          differences = $Trainer.party.map do |pokemon|
            diff = highest_level - pokemon.level
            emphasis = 1 + (0.05 + $PokemonSystem.expall_redist ** 1.1 / 1000.0)
            (diff ** emphasis)
          end
          normalized_diffs = differences.map { |diff| diff.to_f / differences.sum }
          exp = (total_exp * normalized_diffs[$Trainer.party.index(pkmn)]).round
        end
      end
    end
    return if exp <= 0

    # Trainer battle exp boost
    if !$PokemonSystem.trainerexpboost
      k_expmult = 1.5
    else
      k_expmult = (100 + $PokemonSystem.trainerexpboost)/100.0
    end
    exp = (exp * k_expmult).floor if trainerBattle?

    # Scale exp based on level
    if Settings::SCALED_EXP_FORMULA
      exp /= 5
      levelAdjust = (2 * level + 10.0) / (pkmn.level + level + 10.0)
      levelAdjust = levelAdjust ** 5
      levelAdjust = Math.sqrt(levelAdjust)
      exp *= levelAdjust
      exp = exp.floor
      exp += 1 if isPartic || hasExpShare
    else
      exp /= 7
    end

    # SKIP THE OUTSIDER BOOST ENTIRELY IN COOP BATTLES

    # Modify Exp gain based on held item
    i = BattleHandlers.triggerExpGainModifierItem(pkmn.item, pkmn, exp)
    if i < 0
      i = BattleHandlers.triggerExpGainModifierItem(@initialItems[0][idxParty], pkmn, exp)
    end
    exp = i if i >= 0

    # Make sure Exp doesn't exceed the maximum
    expFinal = growth_rate.add_exp(pkmn.exp, exp)
    expGained = expFinal - pkmn.exp
    return if expGained <= 0

    # "Exp gained" message (NO "boosted" message in coop)
    if showMessages
      pbDisplayPaused(_INTL("{1} got {2} Exp. Points!", pkmn.name, expGained))
    end

    curLevel = pkmn.level
    newLevel = growth_rate.level_from_exp(expFinal)

    # Give Exp
    if pkmn.shadowPokemon?
      pkmn.exp += expGained
      return
    end

    tempExp1 = pkmn.exp
    battler = pbFindBattler(idxParty)
    loop do
      levelMinExp = growth_rate.minimum_exp_for_level(curLevel)
      levelMaxExp = growth_rate.minimum_exp_for_level(curLevel + 1)
      tempExp2 = (levelMaxExp < expFinal) ? levelMaxExp : expFinal
      pkmn.exp = tempExp2

      # Handle fusion exp tracking
      if pkmn.respond_to?(:isFusion?) && pkmn.isFusion?
        if pkmn.exp_gained_since_fused == nil
          pkmn.exp_gained_since_fused = expGained
        else
          pkmn.exp_gained_since_fused += expGained
        end
      end

      # Level cap check - SKIP IN COOP BATTLES to prevent desync
      # In coop battles, each player may have different level cap settings
      # which would cause Pokemon to level differently on each client
      if defined?($PokemonSystem) && $PokemonSystem.respond_to?(:kuraylevelcap) &&
         $PokemonSystem.kuraylevelcap != 0 &&
         pkmn.exp >= growth_rate.minimum_exp_for_level(getkuraylevelcap())
        # Check if this is our own Pokemon (not an ally's)
        my_party = $Trainer.party
        is_my_pokemon = my_party.include?(pkmn)

        # Only enforce level cap for our own Pokemon
        if is_my_pokemon
          if showMessages && tempExp1 < levelMaxExp &&
             $PokemonSystem.respond_to?(:levelcapbehavior) &&
             $PokemonSystem.levelcapbehavior != 2
            pbDisplayPaused(_INTL("{1} can't gain any more Exp. Points until the next level cap.", pkmn.name))
          end
          pkmn.exp = growth_rate.minimum_exp_for_level(getkuraylevelcap())
          break
        end
      end

      # Handle exp bar animation and level-up
      if battler
        begin
          @scene.pbEXPBar(battler, levelMinExp, levelMaxExp, tempExp1, tempExp2)
        rescue => e
        end
      end
      tempExp1 = tempExp2
      curLevel += 1
      if curLevel > newLevel
        pkmn.calc_stats
        battler.pbUpdate(false) if battler
        break
      end

      # Level up
      pbCommonAnimation("LevelUp", battler) if showMessages && battler
      oldTotalHP = pkmn.totalhp
      oldAttack  = pkmn.attack
      oldDefense = pkmn.defense
      oldSpAtk   = pkmn.spatk
      oldSpDef   = pkmn.spdef
      oldSpeed   = pkmn.speed
      if battler && battler.pokemon && @internalBattle
        battler.pokemon.changeHappiness("levelup")
      end
      pkmn.calc_stats
      battler.pbUpdate(false) if battler
      if showMessages
        pbDisplayPaused(_INTL("{1} grew to Lv. {2}!", pkmn.name, curLevel))
        @scene.pbLevelUp(pkmn, battler, oldTotalHP, oldAttack, oldDefense,
                         oldSpAtk, oldSpDef, oldSpeed)
      end

      # Force refresh the data box to show new level immediately
      if battler
        begin
          @scene.pbRefreshOne(battler.index)
        rescue => e
          # If pbRefreshOne doesn't exist, try pbRefresh
          @scene.pbRefresh rescue nil
        end
      end

      # Learn new moves upon level up
      movelist = pkmn.getMoveList
      for i in movelist
        next if i[0] != curLevel

        # === COOP FIX: Use aliased pbLearnMove (handles ownership detection internally) ===
        pbLearnMove(idxParty, i[1])

        # === COOP FIX: Immediately sync the learned move to allies ===
        # Only send if this is our Pokemon (ownership check)
        if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
          my_party = $Trainer.party
          if my_party.include?(pkmn)
            # Find which slot was changed
            learned_slot = pkmn.moves.index { |m| m && m.id == i[1] }
            if learned_slot
              # Send sync message: which Pokemon, which move, which slot
              if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:send_data)
                battle_id = CoopBattleState.battle_id
                message = "COOP_MOVE_SYNC:#{battle_id}|#{idxParty}|#{i[1]}|#{learned_slot}"
                MultiplayerClient.send_data(message)
              end
            end
          end
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # END OF BATTLE
  # ---------------------------------------------------------------------------
  # From: 025_Coop_EndOfBattle_Alias.rb
  # Patches: pbEndOfBattle
  # Purpose: Cleanup battle state, sync results
  # ---------------------------------------------------------------------------
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
        end
      end
      # Reset accumulator for next battle
      MultiplayerClient.instance_variable_set(:@wild_platinum_accumulated, 0)
    end

    # Show disconnect message if battle was aborted (safe to call here in main thread)
    if abort_reason
      begin
        pbMessage(_INTL("{1}", abort_reason))
      rescue => e
      end
    end

    # Coop Battle State Cleanup + Whiteout Handling
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
      end

      # Push fresh party snapshot after battle ends (levels/HP/EXP updated)
      # This ensures the next battle uses updated party data
      if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:coop_push_party_now!)
        begin
          MultiplayerClient.coop_push_party_now!
        rescue => e
        end
      end

      # Clear stale battle sync flags (joined SIDs) for next battle
      if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:reset_battle_sync)
        begin
          MultiplayerClient.reset_battle_sync
        rescue => e
        end
      end

      # Clear stale RNG seed buffer for next battle
      if defined?(CoopRNGSync) && CoopRNGSync.respond_to?(:reset_sync_state)
        begin
          CoopRNGSync.reset_sync_state
        rescue => e
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
    # 1. Heal all Pokemon (vanilla whiteout behavior)
    $Trainer.party.each { |pkmn| pkmn.heal if pkmn }

    # 2. Lose half money (vanilla whiteout behavior)
    if $Trainer.money > 0
      lost_money = ($Trainer.money / 2).floor
      $Trainer.money -= lost_money
    end

    # 3. Set teleport destination (Pokemon Center or home)
    pbCancelVehicles
    pbRemoveDependencies if defined?(pbRemoveDependencies)
    $game_switches[Settings::STARTING_OVER_SWITCH] = true if defined?(Settings::STARTING_OVER_SWITCH)

    if $PokemonGlobal && $PokemonGlobal.pokecenterMapId && $PokemonGlobal.pokecenterMapId >= 0
      # Teleport to last Pokemon Center
      $game_temp.player_transferring = true
      $game_temp.player_new_map_id = $PokemonGlobal.pokecenterMapId
      $game_temp.player_new_x = $PokemonGlobal.pokecenterX
      $game_temp.player_new_y = $PokemonGlobal.pokecenterY
      $game_temp.player_new_direction = $PokemonGlobal.pokecenterDirection
    else
      # No Pokemon Center visited - fall back to home (vanilla behavior)
      homedata = GameData::Metadata.get.home
      if homedata
        $game_temp.player_transferring = true
        $game_temp.player_new_map_id = homedata[0]
        $game_temp.player_new_x = homedata[1]
        $game_temp.player_new_y = homedata[2]
        $game_temp.player_new_direction = homedata[3]
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
  end

end
