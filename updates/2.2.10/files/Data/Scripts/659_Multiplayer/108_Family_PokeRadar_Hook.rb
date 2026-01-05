#===============================================================================
# MODULE: Family/Subfamily System - PokeRadar Hook
#===============================================================================
# Hooks PokeRadar wild encounter creation to mark Pokemon as radar encounters.
# This prevents Family assignment to PokeRadar shinies.
#===============================================================================

Events.onWildPokemonCreate += proc { |_sender, e|
  pokemon = e[0]
  next if !$PokemonTemp.pokeradar

  # Check if this Pokemon was encountered via PokeRadar
  grasses = $PokemonTemp.pokeradar[3]
  next if !grasses

  for grass in grasses
    next if $game_player.x != grass[0] || $game_player.y != grass[1]
    # Mark as PokeRadar encounter (prevents Family assignment)
    pokemon.pokeradar_encounter = true
    break
  end
}

# Module loaded successfully
if defined?(MultiplayerDebug)
  #MultiplayerDebug.info("FAMILY-POKERADAR", "108_Family_PokeRadar_Hook.rb loaded")
  #MultiplayerDebug.info("FAMILY-POKERADAR", "PokeRadar encounters will not receive Family assignment")
end
