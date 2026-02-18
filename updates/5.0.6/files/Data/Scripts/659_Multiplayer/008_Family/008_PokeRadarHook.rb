#===============================================================================
# MODULE: Family/Subfamily System - PokeRadar Hook
#===============================================================================
# Hooks PokeRadar wild encounter creation to mark Pokemon as radar encounters.
# This prevents Family assignment to PokeRadar shinies.
#===============================================================================

Events.onWildPokemonCreate += proc { |_sender, e|
  begin
    pokemon = e[0]
    next if !pokemon
    next if !$PokemonTemp || !$PokemonTemp.pokeradar

    # Check if this Pokemon was encountered via PokeRadar
    grasses = $PokemonTemp.pokeradar[3]
    next if !grasses || grasses.empty?

    for grass in grasses
      next if !grass || grass.length < 2
      next if $game_player.x != grass[0] || $game_player.y != grass[1]
      # Mark as PokeRadar encounter (prevents Family assignment)
      pokemon.pokeradar_encounter = true if pokemon.respond_to?(:pokeradar_encounter=)
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("FAMILY-POKERADAR", "Marked #{pokemon.name} as PokeRadar encounter at (#{$game_player.x}, #{$game_player.y})")
      end
      break
    end
  rescue => err
    # Never crash the encounter system
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("FAMILY-POKERADAR", "Error in PokeRadar hook: #{err.message}")
    end
  end
}

# Module loaded successfully
if defined?(MultiplayerDebug)
  #MultiplayerDebug.info("FAMILY-POKERADAR", "108_Family_PokeRadar_Hook.rb loaded")
  #MultiplayerDebug.info("FAMILY-POKERADAR", "PokeRadar encounters will not receive Family assignment")
end
