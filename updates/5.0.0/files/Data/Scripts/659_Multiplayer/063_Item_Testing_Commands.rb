#===============================================================================
# MODULE: Item Testing Commands
#===============================================================================
# Chat commands for giving items during testing.
# Currently restricted to Poke Balls only.
#
# Commands:
#   /give <ballName> <quantity>   - Give yourself Poke Balls
#   /listballs                    - List all available ball types
#   /candy                        - Give yourself 100 Rare Candies
#
# Examples:
#   /give pokeball 100            - Give 100 Poke Balls
#   /give masterball 5            - Give 5 Master Balls
#   /give ultraball 50            - Give 50 Ultra Balls
#   /listballs                    - Show all valid ball names
#===============================================================================

ITEM_TESTING_COMMANDS_ENABLED = true

# Extend ChatCommands to add item testing commands
module ChatCommands
  class << self
    # Save original parse method
    alias item_original_parse parse

    # Override parse to add item commands
    def parse(text)
      return item_original_parse(text) unless ITEM_TESTING_COMMANDS_ENABLED

      case text
      # Give item: /give pokeball 100
      when /^\/give\s+(\w+)\s+(\d+)$/i
        { type: :give_item, item_name: $1.strip, quantity: $2.to_i }

      # List balls: /listballs
      when /^\/listballs$/i
        { type: :list_balls }

      # Rare Candies: /candy
      when /^\/candy$/i
        { type: :give_candy }

      else
        # Fall back to original parse
        item_original_parse(text)
      end
    end
  end
end

# Extend ChatNetwork to handle item commands
module ChatNetwork
  class << self
    # Save original send_command method
    alias item_original_send_command send_command

    # Override send_command to handle item commands
    def send_command(cmd)
      unless ITEM_TESTING_COMMANDS_ENABLED
        item_original_send_command(cmd)
        return
      end

      case cmd[:type]
      when :give_item
        handle_give_item(cmd[:item_name], cmd[:quantity])
      when :list_balls
        handle_list_balls
      when :give_candy
        handle_give_candy
      else
        # Fall back to original handler
        item_original_send_command(cmd)
      end
    end

    #---------------------------------------------------------------------------
    # Command Handlers
    #---------------------------------------------------------------------------

    # Give item (balls only for now)
    def handle_give_item(item_name, quantity)
      # Validate quantity
      if quantity <= 0
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Quantity must be > 0")
        return
      end
      if quantity > 999
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Max quantity is 999")
        return
      end

      # Resolve item symbol (uppercase, no spaces)
      item_str = item_name.gsub(/\s+/, '').upcase
      item_symbol = item_str.to_sym

      # Check if item exists
      unless GameData::Item.exists?(item_symbol)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Unknown item '#{item_name}'")
        ChatMessages.add_message("Global", "SYSTEM", "System", "Use /listballs to see valid ball names")
        return
      end

      # Restrict to Poke Balls only
      item_data = GameData::Item.get(item_symbol)
      unless item_data.is_poke_ball?
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Only Poke Balls allowed (got '#{item_data.name}')")
        ChatMessages.add_message("Global", "SYSTEM", "System", "Use /listballs to see valid ball names")
        return
      end

      # Validate bag exists
      unless defined?($PokemonBag) && $PokemonBag
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No bag available")
        return
      end

      # Add to bag
      if $PokemonBag.pbStoreItem(item_symbol, quantity)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Received #{quantity}x #{item_data.name}!")
      else
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Could not add #{item_data.name} to bag (bag full?)")
      end
    end

    # Give 100 Rare Candies
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

    # List all available Poke Balls
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
      # Show in groups of 6 to avoid chat spam
      balls.each_slice(6) do |group|
        ChatMessages.add_message("Global", "SYSTEM", "System", group.join(", "))
      end
    end
  end
end
