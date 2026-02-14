#===============================================================================
# MODULE: Event System - Dynamic Item Registration
#===============================================================================
# Registers event-related items dynamically after GameData is loaded.
# Follows the same pattern as 114_Family_Abilities.rb for abilities.
#
# Items registered:
#   - SHOOTINGSTARCHARM: Permanent x1.5 shiny chance multiplier
#===============================================================================

if defined?(GameData) && defined?(GameData::Item)
  class GameData::Item
    class << self
      alias event_items_original_load load
      def load
        event_items_original_load

        # Register event items AFTER DATA loaded from items.dat
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("EVENT-ITEMS", "Post-load: Registering event items...")
        end

        # Shooting Star Charm - permanent x1.5 shiny chance
        # Pocket 8 = Key Items (can't be sold/tossed)
        register({
          :id          => :SHOOTINGSTARCHARM,
          :id_number   => 9001,
          :name        => "Shooting Star Charm",
          :name_plural => "Shooting Star Charms",
          :pocket      => 8,
          :price       => 0,
          :description => "A mystical charm that glows with starlight. Increases shiny encounter rate by 1.5x while in your bag.",
          :field_use   => 0,
          :battle_use  => 0,
          :type        => 0
        })

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("EVENT-ITEMS", "  Registered SHOOTINGSTARCHARM (id_number: 9001)")
          MultiplayerDebug.info("EVENT-ITEMS", "  DATA[:SHOOTINGSTARCHARM] = #{DATA[:SHOOTINGSTARCHARM] ? 'OK' : 'FAILED'}")
        end
      end
    end

    # Override name to handle dynamically registered items
    unless method_defined?(:event_items_original_name)
      alias event_items_original_name name
      def name
        translated = event_items_original_name rescue nil
        return translated if translated && !translated.empty?
        return @real_name if @real_name
        return @id.to_s
      end
    end

    # Override description to handle dynamically registered items
    unless method_defined?(:event_items_original_description)
      alias event_items_original_description description
      def description
        translated = event_items_original_description rescue nil
        return translated if translated && !translated.empty?
        return @real_description if @real_description
        return ""
      end
    end
  end

  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("EVENT-ITEMS", "Item registration hooks installed")
  end
else
  if defined?(MultiplayerDebug)
    MultiplayerDebug.error("EVENT-ITEMS", "GameData::Item not available at load time")
  end
end

#===============================================================================
# Debug info
#===============================================================================
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("EVENT-ITEMS", "=" * 60)
  MultiplayerDebug.info("EVENT-ITEMS", "158_Event_Items.rb loaded")
  MultiplayerDebug.info("EVENT-ITEMS", "Dynamic item registration ready")
  MultiplayerDebug.info("EVENT-ITEMS", "  SHOOTINGSTARCHARM - x1.5 shiny chance when owned")
  MultiplayerDebug.info("EVENT-ITEMS", "=" * 60)
end
