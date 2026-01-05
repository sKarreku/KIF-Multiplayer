#===============================================================================
# MODULE 13: Store Pokemon Alias - Skip Nickname Prompt for Remote Players
#===============================================================================
# Wraps pbStorePokemon to prevent nickname prompt when storing Pokemon caught
# by remote players in coop battles. Only the player who caught the Pokemon
# should be prompted to nickname it.
#
# Solution: In coop battles, check if the Pokemon's original trainer matches
# the current player. If not, skip the nickname prompt.
#===============================================================================

module PokeBattle_BattleCommon
  # Save original method
  alias coop_original_pbStorePokemon pbStorePokemon

  def pbStorePokemon(pkmn)
    # If not in coop battle, use original behavior
    unless defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      return coop_original_pbStorePokemon(pkmn)
    end

    # In coop battles, only process if this is MY caught Pokemon (SID check)
    begin
      catcher_sid = pkmn.instance_variable_get(:@coop_catcher_sid) rescue nil
      my_sid = (defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:session_id)) ? MultiplayerClient.session_id.to_s : nil

      MultiplayerDebug.info("🔍 STORE-CHECK", "Checking #{pkmn.name}: catcher_sid=#{catcher_sid}, my_sid=#{my_sid}") if defined?(MultiplayerDebug)

      if catcher_sid && my_sid && catcher_sid != my_sid
        ##MultiplayerDebug.info("🚫 STORE-SKIP", "Skipping #{pkmn.name} - caught by remote (SID #{catcher_sid} ≠ #{my_sid})")
        return
      end

      # If no SID is set, something went wrong - skip storage
      if !catcher_sid
        MultiplayerDebug.warn("⚠️ STORE-NOSID", "No @coop_catcher_sid on #{pkmn.name}, skipping storage") if defined?(MultiplayerDebug)
        return
      end

      # Store to $Trainer (the real player), not trainer objects
      MultiplayerDebug.info("💾 STORE-MINE", "Storing #{pkmn.name} to my party ($Trainer)") if defined?(MultiplayerDebug)
      _pbStorePokemonToPlayer(pkmn, $Trainer)
    rescue => e
      ##MultiplayerDebug.error("COOP-STORE-ERROR", "Error storing Pokemon: #{e.message}")
      raise
    end
  end

  # Helper method to store Pokemon to a specific player's party
  def _pbStorePokemonToPlayer(pkmn, player)
    # Nickname the Pokémon (unless it's a Shadow Pokémon)
    if !pkmn.shadowPokemon?
      if $PokemonSystem.skipcaughtnickname != 1
        if pbDisplayConfirm(_INTL("Would you like to give a nickname to {1}?", pkmn.name))
          nickname = @scene.pbNameEntry(_INTL("{1}'s nickname?", pkmn.speciesName), pkmn)
          pkmn.name = nickname
        end
      end
    end
    # Store the Pokémon to the target player's party/PC
    currentBox = @peer.pbCurrentBox
    storedBox  = @peer.pbStorePokemon(player, pkmn)
    if storedBox < 0
      pbDisplayPaused(_INTL("{1} has been added to your party.", pkmn.name))
      if $PokemonGlobal.pokemonSelectionOriginalParty == nil
        @initialItems[0][player.party.length - 1] = pkmn.item_id if @initialItems
      end
      return
    end
    # Messages saying the Pokémon was stored in a PC box
    creator    = @peer.pbGetStorageCreatorName
    curBoxName = @peer.pbBoxName(currentBox)
    boxName    = @peer.pbBoxName(storedBox)
    if storedBox != currentBox
      if creator
        pbDisplayPaused(_INTL("Box \"{1}\" on {2}'s PC was full.", curBoxName, creator))
      else
        pbDisplayPaused(_INTL("Box \"{1}\" on someone's PC was full.", curBoxName))
      end
      pbDisplayPaused(_INTL("{1} was transferred to box \"{2}\".", pkmn.name, boxName))
    else
      if creator
        pbDisplayPaused(_INTL("{1} was transferred to {2}'s PC.", pkmn.name, creator))
      else
        pbDisplayPaused(_INTL("{1} was transferred to someone's PC.", pkmn.name))
      end
      pbDisplayPaused(_INTL("Box \"{1}\" on {2}'s PC.", boxName, creator))
    end
  end

  # Hook pbRecordAndStoreCaughtPokemon to filter caught Pokemon BEFORE processing
  # This prevents crashes when non-catchers try to process Pokemon they didn't catch
  alias coop_original_pbRecordAndStoreCaughtPokemon pbRecordAndStoreCaughtPokemon

  def pbRecordAndStoreCaughtPokemon
    # If not in coop battle, use original behavior
    unless defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      return coop_original_pbRecordAndStoreCaughtPokemon
    end

    # In coop battles, filter caught Pokemon to only process our own
    my_sid = (defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:session_id)) ? MultiplayerClient.session_id.to_s : nil

    if my_sid && @caughtPokemon && @caughtPokemon.length > 0
      # Filter to only Pokemon caught by me based on SID
      my_caught = @caughtPokemon.select do |pkmn|
        # Check custom SID metadata (set by catcher in pbThrowPokeBall)
        catcher_sid = pkmn.instance_variable_get(:@coop_catcher_sid) rescue nil

        if catcher_sid
          is_mine = (catcher_sid == my_sid)
          if is_mine
            MultiplayerDebug.info("✅ RECORD-MINE", "  #{pkmn.name}: catcher_sid=#{catcher_sid} matches my_sid=#{my_sid}") if defined?(MultiplayerDebug)
          else
            MultiplayerDebug.info("❌ RECORD-NOTMINE", "  #{pkmn.name}: catcher_sid=#{catcher_sid} ≠ my_sid=#{my_sid}") if defined?(MultiplayerDebug)
          end
          is_mine
        else
          # No SID set - this shouldn't happen, assume not mine
          MultiplayerDebug.warn("⚠️ RECORD-NOSID", "  #{pkmn.name}: no @coop_catcher_sid set, assuming not mine") if defined?(MultiplayerDebug)
          false
        end
      end

      MultiplayerDebug.info("📊 RECORD-FILTER", "Filtered: #{@caughtPokemon.length} total → #{my_caught.length} mine") if defined?(MultiplayerDebug)

      # Permanently replace array with filtered list - DON'T restore it
      # The original method will process this filtered array and clear it at the end
      @caughtPokemon = my_caught

      # Call original with filtered list
      return coop_original_pbRecordAndStoreCaughtPokemon
    end

    # Fallback to original
    coop_original_pbRecordAndStoreCaughtPokemon
  end
end

##MultiplayerDebug.info("MODULE-13", "Store Pokemon alias loaded - nickname prompt only for catcher")
