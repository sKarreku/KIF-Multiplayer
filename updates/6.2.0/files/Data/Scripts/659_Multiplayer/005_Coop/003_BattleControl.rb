# ===========================================
# File: 018_Coop_BattleControl.rb
# Purpose: Override battle control logic for co-op battles
# Notes : Makes NPCTrainers AI-controlled instead of player-controlled
#         so each player only controls their own Pokémon ($Trainer)
# ===========================================

##MultiplayerDebug.info("COOP-CTRL", "Loading co-op battle control hooks...")

class PokeBattle_Battle
  # Override pbOwnedByPlayer? to check trainer type
  unless defined?(pbOwnedByPlayer_vanilla_for_coop)
    alias pbOwnedByPlayer_vanilla_for_coop pbOwnedByPlayer?
  end

  def pbOwnedByPlayer?(idxBattler)
    # First check vanilla conditions (opposing side, autobattler, etc.)
    is_opposing = opposes?(idxBattler)
    ##MultiplayerDebug.info("COOP-CTRL", "🎮🔍 BATTLER #{idxBattler} CHECK → opposes=#{is_opposing}")
    return false if is_opposing
    return false if $PokemonSystem.autobattler != nil && $PokemonSystem.autobattler == 1

    # Get the trainer who owns this battler
    begin
      trainer = pbGetOwnerFromBattlerIndex(idxBattler)
      ##MultiplayerDebug.info("COOP-CTRL", "👤 BATTLER #{idxBattler} OWNER → #{trainer.class} '#{trainer.name rescue 'unknown'}'")

      # Only $Trainer (the real player) should be player-controlled
      # NPCTrainers (representing remote allies) should be AI-controlled
      if trainer.is_a?(NPCTrainer)
        ##MultiplayerDebug.info("COOP-CTRL", "🤖 BATTLER #{idxBattler} → NPCTrainer '#{trainer.name}' = AI CONTROL")
        return false
      end

      # $Trainer is player-controlled
      if defined?($Trainer) && trainer == $Trainer
        ##MultiplayerDebug.info("COOP-CTRL", "✅ BATTLER #{idxBattler} → $Trainer = PLAYER CONTROL")
        return true
      end

      # Fallback to vanilla logic
      result = pbGetOwnerIndexFromBattlerIndex(idxBattler)==0
      ##MultiplayerDebug.info("COOP-CTRL", "⚠️ BATTLER #{idxBattler} FALLBACK → #{result}")
      return result
    rescue => e
      ##MultiplayerDebug.error("COOP-CTRL", "❌ ERROR in pbOwnedByPlayer?: #{e.class}: #{e.message}")
      # Fallback to vanilla
      return pbOwnedByPlayer_vanilla_for_coop(idxBattler)
    end
  end
end

##MultiplayerDebug.info("COOP-CTRL", "Co-op battle control hooks loaded successfully.")
