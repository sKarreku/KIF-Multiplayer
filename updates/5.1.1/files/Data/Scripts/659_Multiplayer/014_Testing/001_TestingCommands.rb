# =============================================================================
# Testing Commands (Debug Mode Only)
# =============================================================================
# Unified test command handler for all chat-based debug commands.
#
# Source files merged:
#   063_Item_Testing_Commands.rb     → /give, /listballs, /candy
#   107_Family_Testing_Commands.rb   → /set, /ability, /move, /ability2, /clearability2
#   156_Event_Testing_Commands.rb    → /createevent, /endevent, /checkevent, etc.
#   160_Pokemon_Testing_Commands.rb  → /hatch, /evolve, /unkillable, /give bc
# =============================================================================

ITEM_TESTING_COMMANDS_ENABLED    = false
FAMILY_TESTING_COMMANDS_ENABLED  = false
EVENT_TESTING_COMMANDS_ENABLED   = false
POKEMON_TESTING_COMMANDS_ENABLED = false

# =============================================================================
# ChatCommands - Unified parse alias
# =============================================================================
module ChatCommands
  class << self
    alias testing_commands_original_parse parse

    def parse(text)
      # --- Item commands (from 063) ---
      if ITEM_TESTING_COMMANDS_ENABLED
        case text
        when /^\/give\s+(\w+)\s+(\d+)$/i
          return { type: :give_item, item_name: $1.strip, quantity: $2.to_i }
        when /^\/listballs$/i
          return { type: :list_balls }
        when /^\/candy$/i
          return { type: :give_candy }
        when /^\/give\s+resonator(?:\s+(\d+))?$/i
          return { type: :give_resonator, quantity: ($1 ? $1.to_i : 1) }
        when /^\/give\s+core(?:\s+(\d+))?$/i
          return { type: :give_core, quantity: ($1 ? $1.to_i : 1) }
        end
      end

      # --- Family commands (from 107) ---
      if FAMILY_TESTING_COMMANDS_ENABLED
        case text
        when /^\/forceallshiny\s+(on|off)$/i
          return { type: :force_all_shiny, value: ($1.downcase == "on") }
        when /^\/forcefamily\s+(on|off)$/i
          return { type: :force_family_assignment, value: ($1.downcase == "on") }
        when /^\/set\s+(\d+)\s+shiny$/i
          return { type: :set_pokemon_shiny, party_index: $1.to_i }
        when /^\/set\s+(\d+)\s+(\w+)$/i
          return { type: :set_pokemon_family, party_index: $1.to_i, family_name: $2 }
        when /^\/ability\s+(\d+)\s+(.+)$/i
          return { type: :set_ability, party_index: $1.to_i, ability_name: $2.strip }
        when /^\/ability2\s+(\d+)\s+(.+)$/i
          return { type: :set_ability2, party_index: $1.to_i, ability_name: $2.strip }
        when /^\/clearability2\s+(\d+)$/i
          return { type: :clear_ability2, party_index: $1.to_i }
        when /^\/move\s+(\d+)\s+(.+)$/i
          return { type: :teach_move, party_index: $1.to_i, move_name: $2.strip }
        end
      end

      # --- Event commands (from 156) ---
      if EVENT_TESTING_COMMANDS_ENABLED
        case text
        when /^\/createevent\s+(shiny|family|boss)$/i
          return { type: :create_event, event_type: $1.downcase }
        when /^\/endevent$/i
          return { type: :end_event }
        when /^\/checkevent$/i
          return { type: :check_event }
        when /^\/checkshinyrate$/i
          return { type: :check_shiny_rate }
        when /^\/eventhelp$/i
          return { type: :event_help }
        when /^\/modifyevent\s+(reward)(\d)\s+(\w+)$/i
          return { type: :modify_event_reward, slot: $2.to_i, name: $3.downcase }
        when /^\/modifyevent\s+(challenge)(\d)\s+(\w+)$/i
          return { type: :modify_event_challenge, slot: $2.to_i, name: $3.downcase }
        when /^\/modifyevent\s+map\s+(global|currentmap)$/i
          return { type: :modify_event_map, scope: $1.downcase }
        when /^\/giveeventrewards$/i
          return { type: :give_event_rewards }
        when /^\/listrewards$/i
          return { type: :list_rewards }
        when /^\/listchallenges$/i
          return { type: :list_challenges }
        end
      end

      # --- Pokemon commands (from 160) ---
      if POKEMON_TESTING_COMMANDS_ENABLED
        case text
        when /^\/hatch\s+(\d+)$/i
          return { type: :hatch_pokemon, party_index: $1.to_i }
        when /^\/evolve\s+(\d+)$/i
          return { type: :evolve_pokemon, party_index: $1.to_i }
        when /^\/unkillable\s+(\d+)$/i
          return { type: :unkillable, party_index: $1.to_i }
        when /^\/give\s+bc\s+(\w+)$/i
          return { type: :give_bloodbound, element: $1.downcase }
        when /^\/unboss\s+(\d+)$/i
          return { type: :unboss, party_index: $1.to_i }
        end
      end

      # Fall through to original
      testing_commands_original_parse(text)
    end
  end
end

# =============================================================================
# ChatNetwork - Unified send_command alias
# =============================================================================
module ChatNetwork
  class << self
    alias testing_commands_original_send_command send_command

    def send_command(cmd)
      # --- Item commands (from 063) ---
      if ITEM_TESTING_COMMANDS_ENABLED
        case cmd[:type]
        when :give_item
          return handle_give_item(cmd[:item_name], cmd[:quantity])
        when :list_balls
          return handle_list_balls
        when :give_candy
          return handle_give_candy
        when :give_resonator
          return handle_give_resonator(cmd[:quantity])
        when :give_core
          return handle_give_core(cmd[:quantity])
        end
      end

      # --- Family commands (from 107) ---
      if FAMILY_TESTING_COMMANDS_ENABLED
        case cmd[:type]
        when :force_all_shiny
          return handle_force_all_shiny(cmd[:value])
        when :force_family_assignment
          return handle_force_family_assignment(cmd[:value])
        when :set_pokemon_shiny
          return handle_set_pokemon_shiny(cmd[:party_index])
        when :set_pokemon_family
          return handle_set_pokemon_family(cmd[:party_index], cmd[:family_name])
        when :set_ability
          return handle_set_ability(cmd[:party_index], cmd[:ability_name])
        when :set_ability2
          return handle_set_ability2(cmd[:party_index], cmd[:ability_name])
        when :clear_ability2
          return handle_clear_ability2(cmd[:party_index])
        when :teach_move
          return handle_teach_move(cmd[:party_index], cmd[:move_name])
        end
      end

      # --- Event commands (from 156) ---
      if EVENT_TESTING_COMMANDS_ENABLED
        case cmd[:type]
        when :create_event
          return handle_create_event(cmd[:event_type])
        when :end_event
          return handle_end_event
        when :check_event
          return handle_check_event
        when :check_shiny_rate
          return handle_check_shiny_rate
        when :event_help
          return handle_event_help
        when :modify_event_reward
          return handle_modify_event_reward(cmd[:slot], cmd[:name])
        when :modify_event_challenge
          return handle_modify_event_challenge(cmd[:slot], cmd[:name])
        when :modify_event_map
          return handle_modify_event_map(cmd[:scope])
        when :give_event_rewards
          return handle_give_event_rewards
        when :list_rewards
          return handle_list_rewards
        when :list_challenges
          return handle_list_challenges
        end
      end

      # --- Pokemon commands (from 160) ---
      if POKEMON_TESTING_COMMANDS_ENABLED
        case cmd[:type]
        when :hatch_pokemon
          return handle_hatch_pokemon(cmd[:party_index])
        when :evolve_pokemon
          return handle_evolve_pokemon(cmd[:party_index])
        when :unkillable
          return handle_unkillable(cmd[:party_index])
        when :give_bloodbound
          return handle_give_bloodbound(cmd[:element])
        when :unboss
          return handle_unboss(cmd[:party_index])
        end
      end

      # Fall through to original
      testing_commands_original_send_command(cmd)
    end

    #---------------------------------------------------------------------------
    # Item Command Handlers (from 063)
    #---------------------------------------------------------------------------

    def handle_give_item(item_name, quantity)
      if quantity <= 0
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Quantity must be > 0")
        return
      end
      if quantity > 999
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Max quantity is 999")
        return
      end

      item_str = item_name.gsub(/\s+/, '').upcase
      item_symbol = item_str.to_sym

      unless GameData::Item.exists?(item_symbol)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Unknown item '#{item_name}'")
        ChatMessages.add_message("Global", "SYSTEM", "System", "Use /listballs to see valid ball names")
        return
      end

      item_data = GameData::Item.get(item_symbol)
      unless item_data.is_poke_ball?
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Only Poke Balls allowed (got '#{item_data.name}')")
        ChatMessages.add_message("Global", "SYSTEM", "System", "Use /listballs to see valid ball names")
        return
      end

      unless defined?($PokemonBag) && $PokemonBag
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No bag available")
        return
      end

      if $PokemonBag.pbStoreItem(item_symbol, quantity)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Received #{quantity}x #{item_data.name}!")
      else
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Could not add #{item_data.name} to bag (bag full?)")
      end
    end

    def handle_give_candy
      unless defined?($PokemonBag) && $PokemonBag
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No bag available")
        return
      end

      if $PokemonBag.pbStoreItem(:RARECANDY, 100)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Received 100x Rare Candy!")
      else
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Could not add Rare Candy to bag (bag full?)")
      end
    end

    def handle_give_resonator(quantity = 1)
      unless defined?($PokemonBag) && $PokemonBag
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No bag available")
        return
      end

      quantity = [[quantity, 1].max, 999].min

      if $PokemonBag.pbStoreItem(:RESONANCERESONATOR, quantity)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Received #{quantity}x Resonance Resonator!")
      else
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Could not add Resonance Resonator to bag (bag full?)")
      end
    end

    def handle_give_core(quantity = 1)
      unless defined?($PokemonBag) && $PokemonBag
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No bag available")
        return
      end

      quantity = [[quantity, 1].max, 999].min

      if $PokemonBag.pbStoreItem(:RESONANCECORE, quantity)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Received #{quantity}x Resonance Core!")
      else
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Could not add Resonance Core to bag (bag full?)")
      end
    end

    def handle_list_balls
      balls = []
      GameData::Item.each do |item|
        balls << item.id.to_s if item.is_poke_ball?
      end

      if balls.empty?
        ChatMessages.add_message("Global", "SYSTEM", "System", "No Poke Ball items found")
        return
      end

      ChatMessages.add_message("Global", "SYSTEM", "System", "Available balls (/give <name> <qty>):")
      balls.each_slice(6) do |group|
        ChatMessages.add_message("Global", "SYSTEM", "System", group.join(", "))
      end
    end

    #---------------------------------------------------------------------------
    # Family Command Handlers (from 107)
    #---------------------------------------------------------------------------

    def handle_force_all_shiny(enabled)
      if enabled
        $FORCE_ALL_SHINY_TESTING = true
        ChatMessages.add_message("Global", "SYSTEM", "System", "Force All Shiny: ENABLED")
        ChatMessages.add_message("Global", "SYSTEM", "System", "All wild Pokemon will be shiny")
      else
        $FORCE_ALL_SHINY_TESTING = false
        ChatMessages.add_message("Global", "SYSTEM", "System", "Force All Shiny: DISABLED")
      end
    end

    def handle_force_family_assignment(enabled)
      PokemonFamilyConfig.const_set(:FORCE_FAMILY_ASSIGNMENT, enabled)

      if enabled
        ChatMessages.add_message("Global", "SYSTEM", "System", "Force Family Assignment: ENABLED")
        ChatMessages.add_message("Global", "SYSTEM", "System", "All shinies will get a family (100% rate)")
      else
        ChatMessages.add_message("Global", "SYSTEM", "System", "Force Family Assignment: DISABLED")
        ChatMessages.add_message("Global", "SYSTEM", "System", "Back to 1% chance")
      end
    end

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

      pkmn.shiny = true
      ChatMessages.add_message("Global", "SYSTEM", "System", "#{pkmn.name} (index #{party_index}) is now SHINY")
    end

    def handle_set_pokemon_family(party_index, name)
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
        family_id = subfamily_global_id / 4
        local_subfamily = subfamily_global_id % 4

        pkmn.family = family_id
        pkmn.subfamily = local_subfamily
        pkmn.family_assigned_at = Time.now.to_i
        pkmn.shiny = true unless pkmn.shiny?

        subfamily_name = PokemonFamilyConfig::SUBFAMILIES[subfamily_global_id][:name]
        family_name = PokemonFamilyConfig::FAMILIES[family_id][:name]
        full_name = "#{family_name} #{subfamily_name}"

        ChatMessages.add_message("Global", "SYSTEM", "System", "#{pkmn.name} (index #{party_index}) → #{full_name}")
        return
      end

      # If not found as subfamily, try to find family by name
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

      pkmn.family = family_id
      pkmn.subfamily = (pkmn.personalID >> 16) % 4
      pkmn.family_assigned_at = Time.now.to_i
      pkmn.shiny = true unless pkmn.shiny?

      subfamily_name = PokemonFamilyConfig::SUBFAMILIES[family_id * 4 + pkmn.subfamily][:name]
      full_name = "#{PokemonFamilyConfig::FAMILIES[family_id][:name]} #{subfamily_name}"

      ChatMessages.add_message("Global", "SYSTEM", "System", "#{pkmn.name} (index #{party_index}) → #{full_name}")
    end

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

      talent_symbol = talent_name.upcase.to_sym

      unless GameData::Ability.exists?(talent_symbol)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Unknown talent '#{talent_name}'")
        return
      end

      pkmn.ability = talent_symbol

      ability_obj = GameData::Ability.get(talent_symbol)
      ChatMessages.add_message("Global", "SYSTEM", "System", "#{pkmn.name} (index #{party_index}) talent set to #{ability_obj.name}")
    end

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

      ability_str = ability_name.gsub(/\s+/, '').upcase
      ability_symbol = ability_str.to_sym

      unless GameData::Ability.exists?(ability_symbol)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Unknown ability '#{ability_name}'")
        ChatMessages.add_message("Global", "SYSTEM", "System", "Try without spaces, e.g., /ability 0 naturalcure")
        return
      end

      pkmn.ability = ability_symbol

      ability_obj = GameData::Ability.get(ability_symbol)
      ChatMessages.add_message("Global", "SYSTEM", "System", "#{pkmn.name} ability set to #{ability_obj.name}")
    end

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

      ability_str = ability_name.gsub(/\s+/, '').upcase
      ability_symbol = ability_str.to_sym

      unless GameData::Ability.exists?(ability_symbol)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Unknown ability '#{ability_name}'")
        ChatMessages.add_message("Global", "SYSTEM", "System", "Try without spaces, e.g., /ability2 0 intimidate")
        return
      end

      if pkmn.respond_to?(:ability2_id=)
        pkmn.ability2_id = ability_symbol
      else
        pkmn.instance_variable_set(:@ability2_id, ability_symbol)
      end

      unless pkmn.respond_to?(:has_family?) && pkmn.has_family?
        pkmn.shiny = true unless pkmn.shiny?
        if defined?(PokemonFamilyConfig)
          pkmn.family = 0
          pkmn.subfamily = 0
          pkmn.family_assigned_at = Time.now.to_i
          ChatMessages.add_message("Global", "SYSTEM", "System", "Auto-assigned family to enable ability2")
        end
      end

      ability_obj = GameData::Ability.get(ability_symbol)
      ChatMessages.add_message("Global", "SYSTEM", "System", "#{pkmn.name} ability2 set to #{ability_obj.name}")
      ChatMessages.add_message("Global", "SYSTEM", "System", "Current abilities: #{pkmn.ability&.name || 'None'} + #{ability_obj.name}")
    end

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

      if pkmn.respond_to?(:ability2_id=)
        pkmn.ability2_id = nil
      else
        pkmn.instance_variable_set(:@ability2_id, nil)
      end

      ChatMessages.add_message("Global", "SYSTEM", "System", "#{pkmn.name} ability2 cleared")
    end

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

      move_str = move_name.gsub(/\s+/, '').upcase
      move_symbol = move_str.to_sym

      unless GameData::Move.exists?(move_symbol)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Unknown move '#{move_name}'")
        ChatMessages.add_message("Global", "SYSTEM", "System", "Try without spaces, e.g., /move 0 shadowball")
        return
      end

      move_slot = nil
      pkmn.moves.each_with_index do |m, i|
        if m.nil? || m.id == :NONE
          move_slot = i
          break
        end
      end

      if move_slot
        pkmn.moves[move_slot] = Pokemon::Move.new(move_symbol)
      else
        old_move = pkmn.moves[3]&.name || "empty slot"
        pkmn.moves[3] = Pokemon::Move.new(move_symbol)
        ChatMessages.add_message("Global", "SYSTEM", "System", "(Replaced #{old_move})")
      end

      move_obj = GameData::Move.get(move_symbol)
      ChatMessages.add_message("Global", "SYSTEM", "System", "#{pkmn.name} learned #{move_obj.name}!")

      moveset = pkmn.moves.map { |m| m&.name || "-" }.join(", ")
      ChatMessages.add_message("Global", "SYSTEM", "System", "Moves: #{moveset}")
    end

    #---------------------------------------------------------------------------
    # Event Command Handlers (from 156)
    #---------------------------------------------------------------------------

    def handle_create_event(event_type)
      unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Not connected to server")
        return
      end

      MultiplayerClient.send_data("ADMIN_EVENT_CREATE:#{event_type}")
      ChatMessages.add_message("Global", "SYSTEM", "System", "Requesting #{event_type} event creation...")

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("EVENT-CMD", "Sent ADMIN_EVENT_CREATE:#{event_type}")
      end
    end

    def handle_end_event
      unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Not connected to server")
        return
      end

      if defined?(EventSystem)
        events = EventSystem.active_events
        if events.empty?
          ChatMessages.add_message("Global", "SYSTEM", "System", "No active event to end")
          return
        end

        event_id = events.keys.first
        MultiplayerClient.send_data("ADMIN_EVENT_END:#{event_id}")
        ChatMessages.add_message("Global", "SYSTEM", "System", "Requesting event end: #{event_id}")

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("EVENT-CMD", "Sent ADMIN_EVENT_END:#{event_id}")
        end
      else
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: EventSystem not loaded")
      end
    end

    def handle_check_event
      ChatMessages.add_message("Global", "SYSTEM", "System", "=== Event Status ===")

      if defined?(EventSystem)
        events = EventSystem.active_events

        if events.empty?
          ChatMessages.add_message("Global", "SYSTEM", "System", "No active events")
        else
          events.each do |id, event|
            time_left = EventSystem.time_remaining(id)
            mins = time_left / 60
            secs = time_left % 60

            event_type = event[:type] || "unknown"
            ChatMessages.add_message("Global", "SYSTEM", "System", "Event: #{event_type.to_s.upcase}")
            ChatMessages.add_message("Global", "SYSTEM", "System", "  ID: #{id}")
            ChatMessages.add_message("Global", "SYSTEM", "System", "  Time left: #{mins}m #{secs}s")

            challenges = event[:challenge_modifiers] || []
            if challenges.any?
              ChatMessages.add_message("Global", "SYSTEM", "System", "  Challenges: #{challenges.length}")
              challenges.each do |c|
                ChatMessages.add_message("Global", "SYSTEM", "System", "    - #{c}")
              end
            end

            rewards = event[:reward_modifiers] || []
            if rewards.any?
              ChatMessages.add_message("Global", "SYSTEM", "System", "  Rewards: #{rewards.length}")
              rewards.each do |r|
                ChatMessages.add_message("Global", "SYSTEM", "System", "    - #{r}")
              end
            end
          end
        end
      else
        ChatMessages.add_message("Global", "SYSTEM", "System", "EventSystem not loaded")
      end

      ChatMessages.add_message("Global", "SYSTEM", "System", "==================")
    end

    def handle_check_shiny_rate
      ChatMessages.add_message("Global", "SYSTEM", "System", "=== Shiny Rate Check ===")

      base_odds = 65536
      if defined?($PokemonSystem) && $PokemonSystem.respond_to?(:shinyodds)
        base_odds = $PokemonSystem.shinyodds || 65536
      end

      base_rate = base_odds.to_f / 65536.0
      base_percent = (base_rate * 100).round(4)

      ChatMessages.add_message("Global", "SYSTEM", "System", "Base shiny odds: #{base_odds}/65536 (#{base_percent}%)")

      on_event_map = false
      if defined?(EventSystem) && EventSystem.has_active_event?("shiny")
        event = EventSystem.primary_event
        if event
          if event[:map] == "global" || event[:map].to_s == "0"
            on_event_map = true
          elsif defined?($game_map) && $game_map
            event_map = event[:map].to_i rescue 0
            on_event_map = (event_map == 0 || $game_map.map_id == event_map)
          end
        end
      end

      total_multiplier = 1.0
      if defined?(EventSystem) && EventSystem.has_active_event?("shiny")
        ChatMessages.add_message("Global", "SYSTEM", "System", "Shiny event ACTIVE!")
        ChatMessages.add_message("Global", "SYSTEM", "System", "On event map: #{on_event_map ? 'YES' : 'NO'}")

        if on_event_map
          event_mult = EventSystem.get_modifier_multiplier("shiny_multiplier", "shiny")
          if event_mult > 1
            total_multiplier *= event_mult
            ChatMessages.add_message("Global", "SYSTEM", "System", "  Event base: x#{event_mult}")
          end

          ChatMessages.add_message("Global", "SYSTEM", "System", "--- Passive Modifiers ---")
          player_id = get_local_player_id

          if EventSystem.has_reward_modifier?("blessing")
            if defined?(EventRewards) && EventRewards.has_buff?(player_id, :blessing)
              total_multiplier *= 100
              buff = EventRewards.get_buff(player_id, :blessing)
              remaining = buff ? [(buff[:expires_at] - Time.now).to_i, 0].max : 0
              ChatMessages.add_message("Global", "SYSTEM", "System", "  Blessing: x100 ACTIVE (#{remaining}s remaining)")
            else
              ChatMessages.add_message("Global", "SYSTEM", "System", "  Blessing: inactive (enter event map to activate)")
            end
          else
            ChatMessages.add_message("Global", "SYSTEM", "System", "  Blessing: not set on event")
          end

          if EventSystem.has_reward_modifier?("squad_scaling")
            squad_mult = 1
            if defined?(MultiplayerClient)
              squad = MultiplayerClient.squad rescue nil
              if squad && squad[:members]
                squad_mult = [squad[:members].length, 3].min
              end
            end
            total_multiplier *= squad_mult if squad_mult > 1
            ChatMessages.add_message("Global", "SYSTEM", "System", "  Squad Scaling: x#{squad_mult} ACTIVE")
          else
            ChatMessages.add_message("Global", "SYSTEM", "System", "  Squad Scaling: not set on event")
          end

          if defined?(EventRewards) && EventRewards.has_shooting_star_charm?
            total_multiplier *= 1.5
            ChatMessages.add_message("Global", "SYSTEM", "System", "  Shooting Star Charm: x1.5 ACTIVE")
          end

          ChatMessages.add_message("Global", "SYSTEM", "System", "--- End-of-Event Rewards ---")

          if EventSystem.has_reward_modifier?("pity")
            if defined?(EventRewards) && EventRewards.has_buff?(player_id, :pity)
              ChatMessages.add_message("Global", "SYSTEM", "System", "  Pity: READY (next = 100% shiny)")
            else
              ChatMessages.add_message("Global", "SYSTEM", "System", "  Pity: not received (be eligible + /giveeventrewards)")
            end
          else
            ChatMessages.add_message("Global", "SYSTEM", "System", "  Pity: not set on event")
          end

          if EventSystem.has_reward_modifier?("fusion")
            if defined?(EventRewards) && EventRewards.has_buff?(player_id, :fusion_shiny)
              ChatMessages.add_message("Global", "SYSTEM", "System", "  Fusion: READY (next fusion = shiny part)")
            else
              ChatMessages.add_message("Global", "SYSTEM", "System", "  Fusion: not received (be eligible + /giveeventrewards)")
            end
          else
            ChatMessages.add_message("Global", "SYSTEM", "System", "  Fusion: not set on event")
          end

          ChatMessages.add_message("Global", "SYSTEM", "System", "--- Summary ---")
          effective_odds = [base_odds * total_multiplier, 65535].min.to_i
          effective_rate = effective_odds.to_f / 65536.0
          effective_percent = (effective_rate * 100).round(4)

          ChatMessages.add_message("Global", "SYSTEM", "System", "Total multiplier: x#{total_multiplier.round(1)}")
          ChatMessages.add_message("Global", "SYSTEM", "System", "Effective odds: #{effective_odds}/65536 (#{effective_percent}%)")
        else
          ChatMessages.add_message("Global", "SYSTEM", "System", "Not on event map - modifiers don't apply")
        end
      else
        ChatMessages.add_message("Global", "SYSTEM", "System", "No shiny event active")
        ChatMessages.add_message("Global", "SYSTEM", "System", "Effective multiplier: x1")
      end

      ChatMessages.add_message("Global", "SYSTEM", "System", "========================")
    end

    def handle_event_help
      ChatMessages.add_message("Global", "SYSTEM", "System", "=== Event Commands ===")
      ChatMessages.add_message("Global", "SYSTEM", "System", "/createevent <type> - Create event (shiny/family/boss)")
      ChatMessages.add_message("Global", "SYSTEM", "System", "/endevent - End current event")
      ChatMessages.add_message("Global", "SYSTEM", "System", "/checkevent - Show event status")
      ChatMessages.add_message("Global", "SYSTEM", "System", "/checkshinyrate - Show shiny rate")
      ChatMessages.add_message("Global", "SYSTEM", "System", "/modifyevent reward1/2 <name> - Set reward")
      ChatMessages.add_message("Global", "SYSTEM", "System", "/modifyevent challenge1/2/3 <name> - Set challenge")
      ChatMessages.add_message("Global", "SYSTEM", "System", "/modifyevent map global/currentmap - Set scope")
      ChatMessages.add_message("Global", "SYSTEM", "System", "/giveeventrewards - Give rewards to participants")
      ChatMessages.add_message("Global", "SYSTEM", "System", "/listrewards - List available rewards")
      ChatMessages.add_message("Global", "SYSTEM", "System", "/listchallenges - List available challenges")
      ChatMessages.add_message("Global", "SYSTEM", "System", "/eventhelp - Show this help")
      ChatMessages.add_message("Global", "SYSTEM", "System", "======================")
    end

    def handle_modify_event_reward(slot, name)
      unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Not connected to server")
        return
      end

      unless defined?(EventSystem)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: EventSystem not loaded")
        return
      end

      unless slot >= 1 && slot <= 2
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Reward slot must be 1 or 2")
        return
      end

      if defined?(EventModifierRegistry) && !EventModifierRegistry.valid_shiny_reward?(name)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Unknown reward '#{name}'. Use /listrewards")
        return
      end

      events = EventSystem.active_events
      if events.empty?
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No active event to modify")
        return
      end

      event_id = events.keys.first

      MultiplayerClient.send_data("ADMIN_EVENT_MODIFY:#{event_id}:reward:#{slot}:#{name}")
      update_local_event_reward(event_id, slot, name)

      ChatMessages.add_message("Global", "SYSTEM", "System", "Reward#{slot} set to '#{name}'")

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("EVENT-CMD", "Sent ADMIN_EVENT_MODIFY reward#{slot}=#{name}")
      end
    end

    def update_local_event_reward(event_id, slot, name)
      return unless defined?(EventSystem)

      events_hash = EventSystem.instance_variable_get(:@active_events)
      mutex = EventSystem.instance_variable_get(:@event_mutex)

      mutex.synchronize do
        event = events_hash[event_id]
        return unless event

        event[:reward_modifiers] ||= []

        idx = slot - 1
        while event[:reward_modifiers].length <= idx
          event[:reward_modifiers] << nil
        end
        event[:reward_modifiers][idx] = name
        event[:reward_modifiers].compact!
      end

      if defined?(EventUIManager)
        EventUIManager.investigate_modifier(name)
      end
    end

    def handle_modify_event_challenge(slot, name)
      unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Not connected to server")
        return
      end

      unless defined?(EventSystem)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: EventSystem not loaded")
        return
      end

      unless slot >= 1 && slot <= 3
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Challenge slot must be 1, 2, or 3")
        return
      end

      if defined?(EventModifierRegistry) && !EventModifierRegistry.valid_shiny_challenge?(name)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Unknown challenge '#{name}'. Use /listchallenges")
        return
      end

      events = EventSystem.active_events
      if events.empty?
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No active event to modify")
        return
      end

      event_id = events.keys.first

      MultiplayerClient.send_data("ADMIN_EVENT_MODIFY:#{event_id}:challenge:#{slot}:#{name}")
      update_local_event_challenge(event_id, slot, name)

      ChatMessages.add_message("Global", "SYSTEM", "System", "Challenge#{slot} set to '#{name}'")

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("EVENT-CMD", "Sent ADMIN_EVENT_MODIFY challenge#{slot}=#{name}")
      end
    end

    def update_local_event_challenge(event_id, slot, name)
      return unless defined?(EventSystem)

      events_hash = EventSystem.instance_variable_get(:@active_events)
      mutex = EventSystem.instance_variable_get(:@event_mutex)

      mutex.synchronize do
        event = events_hash[event_id]
        return unless event

        event[:challenge_modifiers] ||= []

        idx = slot - 1
        while event[:challenge_modifiers].length <= idx
          event[:challenge_modifiers] << nil
        end
        event[:challenge_modifiers][idx] = name
        event[:challenge_modifiers].compact!
      end

      if defined?(EventUIManager)
        EventUIManager.investigate_modifier(name)
      end
    end

    def handle_modify_event_map(scope)
      unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Not connected to server")
        return
      end

      unless defined?(EventSystem)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: EventSystem not loaded")
        return
      end

      events = EventSystem.active_events
      if events.empty?
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No active event to modify")
        return
      end

      event_id = events.keys.first

      map_value = case scope
      when "global"
        "global"
      when "currentmap"
        if defined?($game_map) && $game_map
          $game_map.map_id.to_s
        else
          "global"
        end
      else
        "global"
      end

      MultiplayerClient.send_data("ADMIN_EVENT_MODIFY:#{event_id}:map:#{map_value}")
      update_local_event_map(event_id, map_value)

      ChatMessages.add_message("Global", "SYSTEM", "System", "Event scope set to '#{scope}' (map: #{map_value})")

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("EVENT-CMD", "Sent ADMIN_EVENT_MODIFY map=#{map_value}")
      end
    end

    def update_local_event_map(event_id, map_value)
      return unless defined?(EventSystem)

      events_hash = EventSystem.instance_variable_get(:@active_events)
      mutex = EventSystem.instance_variable_get(:@event_mutex)

      mutex.synchronize do
        event = events_hash[event_id]
        return unless event
        event[:map] = map_value
      end

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("EVENT-CMD", "Local event map updated to: #{map_value}")
      end
    end

    def handle_give_event_rewards
      unless defined?(EventSystem)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: EventSystem not loaded")
        return
      end

      unless defined?(EventRewards)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: EventRewards not loaded")
        return
      end

      events = EventSystem.active_events
      if events.empty?
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No active event")
        return
      end

      event_id = events.keys.first
      event = events.values.first

      ChatMessages.add_message("Global", "SYSTEM", "System", "=== Distributing Rewards ===")

      reward_mods = event[:reward_modifiers] || []
      if reward_mods.empty?
        ChatMessages.add_message("Global", "SYSTEM", "System", "No reward modifiers set for this event")
        return
      end

      ChatMessages.add_message("Global", "SYSTEM", "System", "Active rewards: #{reward_mods.join(', ')}")

      player_id = get_local_player_id

      reward_mods.each do |mod_id|
        reward_info = EventModifierRegistry.get_shiny_reward_info(mod_id)
        next unless reward_info

        case reward_info[:reward_type]
        when :item
          ChatMessages.add_message("Global", "SYSTEM", "System", "Giving item reward: #{reward_info[:name]}")
          reward_data = EventModifierRegistry.execute_reward(mod_id, {})
          if reward_data
            result = EventRewards.give_item_reward(reward_data)
            if result[:success]
              ChatMessages.add_message("Global", "SYSTEM", "System", "  Success! #{result[:type]}")
              EventUIManager.deactivate_modifier(mod_id) if defined?(EventUIManager)
            else
              ChatMessages.add_message("Global", "SYSTEM", "System", "  Failed: #{result[:error]}")
            end
          end

        when :end_of_event
          grant_end_of_event_reward(mod_id, reward_info)

        when :passive
          grant_passive_reward(mod_id, reward_info)
        end
      end

      ChatMessages.add_message("Global", "SYSTEM", "System", "============================")
    end

    def grant_end_of_event_reward(mod_id, reward_info)
      mod_id_str = mod_id.to_s.downcase

      case mod_id_str
      when "pity"
        if defined?(ShinyRewardTracker)
          ShinyRewardTracker.grant_pity_buff
          ChatMessages.add_message("Global", "SYSTEM", "System", "Pity granted! Next encounter is guaranteed shiny!")
        end

      when "fusion"
        if defined?(ShinyRewardTracker)
          ShinyRewardTracker.grant_fusion_shiny_buff
          ChatMessages.add_message("Global", "SYSTEM", "System", "Fusion granted! Next wild fusion will have a shiny part!")
        end

      else
        ChatMessages.add_message("Global", "SYSTEM", "System", "End-of-event reward '#{reward_info[:name]}' granted!")
        EventUIManager.activate_modifier(mod_id) if defined?(EventUIManager)
      end
    end

    def grant_passive_reward(mod_id, reward_info)
      mod_id_str = mod_id.to_s.downcase

      case mod_id_str
      when "blessing"
        ChatMessages.add_message("Global", "SYSTEM", "System", "Blessing active! x100 shiny chance for 30s when entering event map.")
        EventUIManager.activate_modifier("blessing") if defined?(EventUIManager)

      when "squad_scaling"
        if defined?(EventRewards)
          multiplier = EventRewards.get_squad_scaling_multiplier
          ChatMessages.add_message("Global", "SYSTEM", "System", "Squad Scaling active! x#{multiplier} based on squad size")
          EventUIManager.activate_modifier("squad_scaling") if defined?(EventUIManager)
        end

      else
        ChatMessages.add_message("Global", "SYSTEM", "System", "Passive reward '#{reward_info[:name]}' is active on event map")
        EventUIManager.activate_modifier(mod_id) if defined?(EventUIManager)
      end
    end

    def get_local_player_id
      if defined?(MultiplayerClient)
        MultiplayerClient.instance_variable_get(:@player_name) rescue "local"
      else
        "local"
      end
    end

    def handle_list_rewards
      ChatMessages.add_message("Global", "SYSTEM", "System", "=== Available Shiny Rewards ===")

      if defined?(EventModifierRegistry)
        rewards = EventModifierRegistry.list_shiny_rewards
        rewards.each do |r|
          type_str = r[:type] == :passive ? "Passive" : "Item"
          ChatMessages.add_message("Global", "SYSTEM", "System", "  #{r[:id]} (#{r[:weight]}%) [#{type_str}]")
          info = EventModifierRegistry.get_shiny_reward_info(r[:id])
          if info
            ChatMessages.add_message("Global", "SYSTEM", "System", "    #{info[:description]}")
          end
        end
      else
        ChatMessages.add_message("Global", "SYSTEM", "System", "EventModifierRegistry not loaded")
      end

      ChatMessages.add_message("Global", "SYSTEM", "System", "===============================")
    end

    def handle_list_challenges
      ChatMessages.add_message("Global", "SYSTEM", "System", "=== Available Shiny Challenges ===")

      if defined?(EventModifierRegistry)
        challenges = EventModifierRegistry.list_shiny_challenges
        challenges.each do |c|
          ChatMessages.add_message("Global", "SYSTEM", "System", "  #{c[:id]} (#{c[:weight]}%)")
          info = EventModifierRegistry.get_shiny_challenge_info(c[:id])
          if info
            ChatMessages.add_message("Global", "SYSTEM", "System", "    #{info[:description]}")
          end
        end
      else
        ChatMessages.add_message("Global", "SYSTEM", "System", "EventModifierRegistry not loaded")
      end

      ChatMessages.add_message("Global", "SYSTEM", "System", "==================================")
    end

    #---------------------------------------------------------------------------
    # Pokemon Command Handlers (from 160)
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

      evolutions = pkmn.species_data.get_evolutions(true)
      if evolutions.nil? || evolutions.empty?
        ChatMessages.add_message("Global", "SYSTEM", "System",
          "Error: #{pkmn.name} (#{pkmn.speciesName}) has no evolutions")
        return
      end

      new_species = evolutions[0][0]
      new_species_name = GameData::Species.get(new_species).name

      ChatMessages.add_message("Global", "SYSTEM", "System",
        "Evolving #{pkmn.name} into #{new_species_name}...")

      pbFadeOutInWithMusic {
        evo = PokemonEvolutionScene.new
        evo.pbStartScreen(pkmn, new_species)
        evo.pbEvolution(false)
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

      if $PokemonBag.pbStoreItem(match[:item_id])
        ChatMessages.add_message("Global", "SYSTEM", "System",
          "Gave Bloodbound Catalyst (#{match[:type_name]})")
      else
        ChatMessages.add_message("Global", "SYSTEM", "System",
          "Error: Bag is full, could not add item")
      end
    end

    def handle_unboss(index)
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

      unless pkmn.respond_to?(:is_boss?) && pkmn.is_boss?
        ChatMessages.add_message("Global", "SYSTEM", "System",
          "Party slot #{index} (#{pkmn.name}) is not a boss")
        return
      end

      pkmn.clear_boss!
      ChatMessages.add_message("Global", "SYSTEM", "System",
        "Cleared boss data from slot #{index} (#{pkmn.name})")
    end
  end
end

# =============================================================================
# Scene_Map Integration - Event HUD Update Hook (from 156)
# =============================================================================
class Scene_Map
  unless method_defined?(:event_system_original_updateSpritesets)
    alias event_system_original_updateSpritesets updateSpritesets
  end

  def updateSpritesets(refresh = false)
    event_system_original_updateSpritesets(refresh)
    EventUIManager.update if defined?(EventUIManager)
  end
end

# =============================================================================
# Force Shiny Hook (from 107) - Only active when FAMILY_TESTING_COMMANDS_ENABLED
# =============================================================================
if FAMILY_TESTING_COMMANDS_ENABLED
  class Pokemon
    alias family_test_force_shiny_initialize initialize
    def initialize(*args)
      family_test_force_shiny_initialize(*args)

      if $FORCE_ALL_SHINY_TESTING
        @shiny = true
        @natural_shiny = false
      end
    end
  end
end

# =============================================================================
# Unkillable Flag on Pokemon (from 160)
# =============================================================================
class Pokemon
  attr_accessor :unkillable

  alias unkillable_original_initialize initialize

  def initialize(*args)
    unkillable_original_initialize(*args)
    @unkillable = false
  end
end

# =============================================================================
# Battle Hook: Prevent unkillable Pokemon from fainting (from 160)
# =============================================================================
class PokeBattle_Battler
  alias unkillable_pbReduceHP pbReduceHP

  def pbReduceHP(amt, anim = true, registerDamage = true, anyAnim = true)
    if @pokemon&.unkillable
      amt = amt.round
      max_loss = @hp - 1
      amt = max_loss if amt > max_loss
      amt = 0 if amt < 0
    end
    unkillable_pbReduceHP(amt, anim, registerDamage, anyAnim)
  end
end
