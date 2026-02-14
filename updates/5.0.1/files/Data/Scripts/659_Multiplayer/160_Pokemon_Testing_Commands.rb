#===============================================================================
# MODULE: Pokemon Testing Commands (Hatch & Evolve)
#===============================================================================
# Chat commands for testing hatching and evolution.
#
# Commands:
#   /hatch <index>    - Force-hatch an egg in your party
#   /evolve <index>   - Force-evolve a Pokemon in your party
#   /unkillable <index> - Toggle unkillable on a party Pokemon (survives at 1 HP)
#   /give bc <type>   - Give a Bloodbound Catalyst for that type
#
# Examples:
#   /hatch 0          - Hatch the egg in slot 0
#   /hatch 2          - Hatch the egg in slot 2
#   /evolve 0         - Evolve the Pokemon in slot 0
#   /evolve 3         - Evolve the Pokemon in slot 3
#   /give bc fire     - Give Bloodbound Catalyst (Fire)
#   /give bc water    - Give Bloodbound Catalyst (Water)
#===============================================================================

POKEMON_TESTING_COMMANDS_ENABLED = false

# Extend ChatCommands to add hatch/evolve commands
module ChatCommands
  class << self
    alias pokemon_test_original_parse parse

    def parse(text)
      return pokemon_test_original_parse(text) unless POKEMON_TESTING_COMMANDS_ENABLED

      case text
      when /^\/hatch\s+(\d+)$/i
        { type: :hatch_pokemon, party_index: $1.to_i }
      when /^\/evolve\s+(\d+)$/i
        { type: :evolve_pokemon, party_index: $1.to_i }
      when /^\/unkillable\s+(\d+)$/i
        { type: :unkillable, party_index: $1.to_i }
      when /^\/give\s+bc\s+(\w+)$/i
        { type: :give_bloodbound, element: $1.downcase }
      else
        pokemon_test_original_parse(text)
      end
    end
  end
end

# Extend ChatNetwork to handle hatch/evolve commands
module ChatNetwork
  class << self
    alias pokemon_test_original_send_command send_command

    def send_command(cmd)
      unless POKEMON_TESTING_COMMANDS_ENABLED
        pokemon_test_original_send_command(cmd)
        return
      end

      case cmd[:type]
      when :hatch_pokemon
        handle_hatch_pokemon(cmd[:party_index])
      when :evolve_pokemon
        handle_evolve_pokemon(cmd[:party_index])
      when :unkillable
        handle_unkillable(cmd[:party_index])
      when :give_bloodbound
        handle_give_bloodbound(cmd[:element])
      else
        pokemon_test_original_send_command(cmd)
      end
    end

    #---------------------------------------------------------------------------
    # Command Handlers
    #---------------------------------------------------------------------------

    def handle_hatch_pokemon(index)
      unless $Trainer && $Trainer.party
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No party available")
        return
      end

      if index < 0 || index >= $Trainer.party.length
        ChatMessages.add_message("Global", "SYSTEM", "System",
          "Error: Invalid index #{index}. Party size: #{$Trainer.party.length} (0-#{$Trainer.party.length - 1})")
        return
      end

      pkmn = $Trainer.party[index]
      unless pkmn.egg?
        ChatMessages.add_message("Global", "SYSTEM", "System",
          "Error: Party slot #{index} (#{pkmn.name}) is not an egg")
        return
      end

      ChatMessages.add_message("Global", "SYSTEM", "System", "Hatching egg in slot #{index}...")
      # Force steps to 0 and trigger the normal hatch flow
      pkmn.steps_to_hatch = 0
      pbHatch(pkmn, index)
    end

    def handle_evolve_pokemon(index)
      unless $Trainer && $Trainer.party
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No party available")
        return
      end

      if index < 0 || index >= $Trainer.party.length
        ChatMessages.add_message("Global", "SYSTEM", "System",
          "Error: Invalid index #{index}. Party size: #{$Trainer.party.length} (0-#{$Trainer.party.length - 1})")
        return
      end

      pkmn = $Trainer.party[index]
      if pkmn.egg?
        ChatMessages.add_message("Global", "SYSTEM", "System",
          "Error: Party slot #{index} is an egg. Use /hatch instead")
        return
      end

      # Get all possible evolutions for this species
      evolutions = pkmn.species_data.get_evolutions(true)
      if evolutions.nil? || evolutions.empty?
        ChatMessages.add_message("Global", "SYSTEM", "System",
          "Error: #{pkmn.name} (#{pkmn.speciesName}) has no evolutions")
        return
      end

      # Use the first available evolution
      new_species = evolutions[0][0]
      new_species_name = GameData::Species.get(new_species).name

      ChatMessages.add_message("Global", "SYSTEM", "System",
        "Evolving #{pkmn.name} into #{new_species_name}...")

      # Trigger the evolution scene (same flow as post-battle evolution)
      pbFadeOutInWithMusic {
        evo = PokemonEvolutionScene.new
        evo.pbStartScreen(pkmn, new_species)
        evo.pbEvolution(false)  # false = cannot cancel
        evo.pbEndScreen
      }
    end

    def handle_unkillable(index)
      unless $Trainer && $Trainer.party
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No party available")
        return
      end

      if index < 0 || index >= $Trainer.party.length
        ChatMessages.add_message("Global", "SYSTEM", "System",
          "Error: Invalid index #{index}. Party size: #{$Trainer.party.length} (0-#{$Trainer.party.length - 1})")
        return
      end

      pkmn = $Trainer.party[index]
      if pkmn.egg?
        ChatMessages.add_message("Global", "SYSTEM", "System",
          "Error: Party slot #{index} is an egg")
        return
      end

      # Toggle the flag
      pkmn.unkillable = !pkmn.unkillable
      state = pkmn.unkillable ? "ON" : "OFF"
      ChatMessages.add_message("Global", "SYSTEM", "System",
        "#{pkmn.name} unkillable: #{state}")
    end

    def handle_give_bloodbound(element)
      unless defined?(BloodboundCatalysts)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: BloodboundCatalysts module not loaded")
        return
      end

      # Build lookup: lowercase name => item symbol
      match = nil
      BloodboundCatalysts::CATALYSTS.each do |item_id, (type_sym, type_name, _icon)|
        if type_name.downcase == element
          match = { item_id: item_id, type_name: type_name }
          break
        end
      end

      unless match
        types = BloodboundCatalysts::CATALYSTS.values.map { |_, name, _| name.downcase }.join(", ")
        ChatMessages.add_message("Global", "SYSTEM", "System",
          "Unknown type '#{element}'. Available: #{types}")
        return
      end

      # Add to bag
      if $PokemonBag.pbStoreItem(match[:item_id])
        ChatMessages.add_message("Global", "SYSTEM", "System",
          "Gave Bloodbound Catalyst (#{match[:type_name]})")
      else
        ChatMessages.add_message("Global", "SYSTEM", "System",
          "Error: Bag is full, could not add item")
      end
    end
  end
end

#===============================================================================
# Unkillable Flag on Pokemon
#===============================================================================
class Pokemon
  attr_accessor :unkillable

  alias unkillable_original_initialize initialize

  def initialize(*args)
    unkillable_original_initialize(*args)
    @unkillable = false
  end
end

#===============================================================================
# Battle Hook: Prevent unkillable Pokemon from fainting
#===============================================================================
class PokeBattle_Battler
  alias unkillable_pbReduceHP pbReduceHP

  def pbReduceHP(amt, anim = true, registerDamage = true, anyAnim = true)
    # If this battler's Pokemon is flagged unkillable, clamp so HP never drops below 1
    if @pokemon&.unkillable
      amt = amt.round
      max_loss = @hp - 1
      amt = max_loss if amt > max_loss
      amt = 0 if amt < 0
    end
    unkillable_pbReduceHP(amt, anim, registerDamage, anyAnim)
  end
end
