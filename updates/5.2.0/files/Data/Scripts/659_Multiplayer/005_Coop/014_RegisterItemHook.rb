#===============================================================================
# Co-op RegisterItem Hook - Track Local Pokeball Registrations
#===============================================================================
# Sets @@local_throw_battler_idx when THIS client registers a Pokeball
# This happens BEFORE action sync, so only the local player sets it
#===============================================================================

class PokeBattle_Battle
  alias coop_original_pbRegisterItem pbRegisterItem

  def pbRegisterItem(idxBattler, item, idxTarget=nil, idxMove=nil)
    # Mark THIS client as the thrower when registering a Pokeball (BEFORE sync)
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      if GameData::Item.get(item).is_poke_ball?
        @@local_throw_battler_idx = idxBattler
        ##MultiplayerDebug.info("🎯 REGISTER-BALL", "Battler #{idxBattler} registered Pokeball #{item} - marked as local thrower")
      end
    end

    # Call original
    return coop_original_pbRegisterItem(idxBattler, item, idxTarget, idxMove)
  end
end

##MultiplayerDebug.info("MODULE-REGISTER", "Co-op register item hook loaded")
