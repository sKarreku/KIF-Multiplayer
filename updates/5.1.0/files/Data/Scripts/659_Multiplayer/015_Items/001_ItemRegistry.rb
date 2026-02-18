#===============================================================================
# MODULE: Consolidated Dynamic Item Registration
#===============================================================================
# Single load hook that registers ALL custom multiplayer items in one pass.
# This replaces the separate per-file alias chains that caused the bag to
# freeze for several seconds on first open (each alias re-loaded all item
# data from scratch before adding its own item).
#
# Items registered here:
#   9001 - SHOOTINGSTARCHARM    (Key Item - x1.5 shiny chance)
#   9100..9117 - BLOODBOUND*    (18 type-immunity held items)
#   9200 - RESONANCERESONATOR   (Consumable - shiny + random Family)
#   9201 - RESONANCECORE        (Consumable - shiny + chosen Family)
#
# Handler logic (UseOnPokemon, battle hooks, icon overrides) remains in the
# original files - only the registration was moved here.
#===============================================================================

if defined?(GameData) && defined?(GameData::Item)
  class GameData::Item
    class << self
      alias multiplayer_items_original_load load
      def load
        multiplayer_items_original_load

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("ITEM-REGISTRY", "Post-load: Registering all custom items...")
        end

        #=====================================================================
        # Shooting Star Charm (Key Item)
        #=====================================================================
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

        #=====================================================================
        # Bloodbound Catalysts (18 type-immunity held items)
        #=====================================================================
        if defined?(BloodboundCatalysts)
          base_id_number = 9100
          BloodboundCatalysts::CATALYSTS.each_with_index do |(item_id, (type_sym, type_name, _icon)), idx|
            register({
              :id          => item_id,
              :id_number   => base_id_number + idx,
              :name        => "Bloodbound Catalyst (#{type_name})",
              :name_plural => "Bloodbound Catalysts (#{type_name})",
              :pocket      => 1,
              :price       => 0,
              :description => "A catalyst forged from ancient blood. When held, grants the Pokemon immunity to #{type_name}-type moves.",
              :field_use   => 0,
              :battle_use  => 0,
              :type        => 0
            })
          end
        end

        #=====================================================================
        # Resonance Resonator (Consumable)
        #=====================================================================
        register({
          :id          => :RESONANCERESONATOR,
          :id_number   => 9200,
          :name        => "Resonance Resonator",
          :name_plural => "Resonance Resonators",
          :pocket      => 1,
          :price       => 0,
          :description => "A mysterious device that resonates with a Pokémon's inner frequency, awakening its shiny potential and attuning it to a Family lineage.",
          :field_use   => 1,
          :battle_use  => 0,
          :type        => 0
        })

        #=====================================================================
        # Resonance Core (Consumable)
        #=====================================================================
        register({
          :id          => :RESONANCECORE,
          :id_number   => 9201,
          :name        => "Resonance Core",
          :name_plural => "Resonance Cores",
          :pocket      => 1,
          :price       => 0,
          :description => "A powerful crystalline core that channels resonant energy. Allows you to choose a specific Family and Subfamily for a Pokémon.",
          :field_use   => 1,
          :battle_use  => 0,
          :type        => 0
        })

        if defined?(MultiplayerDebug)
          count = 22  # 1 + 18 + 2 + 1
          MultiplayerDebug.info("ITEM-REGISTRY", "Registered #{count} custom items in single pass (id 9001-9201)")
        end
      end
    end

    #=========================================================================
    # Name/Description overrides for dynamically registered items
    #=========================================================================
    unless method_defined?(:mp_items_original_name)
      alias mp_items_original_name name
      def name
        translated = mp_items_original_name rescue nil
        return translated if translated && !translated.empty?
        return @real_name if @real_name
        return @id.to_s
      end
    end

    unless method_defined?(:mp_items_original_description)
      alias mp_items_original_description description
      def description
        translated = mp_items_original_description rescue nil
        return translated if translated && !translated.empty?
        return @real_description if @real_description
        return ""
      end
    end
  end
end

#===============================================================================
# Debug
#===============================================================================
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("ITEM-REGISTRY", "=" * 60)
  MultiplayerDebug.info("ITEM-REGISTRY", "015_Items/001_ItemRegistry.rb loaded")
  MultiplayerDebug.info("ITEM-REGISTRY", "  Single-pass registration for all custom items")
  MultiplayerDebug.info("ITEM-REGISTRY", "  SHOOTINGSTARCHARM, 18x BLOODBOUND, RESONANCERESONATOR, RESONANCECORE")
  MultiplayerDebug.info("ITEM-REGISTRY", "=" * 60)
end
