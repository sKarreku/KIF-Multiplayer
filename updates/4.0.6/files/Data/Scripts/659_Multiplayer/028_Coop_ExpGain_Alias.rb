#===============================================================================
# MODULE 12: Exp Gain Alias - Prevent Outsider Exp Boost in Coop Battles
#===============================================================================
# Wraps pbGainExpOne to skip the "isOutsider" exp boost calculation entirely
# during coop battles. This prevents remote player's Pokemon from getting
# 1.5x exp which causes level-up desync between clients.
#
# Solution: In coop battles, just skip lines 180-186 (the isOutsider exp boost)
#===============================================================================

class PokeBattle_Battle
  # Save original method
  alias coop_original_pbGainExpOne pbGainExpOne

  def pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages = true)
    # If not in coop battle, use original behavior
    unless defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      return coop_original_pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages)
    end

    # In coop battles, we reimplement the method WITHOUT the isOutsider boost
    pkmn = pbParty(0)[idxParty]
    ##MultiplayerDebug.info("COOP-EXP", "pbGainExpOne called: idxParty=#{idxParty}, pkmn=#{pkmn ? pkmn.name : 'nil'}, numPartic=#{numPartic}")
    ##MultiplayerDebug.info("COOP-EXP", "  Party size: #{pbParty(0).length}, Participants: #{defeatedBattler.participants.inspect}")
    ##MultiplayerDebug.info("🔔🔔🔔 SHOW-MSG", "►►► showMessages=#{showMessages} for #{pkmn ? pkmn.name : 'nil'} at idxParty=#{idxParty} ◄◄◄")
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
    ##MultiplayerDebug.info("🔔🔔🔔 EXP-CHECK", "►►► After calc: exp=#{exp} for #{pkmn.name} ◄◄◄")
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
    # Lines 177-186 from original are completely omitted
    ##MultiplayerDebug.info("COOP-EXP", "Skipping isOutsider check for #{pkmn.name} (coop battle)")

    # Modify Exp gain based on held item
    i = BattleHandlers.triggerExpGainModifierItem(pkmn.item, pkmn, exp)
    if i < 0
      i = BattleHandlers.triggerExpGainModifierItem(@initialItems[0][idxParty], pkmn, exp)
    end
    exp = i if i >= 0

    # Make sure Exp doesn't exceed the maximum
    expFinal = growth_rate.add_exp(pkmn.exp, exp)
    expGained = expFinal - pkmn.exp
    ##MultiplayerDebug.info("🔔🔔🔔 EXP-FINAL", "►►► expGained=#{expGained} for #{pkmn.name} (current exp: #{pkmn.exp}) ◄◄◄")
    return if expGained <= 0

    # "Exp gained" message (NO "boosted" message in coop)
    if showMessages
      pbDisplayPaused(_INTL("{1} got {2} Exp. Points!", pkmn.name, expGained))
    end
    ##MultiplayerDebug.info("🔔🔔🔔 AFTER-MSG", "►►► After exp message for #{pkmn.name} ◄◄◄")

    curLevel = pkmn.level
    newLevel = growth_rate.level_from_exp(expFinal)
    ##MultiplayerDebug.info("🔔🔔🔔 LEVEL-CHECK", "►►► curLevel=#{curLevel}, newLevel=#{newLevel} for #{pkmn.name} ◄◄◄")

    # Give Exp
    ##MultiplayerDebug.info("🔔🔔🔔 SHADOW-CHECK", "►►► shadowPokemon?=#{pkmn.shadowPokemon?} for #{pkmn.name} ◄◄◄")
    if pkmn.shadowPokemon?
      pkmn.exp += expGained
      return
    end

    tempExp1 = pkmn.exp
    battler = pbFindBattler(idxParty)
    ##MultiplayerDebug.info("🔔🔔🔔 BATTLER-CHECK", "►►► pbFindBattler(#{idxParty}) returned: #{battler ? "Battler##{battler.index}" : 'nil'} for #{pkmn.name} ◄◄◄")
    ##MultiplayerDebug.info("🔔🔔🔔 LOOP-START", "►►► Starting exp loop for #{pkmn.name}, tempExp1=#{tempExp1}, expFinal=#{expFinal} ◄◄◄")
    loop do
      ##MultiplayerDebug.info("🔔🔔🔔 LOOP-ITER", "►►► Loop iteration: curLevel=#{curLevel} for #{pkmn.name} ◄◄◄")
      levelMinExp = growth_rate.minimum_exp_for_level(curLevel)
      levelMaxExp = growth_rate.minimum_exp_for_level(curLevel + 1)
      tempExp2 = (levelMaxExp < expFinal) ? levelMaxExp : expFinal
      ##MultiplayerDebug.info("🔔🔔🔔 EXP-SET", "►►► Setting exp: #{pkmn.exp} → #{tempExp2} for #{pkmn.name} ◄◄◄")
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
          ##MultiplayerDebug.info("🔔🔔🔔 LEVEL-CAP", "►►► Level cap HIT for #{pkmn.name}: cap=#{getkuraylevelcap()}, exp=#{pkmn.exp} (own Pokemon) ◄◄◄")
          if showMessages && tempExp1 < levelMaxExp &&
             $PokemonSystem.respond_to?(:levelcapbehavior) &&
             $PokemonSystem.levelcapbehavior != 2
            pbDisplayPaused(_INTL("{1} can't gain any more Exp. Points until the next level cap.", pkmn.name))
          end
          pkmn.exp = growth_rate.minimum_exp_for_level(getkuraylevelcap())
          break
        else
          ##MultiplayerDebug.info("🔔🔔🔔 LEVEL-CAP", "►►► Level cap SKIPPED for #{pkmn.name}: ally's Pokemon, using their cap ◄◄◄")
        end
      end

      # Handle exp bar animation and level-up
      ##MultiplayerDebug.info("🔔🔔🔔 EXP-BAR", "►►► Before pbEXPBar: battler=#{battler ? battler.index : 'nil'} for #{pkmn.name} ◄◄◄")
      if battler
        begin
          @scene.pbEXPBar(battler, levelMinExp, levelMaxExp, tempExp1, tempExp2)
          ##MultiplayerDebug.info("🔔🔔🔔 EXP-BAR", "►►► pbEXPBar completed for #{pkmn.name} ◄◄◄")
        rescue => e
          ##MultiplayerDebug.info("🔔🔔🔔 EXP-BAR", "►►► pbEXPBar FAILED for #{pkmn.name}: #{e.class} - #{e.message} ◄◄◄")
        end
      end
      tempExp1 = tempExp2
      curLevel += 1
      ##MultiplayerDebug.info("🔔🔔🔔 LEVEL-INC", "►►► curLevel incremented to #{curLevel}, newLevel=#{newLevel} for #{pkmn.name} ◄◄◄")
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
                ##MultiplayerDebug.info("COOP-MOVE-LEARN", "Sent move sync: #{pkmn.name} learned #{GameData::Move.get(i[1]).name} in slot #{learned_slot}")
              end
            end
          end
        end
      end
    end
  end
end

#MultiplayerDebug.info("MODULE-12", "Exp gain alias loaded - outsider boost disabled in coop battles")
