# ===========================================
# File: 128_PvP_BattleAliases.rb
# Purpose: PvP Battle Phase Aliases - Inject RNG & Action Sync
# Phase: 5 - Battle Synchronization
# ===========================================
# Hooks into battle phases to inject PvP synchronization (mirrors coop pattern):
# 1. pbCommandPhaseLoop - Skip AI for opponent NPCTrainer (action from network)
# 2. pbCommandPhase - Player action → Action sync → RNG sync → AI phase
# 3. pbAttackPhase - Execute attacks (RNG already synced), reset sync state
#
# CRITICAL: RNG sync happens BEFORE AI phase in command phase, NOT in attack phase!
# This ensures deterministic move selection and damage calculations.
#===============================================================================

class PokeBattle_Battle
  # Save original methods
  unless defined?(pvp_original_pbCommandPhase)
    alias pvp_original_pbCommandPhase pbCommandPhase
  end

  unless defined?(pvp_original_pbCommandPhaseLoop)
    alias pvp_original_pbCommandPhaseLoop pbCommandPhaseLoop
  end

  unless defined?(pvp_original_pbAttackPhase)
    alias pvp_original_pbAttackPhase pbAttackPhase
  end

  #-----------------------------------------------------------------------------
  # Command Phase Loop - Skip AI for opponent NPCTrainer (action from network)
  #-----------------------------------------------------------------------------
  def pbCommandPhaseLoop(isPlayer)
    # Check if PvP battle in AI phase
    in_pvp = defined?(PvPBattleState) && PvPBattleState.in_pvp_battle?

    if !isPlayer && in_pvp
      # AI PHASE IN PVP
      # Opponent NPCTrainer already has action from network (set in wait_for_opponent_action)
      # Just skip them - their @choices[idx] is already set

      idxBattler = -1
      loop do
        break if @decision != 0
        idxBattler += 1
        break if idxBattler >= @battlers.length

        next if !@battlers[idxBattler] || pbOwnedByPlayer?(idxBattler) != isPlayer

        # Check if this is opponent's NPCTrainer
        trainer = pbGetOwnerFromBattlerIndex(idxBattler)
        if trainer && trainer.is_a?(NPCTrainer)
          # Check if this is the opponent (not ally)
          is_opposing = opposes?(idxBattler)
          if is_opposing
            # Opponent NPC - their action already set from network, SKIP AI
            if defined?(MultiplayerDebug)
              MultiplayerDebug.info("PVP-AI", "Skipping AI for opponent battler #{idxBattler} (action from network)")
            end
            next
          end
        end

        # Skip if action already chosen
        next if @choices[idxBattler][0] != :None
        next if !pbCanShowCommands?(idxBattler)

        # Run AI for any other battlers (shouldn't happen in 1v1 PvP)
        @battleAI.pbDefaultChooseEnemyCommand(idxBattler)
      end
    else
      # Not PvP AI phase - call original
      pvp_original_pbCommandPhaseLoop(isPlayer)
    end
  end

  #-----------------------------------------------------------------------------
  # Command Phase - Player selects action + wait for opponent + AI phase
  #-----------------------------------------------------------------------------
  def pbCommandPhase
    # Check if we're in a PvP battle
    in_pvp = defined?(PvPBattleState) && PvPBattleState.in_pvp_battle?

    unless in_pvp
      # Normal battle - call original
      return pvp_original_pbCommandPhase
    end

    # === PVP BATTLE: Extended command phase (mirrors coop pattern) ===
    @scene.pbBeginCommandPhase

    # Reset choices if commands can be shown
    @battlers.each_with_index do |b, i|
      next if !b
      pbClearChoice(i) if pbCanShowCommands?(i)
    end

    # Reset Mega Evolution choices
    for side in 0...2
      @megaEvolution[side].each_with_index do |megaEvo, i|
        @megaEvolution[side][i] = -1 if megaEvo >= 0
      end
    end

    # 1. PLAYER ACTION SELECTION (use vanilla loop)
    pbCommandPhaseLoop(true)

    # Check if battle ended during command selection
    if @decision != 0
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-COMMAND", "Battle ended during command phase (decision=#{@decision})")
      end
      return
    end

    # 2. ACTION SYNCHRONIZATION
    # Wait for opponent's action and apply it
    if defined?(PvPActionSync)
      @scene.pbDisplayMessage(_INTL("Waiting for opponent..."), true)

      success = PvPActionSync.wait_for_opponent_action(self, 120)

      # Clear waiting message
      @scene.instance_variable_set(:@briefMessage, false) if @scene
      cw = @scene.sprites["messageWindow"] rescue nil
      if cw
        cw.text = ""
        cw.visible = false
      end

      # Check if opponent forfeited during action sync
      if defined?(PvPForfeitSync) && PvPForfeitSync.opponent_forfeited?
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-COMMAND", "Opponent forfeited during action sync - we win!")
        end
        pbDisplay(_INTL("Your opponent forfeited!"))
        return  # @decision already set by PvPForfeitSync
      end

      unless success
        if defined?(MultiplayerDebug)
          MultiplayerDebug.error("PVP-COMMAND", "Action sync failed or timed out")
        end
        pbDisplay(_INTL("Connection lost. Ending battle..."))
        @decision = 3  # Forfeit
        return
      end

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-COMMAND", "Action sync complete")
      end
    end

    # Check if battle ended during action sync (includes forfeit)
    if @decision != 0
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-COMMAND", "Battle ended during action sync (decision=#{@decision})")
      end
      return
    end

    # 3. RNG SYNCHRONIZATION (BEFORE AI PHASE!)
    # This ensures deterministic move execution on both clients
    if defined?(PvPRNGSync)
      rng_sync_turn = @turnCount + 1

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-COMMAND", "Syncing RNG seed before AI phase: turn=#{rng_sync_turn}")
      end

      success = false

      if PvPBattleState.is_initiator?
        success = PvPRNGSync.sync_seed_as_initiator(self, rng_sync_turn)
      else
        success = PvPRNGSync.sync_seed_as_receiver(self, rng_sync_turn, 5)
      end

      unless success
        if defined?(MultiplayerDebug)
          MultiplayerDebug.error("PVP-COMMAND", "RNG sync failed")
        end
        pbDisplay(_INTL("RNG sync failed!"))
        @decision = 3  # Forfeit
        return
      end

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-COMMAND", "RNG sync complete")
      end
    end

    # 4. AI ACTION SELECTION
    # Call AI phase (opponent's action already set by wait_for_opponent_action)
    pbCommandPhaseLoop(false)
  end

  #-----------------------------------------------------------------------------
  # Attack Phase - Execute attacks (RNG already synced in command phase)
  #-----------------------------------------------------------------------------
  def pbAttackPhase
    # Check if we're in a PvP battle
    in_pvp = defined?(PvPBattleState) && PvPBattleState.in_pvp_battle?

    unless in_pvp
      # Normal battle - call original
      return pvp_original_pbAttackPhase
    end

    # === PVP BATTLE: Just execute attack phase ===
    # RNG was already synced in command phase, no need to sync again

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-ATTACK", "Executing attack phase (RNG already synced)")
    end

    # Execute attack phase with synchronized RNG
    pvp_original_pbAttackPhase

    # Reset sync state after turn completes
    PvPActionSync.reset_sync_state if defined?(PvPActionSync)
    PvPRNGSync.reset_sync_state if defined?(PvPRNGSync)
    PvPSwitchSync.reset if defined?(PvPSwitchSync)
  end
end

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("PVP-ALIASES", "PvP battle phase aliases loaded")
end
