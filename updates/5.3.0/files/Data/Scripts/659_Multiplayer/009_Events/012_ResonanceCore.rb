#===============================================================================
# MODULE: Resonance Core - Consumable Item
#===============================================================================
# A consumable item that, when used on a Pokémon:
#   1. Opens a carousel UI to pick a Family, then a Subfamily
#   2. Makes the Pokémon shiny (if not already)
#   3. Assigns the chosen Family + Subfamily
#
# Fails if the Pokémon already has a Family assigned.
# Uses default Pokéball icon (Graphics/Items/000) until a custom icon is added.
#
# Autosave fires via TradeUI.autosave_safely after successful use.
#===============================================================================

#===============================================================================
# Item Registration moved to 015_Items/001_ItemRegistry.rb
#===============================================================================

#===============================================================================
# UseOnPokemon Handler
#===============================================================================
ItemHandlers::UseOnPokemon.add(:RESONANCECORE, proc { |item, pkmn, scene|
  # Block if used on an Egg
  if pkmn.egg?
    scene.pbDisplay(_INTL("The Resonance Core can't be used on an Egg."))
    next false
  end

  # Block if Pokémon already has a Family
  if pkmn.has_family?
    scene.pbDisplay(_INTL("{1} already belongs to a Family. The Resonance Core has no effect.", pkmn.name))
    next false
  end

  # Confirmation before opening UI
  shiny_part = pkmn.shiny? ? "is already shiny" : "will become shiny"
  msg = _INTL("Use the Resonance Core on {1}?\n{1} {2} and you will choose a Family.\nThis cannot be undone.", pkmn.name, shiny_part)
  if !pbConfirmMessage(msg)
    next false
  end

  # Open the carousel UI
  result = nil
  pbFadeOutIn {
    result = pbResonanceCoreSelectFamily
  }

  # User cancelled
  if result.nil?
    scene.pbDisplay(_INTL("The Resonance Core was not used."))
    next false
  end

  chosen_family, chosen_subfamily = result

  # Apply shiny if not already (KIF custom shiny style)
  was_shiny = pkmn.shiny? || pkmn.fakeshiny?
  unless was_shiny
    pkmn.shiny = true
    # Randomize KIF custom shiny colors for a fresh appearance
    pkmn.shinyValue = rand(0..360) - 180
    pkmn.shinyR = kurayRNGforChannels
    pkmn.shinyG = kurayRNGforChannels
    pkmn.shinyB = kurayRNGforChannels
    pkmn.shinyKRS = kurayKRSmake
  end

  # Assign family
  pkmn.family = chosen_family
  pkmn.subfamily = chosen_subfamily
  pkmn.family_assigned_at = Time.now.to_i

  # Display result
  family_name = PokemonFamilyConfig.get_full_name(chosen_family, chosen_subfamily)

  if was_shiny
    scene.pbDisplay(_INTL("{1} resonated with the core!\nIt has been attuned to the {2} lineage!", pkmn.name, family_name))
  else
    scene.pbDisplay(_INTL("{1} began to shimmer and glow!\nIt became shiny and was attuned to the {2} lineage!", pkmn.name, family_name))
  end

  # Autosave
  begin
    TradeUI.autosave_safely if defined?(TradeUI) && TradeUI.respond_to?(:autosave_safely)
  rescue => e
    MultiplayerDebug.warn("RESONANCE-CORE", "Autosave failed: #{e.message}") if defined?(MultiplayerDebug)
  end

  scene.pbHardRefresh

  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("RESONANCE-CORE", "Used on #{pkmn.name}: shiny=#{pkmn.shiny?}, family=#{family_name}")
  end

  next true
})

#===============================================================================
# Debug
#===============================================================================
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("RESONANCE-CORE", "=" * 60)
  MultiplayerDebug.info("RESONANCE-CORE", "012_ResonanceCore.rb loaded")
  MultiplayerDebug.info("RESONANCE-CORE", "  RESONANCECORE - Choose Family + Subfamily via carousel UI")
  MultiplayerDebug.info("RESONANCE-CORE", "  Registration handled by 015_Items/001_ItemRegistry.rb")
  MultiplayerDebug.info("RESONANCE-CORE", "=" * 60)
end
