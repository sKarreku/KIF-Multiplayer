#===============================================================================
# MODULE: Family/Subfamily System - Ability Toggle in Summary
#===============================================================================
# Allows toggling between natural ability and family talent in summary screen.
#
# Features:
# - Press Shift/ACTION button on Skills page (page 3) to toggle between abilities
# - Shows natural ability by default
# - Shows family talent when toggled
# - Both abilities are active in battle (handled by 110_Family_Talent_Infusion.rb)
#
# Integration:
# - Hooks pbScene input handling to add toggle on page 3
# - Hooks drawPageThree to display toggled ability
#===============================================================================

class PokemonSummary_Scene
  # Add instance variable to track which ability to display
  alias family_ability_toggle_original_pbStartScene pbStartScene
  def pbStartScene(*args)
    family_ability_toggle_original_pbStartScene(*args)
    @showing_ability2 = false  # Default: show natural ability
  end

  # Hook pbScene to intercept ACTION button on page 3 (Skills)
  alias family_ability_toggle_original_pbScene pbScene
  def pbScene
    @pokemon.play_cry
    loop do
      Graphics.update
      Input.update
      pbUpdate
      dorefresh = false

      # === FAMILY ABILITY TOGGLE: Check for Shift/ACTION press on Skills page ===
      if Input.trigger?(Input::ACTION)
        # Check if Family Abilities are enabled in settings
        family_abilities_enabled = true
        if defined?($PokemonSystem) && $PokemonSystem && $PokemonSystem.respond_to?(:mp_family_abilities_enabled)
          family_abilities_enabled = ($PokemonSystem.mp_family_abilities_enabled != 0)
        end

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("ABILITY-TOGGLE", "ACTION pressed! Page: #{@page}, has_family: #{@pokemon.respond_to?(:has_family?) && @pokemon.has_family?}, abilities_enabled: #{family_abilities_enabled}")
        end

        # Check if on Skills page (page 3) AND Pokemon has family AND abilities enabled
        if @page == 3 && @pokemon && @pokemon.respond_to?(:has_family?) && @pokemon.has_family? && family_abilities_enabled
          ability2 = @pokemon.ability2

          if defined?(MultiplayerDebug)
            MultiplayerDebug.info("ABILITY-TOGGLE", "On Skills page with family! ability2: #{ability2.inspect}")
          end

          if ability2
            # Toggle ability display
            @showing_ability2 = !@showing_ability2

            # Play sound effect
            pbSEStop
            @pokemon.play_cry

            # Refresh page to show new ability
            dorefresh = true

            if defined?(MultiplayerDebug)
              MultiplayerDebug.info("ABILITY-TOGGLE", "Toggled to show: #{@showing_ability2 ? 'Family Talent (ability2)' : 'Natural Ability (ability1)'}")
            end
          else
            # No ability2, just play cry normally
            pbSEStop
            @pokemon.play_cry

            if defined?(MultiplayerDebug)
              MultiplayerDebug.info("ABILITY-TOGGLE", "No ability2 found, just playing cry")
            end
          end
        else
          # Not on Skills page or no family, just play cry normally
          pbSEStop
          @pokemon.play_cry

          if defined?(MultiplayerDebug)
            MultiplayerDebug.info("ABILITY-TOGGLE", "Not on Skills page or no family, just playing cry")
          end
        end
      # ===========================================================================

      elsif Input.trigger?(Input::BACK)
        pbPlayCloseMenuSE
        break
      elsif Input.trigger?(Input::USE)
        if @page == 4
          pbPlayDecisionSE
          pbMoveSelection
          dorefresh = true
        elsif @page == 5
          @page -= 1
          pbPlayDecisionSE
          #pbRibbonSelection
          #dorefresh = true
        elsif !@inbattle
          pbPlayDecisionSE
          dorefresh = pbOptions
        end
      elsif Input.trigger?(Input::UP) && @partyindex > 0
        oldindex = @partyindex
        pbGoToPrevious
        @showing_ability2 = false  # Reset toggle when switching Pokemon
        if @partyindex != oldindex
          pbChangePokemon
          @ribbonOffset = 0
          dorefresh = true
        end
      elsif Input.trigger?(Input::DOWN) && @partyindex < @party.length - 1
        oldindex = @partyindex
        pbGoToNext
        @showing_ability2 = false  # Reset toggle when switching Pokemon
        if @partyindex != oldindex
          pbChangePokemon
          @ribbonOffset = 0
          dorefresh = true
        end
      elsif Input.trigger?(Input::LEFT) && !@pokemon.egg?
        oldpage = @page
        @page -= 1
        @page = 1 if @page < 1
        @page = 5 if @page > 5
        if @page != oldpage # Move to next page
          pbSEPlay("GUI summary change page")
          @ribbonOffset = 0
          @showing_ability2 = false  # Reset when changing pages
          dorefresh = true
        end
      elsif Input.trigger?(Input::RIGHT) && !@pokemon.egg?
        if @page == 4 && !$Trainer.has_pokedex
          pbSEPlay("GUI sel buzzer")
        else
          oldpage = @page
          @page += 1
          @page = 1 if @page < 1
          @page = 5 if @page > 5
          if @page != oldpage # Move to next page
            pbSEPlay("GUI summary change page")
            @ribbonOffset = 0
            @showing_ability2 = false  # Reset when changing pages
            dorefresh = true
          end
        end
      end

      if dorefresh
        drawPage(@page)
      end
    end
    return @partyindex
  end

  # Hook drawPageThree to show toggled ability and toggle indicator
  alias family_ability_toggle_original_drawPageThree drawPageThree
  def drawPageThree
    # Call original first
    family_ability_toggle_original_drawPageThree

    # Check if Family Abilities are enabled in settings
    family_abilities_enabled = true
    if defined?($PokemonSystem) && $PokemonSystem && $PokemonSystem.respond_to?(:mp_family_abilities_enabled)
      family_abilities_enabled = ($PokemonSystem.mp_family_abilities_enabled != 0)
    end

    # Add toggle indicator for family Pokemon (only if abilities enabled)
    if family_abilities_enabled && @pokemon && @pokemon.respond_to?(:has_family?) && @pokemon.has_family?
      ability2 = @pokemon.ability2
      if ability2
        overlay = @sprites["overlay"].bitmap
        base = Color.new(248, 248, 248)
        shadow = Color.new(104, 104, 104)

        # Clear the "Ability" label area to redraw with toggle indicator
        overlay.fill_rect(224, 278, 130, 32, Color.new(0, 0, 0, 0))

        # Draw ability label with toggle indicator
        textpos = []
        if @showing_ability2
          # Show "Family Ability" when displaying ability2
          textpos.push([_INTL("Family Ability"), 224, 278, 0, base, shadow])
        else
          # Show "Ability" when displaying ability1
          textpos.push([_INTL("Ability"), 224, 278, 0, base, shadow])
        end
        pbDrawTextPositions(overlay, textpos)

        # If showing ability2, redraw ability section
        if @showing_ability2
          # Clear existing ability text
          overlay.fill_rect(362, 278, 150, 32, Color.new(0, 0, 0, 0))  # Ability name
          overlay.fill_rect(224, 320, 282, 64, Color.new(0, 0, 0, 0))  # Ability description

          # Draw ability2 name and description
          textpos = []
          textpos.push([ability2.name, 362, 278, 0, Color.new(64, 64, 64), Color.new(176, 176, 176)])
          pbDrawTextPositions(overlay, textpos)
          drawTextEx(overlay, 224, 320, 282, 2, ability2.description, Color.new(64, 64, 64), Color.new(176, 176, 176))

          if defined?(MultiplayerDebug)
            MultiplayerDebug.info("ABILITY-TOGGLE", "Displaying ability2: #{ability2.name}")
          end
        end
      end
    end
  end
end

#-------------------------------------------------------------------------------
# Module loaded successfully
#-------------------------------------------------------------------------------
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("ABILITY-TOGGLE", "=" * 60)
  MultiplayerDebug.info("ABILITY-TOGGLE", "118_Family_Ability_Toggle.rb loaded successfully")
  MultiplayerDebug.info("ABILITY-TOGGLE", "Press Shift/ACTION on Skills page to toggle abilities")
  MultiplayerDebug.info("ABILITY-TOGGLE", "=" * 60)
end
