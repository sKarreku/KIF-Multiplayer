#===============================================================================
# MODULE: Bloodbound Catalysts
#===============================================================================
# 18 held items that each grant the holding Pokemon immunity to one type.
# When a Pokemon holds a Bloodbound Catalyst, it becomes immune to moves
# of that element type (damage = 0).
#
# Items:
#   BLOODBOUNDNORMAL, BLOODBOUNDFIRE, BLOODBOUNDWATER, BLOODBOUNDGRASS,
#   BLOODBOUNDELECTRIC, BLOODBOUNDICE, BLOODBOUNDFIGHTING, BLOODBOUNDPOISON,
#   BLOODBOUNDGROUND, BLOODBOUNDFLYING, BLOODBOUNDPSYCHIC, BLOODBOUNDBUG,
#   BLOODBOUNDROCK, BLOODBOUNDGHOST, BLOODBOUNDDRAGON, BLOODBOUNDDARK,
#   BLOODBOUNDSTEEL, BLOODBOUNDFAIRY
#
# Icons: Graphics/Multiplayer/<Type>.png
#===============================================================================

module BloodboundCatalysts
  # Map: item symbol => [type symbol, display name, icon file]
  CATALYSTS = {
    :BLOODBOUNDNORMAL   => [:NORMAL,   "Normal",   "Normal"],
    :BLOODBOUNDFIRE     => [:FIRE,     "Fire",     "Fire"],
    :BLOODBOUNDWATER    => [:WATER,    "Water",    "Water"],
    :BLOODBOUNDGRASS    => [:GRASS,    "Grass",    "Grass"],
    :BLOODBOUNDELECTRIC => [:ELECTRIC, "Electric", "Electric"],
    :BLOODBOUNDICE      => [:ICE,      "Ice",      "Ice"],
    :BLOODBOUNDFIGHTING => [:FIGHTING, "Fighting", "Fighting"],
    :BLOODBOUNDPOISON   => [:POISON,   "Poison",   "Poison"],
    :BLOODBOUNDGROUND   => [:GROUND,   "Ground",   "Ground"],
    :BLOODBOUNDFLYING   => [:FLYING,   "Flying",   "Flying"],
    :BLOODBOUNDPSYCHIC  => [:PSYCHIC,  "Psychic",  "Psychic"],
    :BLOODBOUNDBUG      => [:BUG,      "Bug",      "Bug"],
    :BLOODBOUNDROCK     => [:ROCK,     "Rock",     "Rock"],
    :BLOODBOUNDGHOST    => [:GHOST,    "Ghost",    "Ghost"],
    :BLOODBOUNDDRAGON   => [:DRAGON,   "Dragon",   "Dragon"],
    :BLOODBOUNDDARK     => [:DARK,     "Dark",     "Dark"],
    :BLOODBOUNDSTEEL    => [:STEEL,    "Steel",    "Steel"],
    :BLOODBOUNDFAIRY    => [:FAIRY,    "Fairy",    "Fairy"]
  }

  # Reverse lookup: type symbol => item symbol (for fast battle checks)
  TYPE_TO_ITEM = {}
  CATALYSTS.each { |item_id, (type_sym, _, _)| TYPE_TO_ITEM[type_sym] = item_id }

  # All catalyst item symbols as a Set for quick lookup
  ALL_ITEMS = CATALYSTS.keys

  # Check if a battler is holding a catalyst that grants immunity to move_type
  def self.holder_immune?(target, move_type)
    return false unless move_type && target
    item_id = TYPE_TO_ITEM[move_type]
    return false unless item_id
    target.hasActiveItem?(item_id)
  end
end

#===============================================================================
# Item Registration moved to 015_Items/001_ItemRegistry.rb
#===============================================================================

#===============================================================================
# Icon Override - point to Graphics/Multiplayer/<Type>.png
#===============================================================================
if defined?(GameData) && defined?(GameData::Item)
  class GameData::Item
    class << self
      alias bloodbound_icon_original icon_filename
      def icon_filename(item)
        return bloodbound_icon_original(item) if item.nil?
        item_data = self.try_get(item)
        if item_data && BloodboundCatalysts::CATALYSTS.key?(item_data.id)
          _type_sym, _type_name, icon_file = BloodboundCatalysts::CATALYSTS[item_data.id]
          path = "Graphics/Multiplayer/#{icon_file}"
          return path if pbResolveBitmap(path)
        end
        bloodbound_icon_original(item)
      end
    end
  end
end

#===============================================================================
# Battle Hook - Grant type immunity when catalyst is held
#===============================================================================
# Hooks into pbCalcTypeMod to check for Bloodbound Catalysts.
# If the defending Pokemon is holding the matching catalyst,
# the move type becomes completely ineffective (0 damage).
#===============================================================================
if defined?(PokeBattle_Move)
  class PokeBattle_Move
    alias bloodbound_pbCalcTypeMod pbCalcTypeMod

    def pbCalcTypeMod(moveType, user, target)
      # Check if target is holding a Bloodbound Catalyst for this move type
      if moveType && target && BloodboundCatalysts.holder_immune?(target, moveType)
        return Effectiveness::INEFFECTIVE
      end
      bloodbound_pbCalcTypeMod(moveType, user, target)
    end
  end
end

#===============================================================================
# Debug
#===============================================================================
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("BLOODBOUND", "=" * 60)
  MultiplayerDebug.info("BLOODBOUND", "009_BloodboundCatalysts.rb loaded")
  MultiplayerDebug.info("BLOODBOUND", "Registration handled by 015_Items/001_ItemRegistry.rb")
  MultiplayerDebug.info("BLOODBOUND", "Battle immunity hook installed")
  MultiplayerDebug.info("BLOODBOUND", "=" * 60)
end
