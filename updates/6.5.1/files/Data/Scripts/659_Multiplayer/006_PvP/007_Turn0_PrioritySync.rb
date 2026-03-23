#===============================================================================
# PvP Turn 0 Priority Calculation RNG Sync
#===============================================================================
# Syncs RNG RIGHT BEFORE pbCalculatePriority(true) at battle start
# ONLY syncs ONCE per battle (first call in pbOnActiveAll)
#
# This prevents desync when:
# - Both Pokemon have equal speed (random tie-breaker differs per client)
# - Two-turn moves execute in different order on each screen
#===============================================================================

class PokeBattle_Battle
  alias pvp_turn0_original_pbCalculatePriority pbCalculatePriority if method_defined?(:pbCalculatePriority)

  def pbCalculatePriority(fullCalc=false, indexArray=nil)
    # Only sync on Turn 0 when doing full calculation, and ONLY ONCE
    # Use instance variable to track if we've already synced Turn 0
    if fullCalc && @turnCount == 0 && defined?(PvPBattleState) && defined?(PvPRNGSync)
      # Check if we're in a PvP battle
      if PvPBattleState.in_pvp_battle?
        # Initialize flag if not set
        @pvp_turn0_rng_synced ||= false

        unless @pvp_turn0_rng_synced
          begin
            battle_id = PvPBattleState.battle_id
            if battle_id && !battle_id.empty?
              if defined?(MultiplayerDebug)
                MultiplayerDebug.info("PVP-TURN0", "Syncing RNG for Turn 0 priority calculation")
              end

              # Use turn 0 for the sync
              if PvPBattleState.is_initiator?
                PvPRNGSync.sync_seed_as_initiator(self, 0)
              else
                unless PvPRNGSync.sync_seed_as_receiver(self, 0, 10)
                  if defined?(MultiplayerDebug)
                    MultiplayerDebug.error("PVP-TURN0", "RNG sync failed at Turn 0 priority calculation!")
                  end
                  # Don't return early - continue with potentially desynced state
                  # The battle will likely desync but at least won't crash
                end
              end

              # Mark that we've synced Turn 0
              @pvp_turn0_rng_synced = true

              if defined?(MultiplayerDebug)
                MultiplayerDebug.info("PVP-TURN0", "Turn 0 RNG synced successfully (first pbCalculatePriority call)")
              end
            end
          rescue => e
            if defined?(MultiplayerDebug)
              MultiplayerDebug.error("PVP-TURN0", "Exception in Turn 0 sync: #{e.class}: #{e.message}")
              MultiplayerDebug.error("PVP-TURN0", "  Backtrace: #{e.backtrace.first(3).join(' | ')}")
            end
          end
        end
      end
    end

    # Call original
    pvp_turn0_original_pbCalculatePriority(fullCalc, indexArray)
  end
end

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("PVP-TURN0", "PvP Turn 0 priority calculation RNG sync loaded")
end
