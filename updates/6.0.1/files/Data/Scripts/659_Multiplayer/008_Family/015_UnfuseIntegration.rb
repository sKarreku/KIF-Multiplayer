#===============================================================================
# MODULE: Family/Subfamily System - Unfuse Integration
#===============================================================================
# Restores original family data to both parent Pokemon when unfusing.
#
# When a fused Pokemon is unfused:
# - Body Pokemon gets its original family back (from body_family)
# - Head Pokemon gets its original family back (from head_family)
#
# This ensures that unfusing returns both Pokemon to their original state.
#===============================================================================

# Hook pbUnfuse function to restore family data
module FamilyUnfuseIntegration
  def self.restore_family_data(fused_pokemon, body_pokemon, head_pokemon)
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("FAMILY-UNFUSE", "=== Restoring Family Data ===")
      MultiplayerDebug.info("FAMILY-UNFUSE", "Fused Pokemon: #{fused_pokemon.name}")
      MultiplayerDebug.info("FAMILY-UNFUSE", "Body stored family: #{fused_pokemon.body_family}")
      MultiplayerDebug.info("FAMILY-UNFUSE", "Head stored family: #{fused_pokemon.head_family}")
      MultiplayerDebug.info("FAMILY-UNFUSE", "Current fusion family: #{fused_pokemon.family}")
      MultiplayerDebug.info("FAMILY-UNFUSE", "Body shiny: #{body_pokemon.shiny?}")
      MultiplayerDebug.info("FAMILY-UNFUSE", "Head shiny: #{head_pokemon.shiny?}")
    end

    # Check if this was a wild-caught fusion (neither parent had stored family)
    # In this case, the family was assigned to the fusion AFTER catching
    wild_caught_fusion = fused_pokemon.body_family.nil? && fused_pokemon.head_family.nil?

    if wild_caught_fusion && fused_pokemon.family
      # Wild-caught fusion with family: Give family to the SHINY component
      # (since family is only assigned to shinies, at least one must be shiny)

      if head_pokemon.shiny? && !body_pokemon.shiny?
        # Only head is shiny - give family to head
        head_pokemon.family = fused_pokemon.family
        head_pokemon.subfamily = fused_pokemon.subfamily
        head_pokemon.family_assigned_at = fused_pokemon.family_assigned_at

        if defined?(MultiplayerDebug)
          family_name = PokemonFamilyConfig::FAMILIES[fused_pokemon.family][:name]
          MultiplayerDebug.info("FAMILY-UNFUSE", "Wild fusion: Gave family #{family_name} to shiny HEAD")
        end

      elsif body_pokemon.shiny? && !head_pokemon.shiny?
        # Only body is shiny - give family to body
        body_pokemon.family = fused_pokemon.family
        body_pokemon.subfamily = fused_pokemon.subfamily
        body_pokemon.family_assigned_at = fused_pokemon.family_assigned_at

        if defined?(MultiplayerDebug)
          family_name = PokemonFamilyConfig::FAMILIES[fused_pokemon.family][:name]
          MultiplayerDebug.info("FAMILY-UNFUSE", "Wild fusion: Gave family #{family_name} to shiny BODY")
        end

      elsif body_pokemon.shiny? && head_pokemon.shiny?
        # Both are shiny - give family to BOTH (rare double shiny)
        body_pokemon.family = fused_pokemon.family
        body_pokemon.subfamily = fused_pokemon.subfamily
        body_pokemon.family_assigned_at = fused_pokemon.family_assigned_at

        head_pokemon.family = fused_pokemon.family
        head_pokemon.subfamily = fused_pokemon.subfamily
        head_pokemon.family_assigned_at = fused_pokemon.family_assigned_at

        if defined?(MultiplayerDebug)
          family_name = PokemonFamilyConfig::FAMILIES[fused_pokemon.family][:name]
          MultiplayerDebug.info("FAMILY-UNFUSE", "Wild fusion: Both shiny - gave family #{family_name} to BOTH")
        end

      else
        # Neither is shiny (shouldn't happen since family requires shiny, but fallback to body)
        body_pokemon.family = fused_pokemon.family
        body_pokemon.subfamily = fused_pokemon.subfamily
        body_pokemon.family_assigned_at = fused_pokemon.family_assigned_at

        if defined?(MultiplayerDebug)
          family_name = PokemonFamilyConfig::FAMILIES[fused_pokemon.family][:name]
          MultiplayerDebug.info("FAMILY-UNFUSE", "Wild fusion: No shiny detected - fallback gave family #{family_name} to BODY")
        end
      end

      return  # Don't continue to normal restoration logic
    end

    # Normal case: Restore stored family data from fusion

    # Restore body Pokemon's family
    if fused_pokemon.body_family
      body_pokemon.family = fused_pokemon.body_family
      body_pokemon.subfamily = fused_pokemon.body_subfamily
      body_pokemon.family_assigned_at = fused_pokemon.body_family_assigned_at

      if defined?(MultiplayerDebug)
        family_name = PokemonFamilyConfig::FAMILIES[fused_pokemon.body_family][:name]
        MultiplayerDebug.info("FAMILY-UNFUSE", "Restored body family: #{family_name}")
      end
    end

    # Restore head Pokemon's family
    if fused_pokemon.head_family
      head_pokemon.family = fused_pokemon.head_family
      head_pokemon.subfamily = fused_pokemon.head_subfamily
      head_pokemon.family_assigned_at = fused_pokemon.head_family_assigned_at

      if defined?(MultiplayerDebug)
        family_name = PokemonFamilyConfig::FAMILIES[fused_pokemon.head_family][:name]
        MultiplayerDebug.info("FAMILY-UNFUSE", "Restored head family: #{family_name}")
      end
    end
  end
end

# Hook the pbUnfuse function to restore family data
# This needs to be done carefully to insert at the right point
def pbUnfuse(pokemon, scene, supersplicers, pcPosition = nil)
  if pokemon.species_data.id_number > (NB_POKEMON * NB_POKEMON) + NB_POKEMON #triple fusion
    scene.pbDisplay(_INTL("{1} cannot be unfused.", pokemon.name))
    return false
  end

  bodyPoke = getBasePokemonID(pokemon.species_data.id_number, true)
  headPoke = getBasePokemonID(pokemon.species_data.id_number, false)
  $PokemonSystem.unfusetraded = 0 unless $PokemonSystem.unfusetraded
  if (pokemon.obtain_method == 2 || pokemon.ot != $Trainer.name) && $PokemonSystem.unfusetraded == 0
    scene.pbDisplay(_INTL("You can't unfuse a Pokémon obtained in a trade!"))
    return false
  else
    if Kernel.pbConfirmMessage(_INTL("Should {1} be unfused?", pokemon.name))
      keepInParty = 0
      if $Trainer.party.length >= 6 && !pcPosition
        scene.pbDisplay(_INTL("Your party is full! Keep which Pokémon in party?"))
        choice = Kernel.pbMessage("Select a Pokémon to keep in your party.", [_INTL("{1}", PBSpecies.getName(bodyPoke)), _INTL("{1}", PBSpecies.getName(headPoke)), "Cancel"], 2)
        if choice == 2
          return false
        else
          keepInParty = choice
        end
      end

      scene.pbDisplay(_INTL("Unfusing ... "))
      scene.pbDisplay(_INTL(" ... "))
      scene.pbDisplay(_INTL(" ... "))

      if pokemon.exp_when_fused_head == nil || pokemon.exp_when_fused_body == nil
        new_level = calculateUnfuseLevelOldMethod(pokemon, supersplicers)
        body_level = new_level
        head_level = new_level
        poke1 = Pokemon.new(bodyPoke, body_level)
        poke2 = Pokemon.new(headPoke, head_level)
      else
        exp_body = pokemon.exp_when_fused_body + pokemon.exp_gained_since_fused
        exp_head = pokemon.exp_when_fused_head + pokemon.exp_gained_since_fused

        poke1 = Pokemon.new(bodyPoke, pokemon.level)
        poke2 = Pokemon.new(headPoke, pokemon.level)
        poke1.exp = exp_body
        poke2.exp = exp_head
      end
      body_level = poke1.level
      head_level = poke2.level

      #KurayX - KURAYX_ABOUT_SHINIES
      poke2.shinyValue=pokemon.shinyValue
      #

      # pokemon = body
      # poke2 = head

      # === FAMILY UNFUSE INTEGRATION: Restore family data AFTER species change ===
      # NOTE: This must happen AFTER pokemon.species is set (line 250) because
      # pokemon becomes the body Pokemon, not poke1
      # We'll call this at the end, right before the success message
      # =============================================================================

      pokemon.spriteform_body=nil
      pokemon.spriteform_head=nil
      pokemon.exp_gained_since_fused = 0
      pokemon.exp_when_fused_head = nil
      pokemon.exp_when_fused_body = nil
      pokemon.kuraycustomfile = nil
      poke2.kuraycustomfile = nil
      poke2.name = pokemon.name unless !pokemon.nicknamed?
      poke2.force_gender = pokemon.head_gender?

      if pokemon.shiny?
        pokemon.shiny = false
        if pokemon.body_shinyhue == nil && pokemon.head_shinyhue == nil
            pokemon.head_shinyhue=pokemon.shinyValue?
            pokemon.head_shinyr=pokemon.shinyR?
            pokemon.head_shinyg=pokemon.shinyG?
            pokemon.head_shinyb=pokemon.shinyB?
            pokemon.head_shinykrs=pokemon.shinyKRS?.clone
        end
        if pokemon.bodyShiny? && pokemon.headShiny?
          pokemon.shiny = true
          poke2.shiny = true
          pokemon.shinyValue=pokemon.body_shinyhue?
          pokemon.shinyR=pokemon.body_shinyr?
          pokemon.shinyG=pokemon.body_shinyg?
          pokemon.shinyB=pokemon.body_shinyb?
          pokemon.shinyKRS=pokemon.body_shinykrs?.clone
          poke2.shinyValue=pokemon.head_shinyhue?
          poke2.shinyR=pokemon.head_shinyr?
          poke2.shinyG=pokemon.head_shinyg?
          poke2.shinyB=pokemon.head_shinyb?
          poke2.shinyKRS=pokemon.head_shinykrs?.clone
          pokemon.natural_shiny = true if pokemon.natural_shiny && !pokemon.debug_shiny
          poke2.natural_shiny = true if pokemon.natural_shiny && !pokemon.debug_shiny
        elsif pokemon.bodyShiny?
          pokemon.shiny = true
          pokemon.shinyValue=pokemon.body_shinyhue?
          pokemon.shinyR=pokemon.body_shinyr?
          pokemon.shinyG=pokemon.body_shinyg?
          pokemon.shinyB=pokemon.body_shinyb?
          pokemon.shinyKRS=pokemon.body_shinykrs?.clone
          poke2.shiny = false
          pokemon.natural_shiny = true if pokemon.natural_shiny && !pokemon.debug_shiny
        elsif pokemon.headShiny?
          poke2.shiny = true
          poke2.shinyValue=pokemon.head_shinyhue?
          poke2.shinyR=pokemon.head_shinyr?
          poke2.shinyG=pokemon.head_shinyg?
          poke2.shinyB=pokemon.head_shinyb?
          poke2.shinyKRS=pokemon.head_shinykrs?.clone
          pokemon.shiny = false
          poke2.natural_shiny = true if pokemon.natural_shiny && !pokemon.debug_shiny
        else
          poke2.shiny = true
          poke2.shinyValue=pokemon.shinyValue?
          poke2.shinyR=pokemon.shinyR?
          poke2.shinyG=pokemon.shinyG?
          poke2.shinyB=pokemon.shinyB?
          poke2.shinyKRS=pokemon.shinyKRS?.clone

          newvalue = rand(0..360) - 180
          pokemon.shinyValue=newvalue
          pokemon.shinyR=kurayRNGforChannels
          pokemon.shinyG=kurayRNGforChannels
          pokemon.shinyB=kurayRNGforChannels
          pokemon.shinyKRS=kurayKRSmake
        end
      end

      pokemon.ability_index = pokemon.body_original_ability_index if pokemon.body_original_ability_index
      poke2.ability_index = pokemon.head_original_ability_index if pokemon.head_original_ability_index

      pokemon.ability2_index=nil
      pokemon.ability2=nil
      poke2.ability2_index=nil
      poke2.ability2=nil

      pokemon.debug_shiny = true if pokemon.debug_shiny && pokemon.body_shiny
      poke2.debug_shiny = true if pokemon.debug_shiny && poke2.head_shiny

      pokemon.body_shiny = false
      pokemon.head_shiny = false

      if !pokemon.shiny?
        pokemon.debug_shiny = false
      end
      if !poke2.shiny?
        poke2.debug_shiny = false
      end

      currentBoxFull = pcPosition != nil && (pcPosition[0] == -1 ? $PokemonStorage.party_full? : $PokemonStorage[pcPosition[0]].full?)

      if $Trainer.party.length >= 6
        if (keepInParty == 0)
          if currentBoxFull && scene.is_a?(PokemonStorageScene) && !scene.screen.heldpkmn
            scene.screen.pbSetHeldPokemon(poke2)
          else
            $PokemonStorage.pbStoreCaught(poke2)
            scene.pbDisplay(_INTL("{1} was sent to the PC.", poke2.name))
          end
        else
          poke2 = Pokemon.new(bodyPoke, body_level)
          poke1 = Pokemon.new(headPoke, head_level)

          if pcPosition != nil
            box = pcPosition[0]
            index = pcPosition[1]

            if currentBoxFull && scene.is_a?(PokemonStorageScene) && !scene.screen.heldpkmn
              scene.screen.pbSetHeldPokemon(poke2)
            else
              $PokemonStorage.pbStoreCaught(poke2)
            end
          else
            $PokemonStorage.pbStoreCaught(poke2)
            scene.pbDisplay(_INTL("{1} was sent to the PC.", poke2.name))
          end

        end
      else
        if pcPosition != nil
          box = pcPosition[0]
          index = pcPosition[1]

          if box == -1
            Kernel.pbAddPokemonSilent(poke2, poke2.level)
          elsif currentBoxFull && scene.is_a?(PokemonStorageScene) && !scene.screen.heldpkmn
            scene.screen.pbSetHeldPokemon(poke2)
          else
            $PokemonStorage.pbStoreCaught(poke2)
          end
        else
          Kernel.pbAddPokemonSilent(poke2, poke2.level)
        end
      end

      $Trainer.pokedex.set_seen(poke1.species)
      $Trainer.pokedex.set_owned(poke1.species)
      $Trainer.pokedex.set_seen(poke2.species)
      $Trainer.pokedex.set_owned(poke2.species)

      pokemon.species = poke1.species
      pokemon.level = poke1.level
      pokemon.name = poke1.name
      pokemon.moves = poke1.moves
      pokemon.obtain_method = 0
      poke1.obtain_method = 0
      poke1.kuraycustomfile = nil
      poke2.kuraycustomfile = nil

      # === FAMILY UNFUSE INTEGRATION: Restore family data ===
      # pokemon is now the body Pokemon (species was changed at line 250)
      # poke2 is the head Pokemon
      FamilyUnfuseIntegration.restore_family_data(pokemon, pokemon, poke2)
      # ======================================================

      scene.pbHardRefresh
      scene.pbDisplay(_INTL("Your Pokémon were successfully unfused! "))
      return true
    end
  end
end

#-------------------------------------------------------------------------------
# Module loaded successfully
#-------------------------------------------------------------------------------
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("FAMILY-UNFUSE", "=" * 60)
  MultiplayerDebug.info("FAMILY-UNFUSE", "117_Family_Unfuse_Integration.rb loaded successfully")
  MultiplayerDebug.info("FAMILY-UNFUSE", "Unfuse hook registered - family data will be restored on unfuse")
  MultiplayerDebug.info("FAMILY-UNFUSE", "=" * 60)
end
