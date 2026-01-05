#===============================================================================
# Turn 0 Priority Calculation RNG Sync
#===============================================================================
# Syncs RNG RIGHT BEFORE pbCalculatePriority(true) at battle start
# ONLY syncs ONCE per battle (first call in pbOnActiveAll)
#===============================================================================

class PokeBattle_Battle
  alias coop_original_pbCalculatePriority pbCalculatePriority if method_defined?(:pbCalculatePriority)

  def pbCalculatePriority(fullCalc=false, indexArray=nil)
    # Only sync on Turn 0 when doing full calculation, and ONLY ONCE
    # Use instance variable to track if we've already synced Turn 0
    if fullCalc && @turnCount == 0 && defined?(CoopBattleState) && defined?(CoopRNGSync)
      # Initialize flag if not set
      @turn0_rng_synced ||= false

      unless @turn0_rng_synced
        begin
          battle_id = CoopBattleState.battle_id
          if battle_id && !battle_id.empty?
            if defined?(CoopRNGDebug)
              CoopRNGDebug.reset_counter(0)
            end

            if CoopBattleState.am_i_initiator?
              CoopRNGSync.sync_seed_as_initiator(self, 0)
            else
              unless CoopRNGSync.sync_seed_as_receiver(self, 0)
                ##MultiplayerDebug.error("COOP-TURN0", "RNG sync failed at Turn 0 priority calculation!")
                return
              end
            end

            # Mark that we've synced Turn 0
            @turn0_rng_synced = true
            ##MultiplayerDebug.info("COOP-TURN0", "Turn 0 RNG synced (first pbCalculatePriority call)")
          end
        rescue => e
          ##MultiplayerDebug.error("COOP-TURN0", "Exception in Turn 0 sync: #{e.class}: #{e.message}")
        end
      end
    end

    # Call original
    coop_original_pbCalculatePriority(fullCalc, indexArray)
  end
end

##MultiplayerDebug.info("MODULE-TURN0", "Turn 0 priority calculation RNG sync loaded")
