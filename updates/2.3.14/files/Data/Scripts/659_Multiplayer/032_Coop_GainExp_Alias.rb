#===============================================================================
# MODULE 15: Gain Exp Alias - Award Exp to All Trainers in Coop
#===============================================================================
# Wraps pbGainExp to ensure ALL trainers on side 0 get exp, not just trainer 0
# In coop battles, there are multiple trainers (initiator + allies), and the
# original code only awards exp to trainer 0's Pokemon.
#
# Solution: Iterate through all trainers on side 0 using eachInTeam(0, i)
#===============================================================================

class PokeBattle_Battle
  # Save original method
  alias coop_original_pbGainExp pbGainExp

  def pbGainExp
    # If not in coop battle, use original behavior
    unless defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      return coop_original_pbGainExp
    end

    # In coop battles, we need to award exp to ALL trainers, not just trainer 0
    # Check if any Pokémon need to be given Exp, and award those Pokémon Exp/EVs
    # IMPORTANT: Force expAll = false in coop to prevent desync between players with different difficulty settings
    expAll = false  # Disabled in coop - only participants get exp
    p1 = pbParty(0)

    ##MultiplayerDebug.info("XP-TRACE-1", "=" * 70)
    ##MultiplayerDebug.info("XP-TRACE-1", "pbGainExp CALLED")
    ##MultiplayerDebug.info("XP-TRACE-2", "party1starts=#{@party1starts.inspect}")
    ##MultiplayerDebug.info("XP-TRACE-3", "Total party size: #{p1.length}")
    ##MultiplayerDebug.info("XP-TRACE-4", "Party contents:")
    p1.each_with_index do |pkmn, i|
      if pkmn
        ##MultiplayerDebug.info("XP-TRACE-4", "  [#{i}] #{pkmn.name} HP=#{pkmn.hp}/#{pkmn.totalhp} Able=#{pkmn.able?}")
      else
        ##MultiplayerDebug.info("XP-TRACE-4", "  [#{i}] nil")
      end
    end
    ##MultiplayerDebug.info("XP-TRACE-5", "Battlers (fainted foes):")
    @battlers.each do |b|
      next unless b && b.opposes?
      if b.fainted? || b.captured
        ##MultiplayerDebug.info("XP-TRACE-5", "  Battler##{b.index} #{b.pokemon.name}: participants=#{b.participants.inspect}, fainted?=#{b.fainted?}, captured?=#{b.captured}")
      end
    end
    ##MultiplayerDebug.info("XP-TRACE-1", "=" * 70)

    @battlers.each do |b|
      next unless b && b.opposes? # Can only gain Exp from fainted foes
      next if b.participants.length == 0
      next unless b.fainted? || b.captured

      ##MultiplayerDebug.info("COOP-EXP", "Defeated: #{b.pokemon.name}, Participants: #{b.participants.inspect}")
      ##MultiplayerDebug.info("COOP-EXP", "  party1starts: #{@party1starts.inspect}, party size: #{p1.length}")

      # Iterate through EACH trainer on side 0
      @party1starts.length.times do |idxTrainer|
        ##MultiplayerDebug.info("COOP-EXP", "Processing trainer #{idxTrainer} on side 0...")

        # Debug: Show party range for this trainer
        partyStart = @party1starts[idxTrainer]
        partyEnd = (idxTrainer < @party1starts.length - 1) ? @party1starts[idxTrainer + 1] : p1.length
        ##MultiplayerDebug.info("COOP-EXP", "  Trainer #{idxTrainer} owns party indices [#{partyStart}..#{partyEnd-1}]")

        # Count the number of participants for THIS trainer
        numPartic = 0
        b.participants.each do |partic|
          ##MultiplayerDebug.info("COOP-EXP", "    Checking participant #{partic}: exists?=#{!p1[partic].nil?}, able?=#{p1[partic] ? p1[partic].able? : 'N/A'}")
          next unless p1[partic] && p1[partic].able?
          # Check if this participant belongs to this trainer
          partyStart = @party1starts[idxTrainer]
          partyEnd = (idxTrainer < @party1starts.length - 1) ? @party1starts[idxTrainer + 1] : p1.length
          ##MultiplayerDebug.info("COOP-EXP", "    Participant #{partic} in range check: [#{partyStart}..#{partyEnd-1}]")
          if partic >= partyStart && partic < partyEnd
            ##MultiplayerDebug.info("COOP-EXP", "    ✓ Participant #{partic} belongs to trainer #{idxTrainer}")
            numPartic += 1
          else
            ##MultiplayerDebug.info("COOP-EXP", "    ✗ Participant #{partic} does NOT belong to trainer #{idxTrainer}")
          end
        end

        ##MultiplayerDebug.info("COOP-EXP", "  Trainer #{idxTrainer} participants: #{numPartic}")

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
          ##MultiplayerDebug.info("COOP-EXP", "  Condition met: numPartic=#{numPartic}, expShare=#{expShare.length}, expAll=#{expAll}")

          # Gain EVs and Exp for participants
          eachInTeam(0, idxTrainer) do |pkmn, i|
            ##MultiplayerDebug.info("COOP-EXP", "    Checking #{pkmn.name} (party #{i}): able?=#{pkmn.able?}, participant?=#{b.participants.include?(i)}, expShare?=#{expShare.include?(i)}")
            next if !pkmn.able?
            next unless b.participants.include?(i) || expShare.include?(i)
            ##MultiplayerDebug.info("COOP-EXP", "  Awarding exp to #{pkmn.name} (party #{i})")
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
              ##MultiplayerDebug.info("COOP-EXP", "  Awarding exp (Exp All) to #{pkmn.name} (party #{i})")
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

    ##MultiplayerDebug.info("COOP-EXP", "=" * 70)
  end
end

##MultiplayerDebug.info("MODULE-15", "Gain exp alias loaded - all trainers get exp in coop")
