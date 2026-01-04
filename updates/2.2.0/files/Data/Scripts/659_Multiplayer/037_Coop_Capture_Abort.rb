#===============================================================================
# Co-op Battle Capture Abort Hook
#===============================================================================
# When a player catches a Pokemon in a co-op wild battle, broadcast abort
# to all other participants so they exit gracefully instead of getting stuck
#===============================================================================

class PokeBattle_Battle
  alias coop_capture_original_pbThrowPokeBall pbThrowPokeBall

  # Class variable to track who initiated the throw on THIS client
  @@local_throw_battler_idx = nil

  def pbThrowPokeBall(idxBattler, ball, catch_rate=nil, showPlayer=false)
    # Track caught Pokemon count before throw
    caught_before = @caughtPokemon ? @caughtPokemon.length : 0

    # Detect if THIS client owns the thrower by checking battler ownership
    # In coop: initiator owns battlers 0,2,4... joiner owns battlers based on their position
    my_battler_indices = []
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      my_sid = MultiplayerClient.session_id.to_s rescue nil
      @battlers.each_with_index do |b, i|
        next if !b || b.opposes?(0)  # Skip nil and enemy battlers
        owner = pbGetOwnerFromBattlerIndex(i)
        owner_sid = owner.respond_to?(:id) ? owner.id.to_s : nil
        if owner_sid == my_sid || owner == $Trainer
          my_battler_indices << i
        end
      end
    end

    ##MultiplayerDebug.info("🎾 THROW-BALL", "Target: #{idxBattler}, My battlers: #{my_battler_indices.inspect}")

    result = coop_capture_original_pbThrowPokeBall(idxBattler, ball, catch_rate, showPlayer)

    # Check if this was a successful capture in a coop battle
    if defined?(CoopBattleState) && CoopBattleState.active?
      caught_after = @caughtPokemon ? @caughtPokemon.length : 0

      # Check if Pokemon was just caught (new entry in @caughtPokemon array)
      if caught_after > caught_before && @caughtPokemon && @caughtPokemon.length > 0
        # Get the last caught Pokemon
        caught_pkmn = @caughtPokemon.last

        # CRITICAL: Ball was thrown FROM a player battler (always even index: 0,2,4,6...)
        # Check if that battler belongs to me
        thrower_idx = idxBattler.even? ? idxBattler : (idxBattler - 1)
        is_my_throw = my_battler_indices.include?(thrower_idx)

        ##MultiplayerDebug.info("🎯 CAPTURE-CHECK", "Pokemon: #{caught_pkmn.name}")
        ##MultiplayerDebug.info("🎯 CAPTURE-CHECK", "  Target: #{idxBattler}, Thrower: #{thrower_idx}")
        ##MultiplayerDebug.info("🎯 CAPTURE-CHECK", "  Is my throw?: #{is_my_throw}")

        if is_my_throw
          # Mark this Pokemon as caught by current player
          # Store catcher's session ID in Pokemon's metadata
          begin
            my_sid = MultiplayerClient.session_id.to_s rescue nil
            if my_sid
              # Store catcher SID in a custom instance variable
              caught_pkmn.instance_variable_set(:@coop_catcher_sid, my_sid)
              ##MultiplayerDebug.info("✅ CAPTURE-MARKED", "Marked #{caught_pkmn.name} as caught by ME (SID: #{my_sid})")
            else
              ##MultiplayerDebug.error("❌ CAPTURE-NOSID", "Cannot mark #{caught_pkmn.name} - no session ID available")
            end
          rescue => e
            ##MultiplayerDebug.error("❌ CAPTURE-ERROR", "Failed to mark catcher SID: #{e.message}")
          end
        else
          ##MultiplayerDebug.info("👥 CAPTURE-REMOTE", "Not marking #{caught_pkmn.name} - thrown by remote player (battler #{idxBattler})")
        end
      end
    end

    return result
  end
end

##MultiplayerDebug.info("MODULE-CAPTURE", "Co-op capture abort hook loaded")
