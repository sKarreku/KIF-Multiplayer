#===============================================================================
# MODULE: Family/Subfamily System - Testing Commands
#===============================================================================
# Chat commands for testing the family system and abilities.
#
# Commands:
#   /set <partyIndex> shiny            - Force a Pokemon to be shiny
#   /set <partyIndex> <familyName>     - Assign a specific family to a Pokemon
#   /set <partyIndex> <subfamilyName>  - Assign a specific subfamily to a Pokemon
#   /forceallshiny on|off              - Force all generated Pokemon to be shiny
#   /forcefamily on|off                - Force 100% family assignment rate
#   /ability <partyIndex> <abilityName> - Set any ability on a party Pokemon
#   /ability2 <partyIndex> <abilityName> - Set second ability on a party Pokemon
#   /move <partyIndex> <moveName>      - Teach any move to a party Pokemon
#   /clearability2 <partyIndex>        - Clear second ability from a party Pokemon
#
# Examples:
#   /set 0 shiny         → Makes first party Pokemon shiny
#   /set 1 Infernum      → Assigns Infernum family to second Pokemon (random subfamily)
#   /ability 0 regenerator → Sets first Pokemon's ability to Regenerator
#   /ability2 0 intimidate → Sets first Pokemon's second ability to Intimidate
#   /move 0 earthquake   → Teaches Earthquake to first Pokemon
#   /forceallshiny on    → All wild Pokemon will be shiny
#   /forcefamily on      → All shinies will get family
#===============================================================================

# TESTING COMMANDS ENABLED
FAMILY_TESTING_COMMANDS_ENABLED = false

# Extend ChatCommands to add family testing commands
module ChatCommands
  class << self
    # Save original parse method
    alias family_original_parse parse

    # Override parse to add family commands
    def parse(text)
      # Check if testing commands are enabled
      return family_original_parse(text) unless FAMILY_TESTING_COMMANDS_ENABLED

      case text
      # Force all shiny toggle
      when /^\/forceallshiny\s+(on|off)$/i
        { type: :force_all_shiny, value: ($1.downcase == "on") }

      # Force family assignment toggle
      when /^\/forcefamily\s+(on|off)$/i
        { type: :force_family_assignment, value: ($1.downcase == "on") }

      # Set Pokemon shiny: /set 0 shiny
      when /^\/set\s+(\d+)\s+shiny$/i
        { type: :set_pokemon_shiny, party_index: $1.to_i }

      # Set Pokemon family: /set 0 Primordium, /set 1 Infernum, etc.
      when /^\/set\s+(\d+)\s+(\w+)$/i
        { type: :set_pokemon_family, party_index: $1.to_i, family_name: $2 }

      # Set ability: /ability 0 regenerator
      when /^\/ability\s+(\d+)\s+(.+)$/i
        { type: :set_ability, party_index: $1.to_i, ability_name: $2.strip }

      # Set second ability: /ability2 0 intimidate
      when /^\/ability2\s+(\d+)\s+(.+)$/i
        { type: :set_ability2, party_index: $1.to_i, ability_name: $2.strip }

      # Clear second ability: /clearability2 0
      when /^\/clearability2\s+(\d+)$/i
        { type: :clear_ability2, party_index: $1.to_i }

      # Teach move: /move 0 earthquake
      when /^\/move\s+(\d+)\s+(.+)$/i
        { type: :teach_move, party_index: $1.to_i, move_name: $2.strip }

      else
        # Fall back to original parse
        family_original_parse(text)
      end
    end
  end
end

# Extend ChatNetwork to handle family commands
module ChatNetwork
  class << self
    # Save original send_command method
    alias family_original_send_command send_command

    # Override send_command to handle family commands
    def send_command(cmd)
      # Check if testing commands are enabled
      unless FAMILY_TESTING_COMMANDS_ENABLED
        family_original_send_command(cmd)
        return
      end

      case cmd[:type]
      when :force_all_shiny
        handle_force_all_shiny(cmd[:value])
      when :force_family_assignment
        handle_force_family_assignment(cmd[:value])
      when :set_pokemon_shiny
        handle_set_pokemon_shiny(cmd[:party_index])
      when :set_pokemon_family
        handle_set_pokemon_family(cmd[:party_index], cmd[:family_name])
      when :set_ability
        handle_set_ability(cmd[:party_index], cmd[:ability_name])
      when :set_ability2
        handle_set_ability2(cmd[:party_index], cmd[:ability_name])
      when :clear_ability2
        handle_clear_ability2(cmd[:party_index])
      when :teach_move
        handle_teach_move(cmd[:party_index], cmd[:move_name])
      else
        # Fall back to original handler
        family_original_send_command(cmd)
      end
    end

    #---------------------------------------------------------------------------
    # Command Handlers
    #---------------------------------------------------------------------------

    # Toggle force all shiny mode
    def handle_force_all_shiny(enabled)
      if enabled
        # Enable force shiny mode (use global variable, not game switch)
        $FORCE_ALL_SHINY_TESTING = true

        ChatMessages.add_message("Global", "SYSTEM", "System", "Force All Shiny: ENABLED")
        ChatMessages.add_message("Global", "SYSTEM", "System", "All wild Pokemon will be shiny")

        if defined?(MultiplayerDebug)
          #MultiplayerDebug.info("FAMILY-CMD", "Force all shiny: ENABLED")
        end
      else
        # Disable force shiny mode
        $FORCE_ALL_SHINY_TESTING = false

        ChatMessages.add_message("Global", "SYSTEM", "System", "Force All Shiny: DISABLED")

        if defined?(MultiplayerDebug)
          #MultiplayerDebug.info("FAMILY-CMD", "Force all shiny: DISABLED")
        end
      end
    end

    # Toggle force family assignment mode
    def handle_force_family_assignment(enabled)
      # Modify the constant directly (Ruby allows this)
      PokemonFamilyConfig.const_set(:FORCE_FAMILY_ASSIGNMENT, enabled)

      if enabled
        ChatMessages.add_message("Global", "SYSTEM", "System", "Force Family Assignment: ENABLED")
        ChatMessages.add_message("Global", "SYSTEM", "System", "All shinies will get a family (100% rate)")

        if defined?(MultiplayerDebug)
          #MultiplayerDebug.info("FAMILY-CMD", "Force family assignment: ENABLED")
        end
      else
        ChatMessages.add_message("Global", "SYSTEM", "System", "Force Family Assignment: DISABLED")
        ChatMessages.add_message("Global", "SYSTEM", "System", "Back to 1% chance")

        if defined?(MultiplayerDebug)
          #MultiplayerDebug.info("FAMILY-CMD", "Force family assignment: DISABLED")
        end
      end
    end

    # Set a specific Pokemon to be shiny
    def handle_set_pokemon_shiny(party_index)
      unless $Trainer && $Trainer.party
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No party available")
        return
      end

      if party_index < 0 || party_index >= $Trainer.party.length
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Invalid party index #{party_index} (0-#{$Trainer.party.length-1})")
        return
      end

      pkmn = $Trainer.party[party_index]
      unless pkmn
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No Pokemon at index #{party_index}")
        return
      end

      # Make shiny
      pkmn.shiny = true

      ChatMessages.add_message("Global", "SYSTEM", "System", "#{pkmn.name} (index #{party_index}) is now SHINY")

      if defined?(MultiplayerDebug)
        #MultiplayerDebug.info("FAMILY-CMD", "Set #{pkmn.name} (index #{party_index}) to shiny")
      end
    end

    # Set a specific Pokemon to a specific family or subfamily
    def handle_set_pokemon_family(party_index, name)
      # Check if setting talent (boosted ability)
      if name.match?(/^(Panmorphosis|Veilbreaker|Voidborne|Vitalrebirth|Immovable|Indomitable|Cosmicblessing|Mindshatter)$/i)
        handle_set_pokemon_talent(party_index, name)
        return
      end

      unless $Trainer && $Trainer.party
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No party available")
        return
      end

      if party_index < 0 || party_index >= $Trainer.party.length
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Invalid party index #{party_index} (0-#{$Trainer.party.length-1})")
        return
      end

      pkmn = $Trainer.party[party_index]
      unless pkmn
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No Pokemon at index #{party_index}")
        return
      end

      # First, try to find subfamily by name (case-insensitive)
      subfamily_global_id = nil
      PokemonFamilyConfig::SUBFAMILIES.each do |id, data|
        if data[:name].downcase == name.downcase
          subfamily_global_id = id
          break
        end
      end

      if subfamily_global_id
        # Found subfamily - assign it directly
        family_id = subfamily_global_id / 4
        local_subfamily = subfamily_global_id % 4

        pkmn.family = family_id
        pkmn.subfamily = local_subfamily
        pkmn.family_assigned_at = Time.now.to_i

        # Make sure it's shiny (required for family Pokemon)
        pkmn.shiny = true unless pkmn.shiny?

        subfamily_name = PokemonFamilyConfig::SUBFAMILIES[subfamily_global_id][:name]
        family_name = PokemonFamilyConfig::FAMILIES[family_id][:name]
        full_name = "#{family_name} #{subfamily_name}"

        ChatMessages.add_message("Global", "SYSTEM", "System", "#{pkmn.name} (index #{party_index}) → #{full_name}")

        if defined?(MultiplayerDebug)
          #MultiplayerDebug.info("FAMILY-CMD", "Set #{pkmn.name} to subfamily #{full_name}")
        end
        return
      end

      # If not found as subfamily, try to find family by name (case-insensitive)
      family_id = nil
      PokemonFamilyConfig::FAMILIES.each do |id, data|
        if data[:name].downcase == name.downcase
          family_id = id
          break
        end
      end

      unless family_id
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Unknown family/subfamily '#{name}'")
        ChatMessages.add_message("Global", "SYSTEM", "System", "Valid families: Primordium, Vacuum, Astrum, Silva, Machina, Humanitas, Aetheris, Infernum")
        ChatMessages.add_message("Global", "SYSTEM", "System", "Valid subfamilies: Genesis, Cataclysmus, Quantum, Nullus, etc. (32 total)")
        return
      end

      # Assign family (use personalID for deterministic subfamily selection)
      pkmn.family = family_id
      pkmn.subfamily = (pkmn.personalID >> 16) % 4  # Deterministic subfamily
      pkmn.family_assigned_at = Time.now.to_i

      # Make sure it's shiny (required for family Pokemon)
      pkmn.shiny = true unless pkmn.shiny?

      subfamily_name = PokemonFamilyConfig::SUBFAMILIES[family_id * 4 + pkmn.subfamily][:name]
      full_name = "#{PokemonFamilyConfig::FAMILIES[family_id][:name]} #{subfamily_name}"

      ChatMessages.add_message("Global", "SYSTEM", "System", "#{pkmn.name} (index #{party_index}) → #{full_name}")

      if defined?(MultiplayerDebug)
        #MultiplayerDebug.info("FAMILY-CMD", "Set #{pkmn.name} to family #{full_name}")
      end
    end

    # Set party Pokemon's talent/ability
    def handle_set_pokemon_talent(party_index, talent_name)
      unless $Trainer && $Trainer.party
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No party available")
        return
      end

      if party_index < 0 || party_index >= $Trainer.party.length
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Invalid party index #{party_index} (0-#{$Trainer.party.length-1})")
        return
      end

      pkmn = $Trainer.party[party_index]
      unless pkmn
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No Pokemon at index #{party_index}")
        return
      end

      # Convert talent name to symbol (uppercase)
      talent_symbol = talent_name.upcase.to_sym

      # Verify talent exists
      unless GameData::Ability.exists?(talent_symbol)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Unknown talent '#{talent_name}'")
        return
      end

      # Set Pokemon's ability directly (bypasses family system)
      pkmn.ability = talent_symbol

      ability_obj = GameData::Ability.get(talent_symbol)
      ChatMessages.add_message("Global", "SYSTEM", "System", "#{pkmn.name} (index #{party_index}) talent set to #{ability_obj.name}")
    end

    #---------------------------------------------------------------------------
    # Ability and Move Testing Commands
    #---------------------------------------------------------------------------

    # Set primary ability: /ability 0 regenerator
    def handle_set_ability(party_index, ability_name)
      unless $Trainer && $Trainer.party
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No party available")
        return
      end

      if party_index < 0 || party_index >= $Trainer.party.length
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Invalid party index #{party_index} (0-#{$Trainer.party.length-1})")
        return
      end

      pkmn = $Trainer.party[party_index]
      unless pkmn
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No Pokemon at index #{party_index}")
        return
      end

      # Convert ability name to symbol (handle spaces with underscores)
      ability_str = ability_name.gsub(/\s+/, '').upcase
      ability_symbol = ability_str.to_sym

      # Verify ability exists
      unless GameData::Ability.exists?(ability_symbol)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Unknown ability '#{ability_name}'")
        ChatMessages.add_message("Global", "SYSTEM", "System", "Try without spaces, e.g., /ability 0 naturalcure")
        return
      end

      # Set Pokemon's ability
      pkmn.ability = ability_symbol

      ability_obj = GameData::Ability.get(ability_symbol)
      ChatMessages.add_message("Global", "SYSTEM", "System", "#{pkmn.name} ability set to #{ability_obj.name}")
    end

    # Set second ability: /ability2 0 intimidate
    def handle_set_ability2(party_index, ability_name)
      unless $Trainer && $Trainer.party
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No party available")
        return
      end

      if party_index < 0 || party_index >= $Trainer.party.length
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Invalid party index #{party_index} (0-#{$Trainer.party.length-1})")
        return
      end

      pkmn = $Trainer.party[party_index]
      unless pkmn
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No Pokemon at index #{party_index}")
        return
      end

      # Convert ability name to symbol (handle spaces with underscores)
      ability_str = ability_name.gsub(/\s+/, '').upcase
      ability_symbol = ability_str.to_sym

      # Verify ability exists
      unless GameData::Ability.exists?(ability_symbol)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Unknown ability '#{ability_name}'")
        ChatMessages.add_message("Global", "SYSTEM", "System", "Try without spaces, e.g., /ability2 0 intimidate")
        return
      end

      # Set Pokemon's second ability using ability2_id
      if pkmn.respond_to?(:ability2_id=)
        pkmn.ability2_id = ability_symbol
      else
        # Fallback: use instance variable directly
        pkmn.instance_variable_set(:@ability2_id, ability_symbol)
      end

      # Ensure the Pokemon is treated as a family Pokemon for ability2 to work
      # If not already a family Pokemon, assign a family
      unless pkmn.respond_to?(:has_family?) && pkmn.has_family?
        pkmn.shiny = true unless pkmn.shiny?
        if defined?(PokemonFamilyConfig)
          pkmn.family = 0  # Primordium
          pkmn.subfamily = 0
          pkmn.family_assigned_at = Time.now.to_i
          ChatMessages.add_message("Global", "SYSTEM", "System", "Auto-assigned family to enable ability2")
        end
      end

      ability_obj = GameData::Ability.get(ability_symbol)
      ChatMessages.add_message("Global", "SYSTEM", "System", "#{pkmn.name} ability2 set to #{ability_obj.name}")
      ChatMessages.add_message("Global", "SYSTEM", "System", "Current abilities: #{pkmn.ability&.name || 'None'} + #{ability_obj.name}")
    end

    # Clear second ability: /clearability2 0
    def handle_clear_ability2(party_index)
      unless $Trainer && $Trainer.party
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No party available")
        return
      end

      if party_index < 0 || party_index >= $Trainer.party.length
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Invalid party index #{party_index} (0-#{$Trainer.party.length-1})")
        return
      end

      pkmn = $Trainer.party[party_index]
      unless pkmn
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No Pokemon at index #{party_index}")
        return
      end

      # Clear ability2
      if pkmn.respond_to?(:ability2_id=)
        pkmn.ability2_id = nil
      else
        pkmn.instance_variable_set(:@ability2_id, nil)
      end

      ChatMessages.add_message("Global", "SYSTEM", "System", "#{pkmn.name} ability2 cleared")
    end

    # Teach move: /move 0 earthquake
    def handle_teach_move(party_index, move_name)
      unless $Trainer && $Trainer.party
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No party available")
        return
      end

      if party_index < 0 || party_index >= $Trainer.party.length
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Invalid party index #{party_index} (0-#{$Trainer.party.length-1})")
        return
      end

      pkmn = $Trainer.party[party_index]
      unless pkmn
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No Pokemon at index #{party_index}")
        return
      end

      # Convert move name to symbol (handle spaces)
      move_str = move_name.gsub(/\s+/, '').upcase
      move_symbol = move_str.to_sym

      # Verify move exists
      unless GameData::Move.exists?(move_symbol)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Unknown move '#{move_name}'")
        ChatMessages.add_message("Global", "SYSTEM", "System", "Try without spaces, e.g., /move 0 shadowball")
        return
      end

      # Find empty move slot or replace last move
      move_slot = nil
      pkmn.moves.each_with_index do |m, i|
        if m.nil? || m.id == :NONE
          move_slot = i
          break
        end
      end

      if move_slot
        # Use empty slot
        pkmn.moves[move_slot] = Pokemon::Move.new(move_symbol)
      else
        # Replace last move (slot 3)
        old_move = pkmn.moves[3]&.name || "empty slot"
        pkmn.moves[3] = Pokemon::Move.new(move_symbol)
        ChatMessages.add_message("Global", "SYSTEM", "System", "(Replaced #{old_move})")
      end

      move_obj = GameData::Move.get(move_symbol)
      ChatMessages.add_message("Global", "SYSTEM", "System", "#{pkmn.name} learned #{move_obj.name}!")

      # Show current moveset
      moveset = pkmn.moves.map { |m| m&.name || "-" }.join(", ")
      ChatMessages.add_message("Global", "SYSTEM", "System", "Moves: #{moveset}")
    end
  end
end

# Hook Pokemon generation to force shiny if testing mode enabled
if FAMILY_TESTING_COMMANDS_ENABLED
  class Pokemon
    alias family_test_force_shiny_initialize initialize
    def initialize(*args)
      family_test_force_shiny_initialize(*args)

      # Force shiny if testing mode enabled (use global variable instead of game switch)
      if $FORCE_ALL_SHINY_TESTING
        @shiny = true
        @natural_shiny = false

        if defined?(MultiplayerDebug)
          #MultiplayerDebug.info("FAMILY-TEST", "Forced #{self.name} to be shiny (testing mode)")
        end
      end
    end
  end
end

# Module loaded successfully
if defined?(MultiplayerDebug)
  #MultiplayerDebug.info("FAMILY-CMD", "=" * 60)
  #MultiplayerDebug.info("FAMILY-CMD", "107_Family_Testing_Commands.rb loaded successfully")
  #MultiplayerDebug.info("FAMILY-CMD", "Chat commands registered:")
  #MultiplayerDebug.info("FAMILY-CMD", "  /forceallshiny on|off       - Force all Pokemon to be shiny")
  #MultiplayerDebug.info("FAMILY-CMD", "  /forcefamily on|off         - Force 100% family assignment")
  #MultiplayerDebug.info("FAMILY-CMD", "  /set <index> shiny          - Make party Pokemon shiny")
  #MultiplayerDebug.info("FAMILY-CMD", "  /set <index> <family>       - Assign family to party Pokemon")
  #MultiplayerDebug.info("FAMILY-CMD", "  /set <index> <subfamily>    - Assign subfamily to party Pokemon")
  #MultiplayerDebug.info("FAMILY-CMD", "Examples:")
  #MultiplayerDebug.info("FAMILY-CMD", "  /set 0 shiny                - Make first Pokemon shiny")
  #MultiplayerDebug.info("FAMILY-CMD", "  /set 1 Infernum             - Give second Pokemon Infernum family (random subfamily)")
  #MultiplayerDebug.info("FAMILY-CMD", "  /set 0 Quantum              - Give first Pokemon Quantum subfamily (Machina family)")
  #MultiplayerDebug.info("FAMILY-CMD", "=" * 60)
end
