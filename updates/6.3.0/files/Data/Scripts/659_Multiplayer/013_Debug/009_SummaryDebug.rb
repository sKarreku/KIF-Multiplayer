#===============================================================================
# MODULE: Summary Screen Debug Hook
#===============================================================================
# Debug ability display on summary screen
#===============================================================================

class PokemonSummary_Scene
  alias family_debug_original_drawPageThree drawPageThree
  def drawPageThree
    if defined?(MultiplayerDebug) && @pokemon && @pokemon.respond_to?(:has_family?) && @pokemon.has_family?
      MultiplayerDebug.info("SUMMARY", "=== drawPageThree called ===")
      MultiplayerDebug.info("SUMMARY", "  Pokemon: #{@pokemon.name}")

      ability_id = @pokemon.ability_id
      MultiplayerDebug.info("SUMMARY", "  ability_id: #{ability_id.inspect}")
      MultiplayerDebug.info("SUMMARY", "  DATA has key?: #{GameData::Ability::DATA.has_key?(ability_id)}")
      MultiplayerDebug.info("SUMMARY", "  DATA[:PANMORPHOSIS]: #{GameData::Ability::DATA[:PANMORPHOSIS].inspect}")
      MultiplayerDebug.info("SUMMARY", "  DATA[900]: #{GameData::Ability::DATA[900].inspect}")

      ability = @pokemon.ability
      ability2 = @pokemon.ability2

      MultiplayerDebug.info("SUMMARY", "  ability object: #{ability.inspect}")

      if ability
        MultiplayerDebug.info("SUMMARY", "  ability.class: #{ability.class}")
        MultiplayerDebug.info("SUMMARY", "  ability.id: #{ability.id}")
        MultiplayerDebug.info("SUMMARY", "  ability.id_number: #{ability.id_number}")
        MultiplayerDebug.info("SUMMARY", "  ability.real_name: '#{ability.real_name}'")
        begin
          name_result = ability.name
          MultiplayerDebug.info("SUMMARY", "  ability.name: '#{name_result}'")
        rescue => e
          MultiplayerDebug.error("SUMMARY", "  ability.name ERROR: #{e.message}")
          MultiplayerDebug.error("SUMMARY", "  #{e.backtrace[0..3].join("\n  ")}")
        end
      else
        MultiplayerDebug.error("SUMMARY", "  ability is nil!")
      end
    end

    family_debug_original_drawPageThree
  end
end

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("FAMILY-TALENT", "115_Family_Summary_Debug.rb loaded")
end
