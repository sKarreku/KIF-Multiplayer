#===============================================================================
# MODULE: Resonance Resonator - Consumable Item
#===============================================================================
# A consumable item that, when used on a Pokémon:
#   1. Makes it shiny (if not already shiny)
#   2. Assigns a random Family + Subfamily (if it doesn't already have one)
#
# Fails if the Pokémon already has a Family assigned.
# Shows a confirmation popup before applying.
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
ItemHandlers::UseOnPokemon.add(:RESONANCERESONATOR, proc { |item, pkmn, scene|
  # Block if used on an Egg
  if pkmn.egg?
    scene.pbDisplay(_INTL("The Resonance Resonator can't be used on an Egg."))
    next false
  end

  # Block if Pokémon already has a Family
  if pkmn.has_family?
    scene.pbDisplay(_INTL("{1} already belongs to a Family. The Resonance Resonator has no effect.", pkmn.name))
    next false
  end

  # Build preview message
  shiny_part = pkmn.shiny? ? "is already shiny" : "will become shiny"
  msg = _INTL("Use the Resonance Resonator on {1}?\n{1} {2} and will be attuned to a random Family.\nThis cannot be undone.", pkmn.name, shiny_part)

  # Confirmation popup
  if !pbConfirmMessage(msg)
    next false
  end

  # --- Apply shiny if not already (KIF custom shiny style) ---
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

  # --- Assign random Family + Subfamily using true randomness ---
  families = PokemonFamilyConfig::FAMILIES
  total_family_weight = families.values.map { |f| f[:weight] }.sum
  roll = rand(total_family_weight)
  cumulative = 0
  chosen_family = 0
  families.each do |id, data|
    cumulative += data[:weight]
    if roll < cumulative
      chosen_family = id
      break
    end
  end

  # Select subfamily
  base_idx = chosen_family * 4
  subfamily_data = (0..3).map { |i| PokemonFamilyConfig::SUBFAMILIES[base_idx + i] }
  total_sub_weight = subfamily_data.map { |s| s[:weight] }.sum
  sub_roll = rand(total_sub_weight)
  cumulative = 0
  chosen_subfamily = 0
  subfamily_data.each_with_index do |sub, idx|
    cumulative += sub[:weight]
    if sub_roll < cumulative
      chosen_subfamily = idx
      break
    end
  end

  pkmn.family = chosen_family
  pkmn.subfamily = chosen_subfamily
  pkmn.family_assigned_at = Time.now.to_i

  # --- Display result ---
  family_name = PokemonFamilyConfig.get_full_name(chosen_family, chosen_subfamily)

  if was_shiny
    scene.pbDisplay(_INTL("{1} resonated with the device!\nIt has been attuned to the {2} Family!", pkmn.name, family_name))
  else
    scene.pbDisplay(_INTL("{1} began to shimmer and glow!\nIt became shiny and was attuned to the {2} Family!", pkmn.name, family_name))
  end

  # Autosave
  begin
    TradeUI.autosave_safely if defined?(TradeUI) && TradeUI.respond_to?(:autosave_safely)
  rescue => e
    MultiplayerDebug.warn("RESONANCE", "Autosave failed: #{e.message}") if defined?(MultiplayerDebug)
  end

  scene.pbHardRefresh

  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("RESONANCE", "Used on #{pkmn.name}: shiny=#{pkmn.shiny?}, family=#{family_name}")
  end

  next true
})

#===============================================================================
# Debug
#===============================================================================
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("RESONANCE", "=" * 60)
  MultiplayerDebug.info("RESONANCE", "010_ResonanceResonator.rb loaded")
  MultiplayerDebug.info("RESONANCE", "  RESONANCERESONATOR - Shiny + random Family assignment")
  MultiplayerDebug.info("RESONANCE", "  Registration handled by 015_Items/001_ItemRegistry.rb")
  MultiplayerDebug.info("RESONANCE", "=" * 60)
end
