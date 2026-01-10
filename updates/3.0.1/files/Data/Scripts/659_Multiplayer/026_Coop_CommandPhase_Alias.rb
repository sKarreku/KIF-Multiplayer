#===============================================================================
# MODULE 10: Command Phase Alias - Action Sync + RNG Sync
#===============================================================================
# Wraps pbCommandPhase to inject:
# 1. Action synchronization - wait for all allies after player phase
# 2. RNG synchronization - sync seed BEFORE AI phase (ensures enemy AI is deterministic)
# 3. Monkey-patching - replace ally AI decisions with real player choices
#===============================================================================

class PokeBattle_Battle
  # Save original methods
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
              ##MultiplayerDebug.info("COOP-AI", "🎯 NPCTrainer battler #{idxBattler} is ENEMY - running AI")
            else
              # Ally NPCTrainer (remote player) - skip AI, actions come from network
              ##MultiplayerDebug.info("COOP-AI", "🤝 NPCTrainer battler #{idxBattler} is ALLY - skipping AI (remote player)")
              next
            end
          end
        rescue => e
          ##MultiplayerDebug.error("COOP-AI", "❌ Error checking trainer for battler #{idxBattler}: #{e.message}")
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
    # MODULE 21: Skip action selection if player is in spectator mode (all Pokemon fainted)
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      # Check if LOCAL player (battler 0's owner) has any able Pokemon
      local_battler_idx = 0  # The player-controlled battler
      local_owner_idx = pbGetOwnerIndexFromBattlerIndex(local_battler_idx)

      # Get the local player's trainer
      local_trainer = pbGetOwnerFromBattlerIndex(local_battler_idx)
      local_is_player = local_trainer && local_trainer.is_a?(Player)

      if local_is_player && pbTrainerAllFainted?(local_battler_idx)
        ##MultiplayerDebug.info("COOP-SPECTATOR", "Local player in spectator mode - skipping action selection")
        ##MultiplayerDebug.info("COOP-SPECTATOR", "Player is now spectating the battle")
        # Don't choose any actions - all the player's Pokemon are fainted
        # The player will just watch the battle continue
        # No need to call pbAutoChooseMove - fainted Pokemon don't need actions
      else
        pbCommandPhaseLoop(true)    # Player chooses their actions
      end
    else
      pbCommandPhaseLoop(true)    # Player chooses their actions
    end

    # Check if battle ended during command selection (e.g., forfeit)
    if @decision != 0
      ##MultiplayerDebug.info("COOP-COMMAND", "Battle ended during command phase (decision=#{@decision}), aborting")
      return
    end

    # MODULE 5: Synchronize player actions in coop battles
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      # Check if ANY player still has able Pokemon
      # If all allies have fainted, we might still continue (spectator mode)
      has_able_allies = false
      ally_sids = CoopBattleState.get_ally_sids rescue []

      ##MultiplayerDebug.info("COOP-SPECTATOR", "Checking ally status before action sync...")
      ##MultiplayerDebug.info("COOP-SPECTATOR", "  Allies: #{ally_sids.inspect}")

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
        ##MultiplayerDebug.info("COOP-RUN", "Battle ended during action sync (decision=#{@decision})")
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
      ##MultiplayerDebug.info("COOP-RUN-RNG", "=== RUN ATTEMPT CHECK ===")
      ##MultiplayerDebug.info("COOP-RUN-RNG", "Run was attempted this turn: #{run_was_attempted}")

      # CRITICAL: If run was attempted, force RNG re-sync to fix any desync
      # This REPLACES the normal RNG sync (we don't do both)
      if run_was_attempted
        ##MultiplayerDebug.info("COOP-RUN-RNG", "Run was attempted - RNG re-sync will replace normal sync")
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
          ##MultiplayerDebug.info("COOP-RUN-RNG", "✓ RNG re-synced successfully after run attempt")
        end
      else
        # MODULE 6: Synchronize RNG seed BEFORE AI runs (only if no run attempt)
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

      # MODULE 7: Apply remote player actions (monkey-patch AI)
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
end

##MultiplayerDebug.info("MODULE-10", "Command phase alias loaded - action sync enabled")
