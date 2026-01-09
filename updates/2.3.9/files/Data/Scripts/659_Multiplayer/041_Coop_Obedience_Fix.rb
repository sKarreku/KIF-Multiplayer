#===============================================================================
# Co-op Obedience Fix
#===============================================================================
# In co-op battles, obedience checks should use the Pokemon owner's badge count,
# not the initiator's badge count. Otherwise ally Pokemon will disobey based on
# wrong trainer's badges.
#===============================================================================

class PokeBattle_Battler
  alias coop_obedience_original_pbObedienceCheck? pbObedienceCheck?

  def pbObedienceCheck?(choice)
    return true if usingMultiTurnAttack?
    return true if choice[0] != :UseMove
    return true if !@battle.internalBattle
    return true if !@battle.pbOwnedByPlayer?(@index)

    disobedient = false

    # COOP FIX: In coop battles, use max badges (8) to prevent disobedience
    if defined?(CoopBattleState) && CoopBattleState.active?
      badge_count = 8  # Max badges - no disobedience in coop
    else
      # Vanilla battle, use player's actual badge count
      badge_count = @battle.pbPlayer.badge_count
    end

    badgeLevel = 10 * (badge_count + 1)
    badgeLevel = GameData::GrowthRate.max_level if badge_count >= 8

    if (@pokemon.foreign?(@battle.pbPlayer) && @level > badgeLevel) || @pokemon.force_disobey
      a = ((@level + badgeLevel) * @battle.pbRandom(256) / 256).floor
      disobedient |= (a >= badgeLevel)
    end
    disobedient |= !pbHyperModeObedience(choice[2])
    return true if !disobedient

    # Pokémon is disobedient; make it do something else
    return pbDisobey(choice, badgeLevel)
  end
end

##MultiplayerDebug.info("MODULE-OBEDIENCE", "Co-op obedience fix loaded - uses owner badges")
