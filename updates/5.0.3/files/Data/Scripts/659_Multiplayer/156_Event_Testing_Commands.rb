#===============================================================================
# MODULE: Event System - Testing Chat Commands
#===============================================================================
# Chat commands for testing the event system.
#
# Commands:
#   /createevent <type>          - Create a new event (shiny, family, boss)
#   /endevent                    - End the current active event
#   /checkevent                  - Check current event status
#   /checkshinyrate              - Check current shiny rate multiplier
#   /eventhelp                   - Show event command help
#   /modifyevent reward1 <name>  - Set first reward modifier
#   /modifyevent reward2 <name>  - Set second reward modifier
#   /modifyevent challenge1 <n>  - Set first challenge modifier
#   /modifyevent challenge2 <n>  - Set second challenge modifier
#   /modifyevent challenge3 <n>  - Set third challenge modifier
#   /modifyevent map <scope>     - Set event scope (global/currentmap)
#   /giveeventrewards            - Distribute rewards to participants
#   /listrewards                 - List all available reward modifiers
#   /listchallenges              - List all available challenge modifiers
#
# Examples:
#   /createevent shiny           → Creates a shiny event (x10 shiny chance, 1 hour)
#   /createevent family          → Creates a family event (100% family chance)
#   /createevent boss            → Creates a boss event (10% boss spawn)
#   /modifyevent reward1 blessing → Set blessing as first reward
#   /modifyevent map currentmap  → Limit event to current map
#   /endevent                    → Ends any active event
#   /checkevent                  → Shows event status
#   /checkshinyrate              → Shows current shiny multiplier
#===============================================================================

EVENT_TESTING_COMMANDS_ENABLED = false

# Extend ChatCommands to add event testing commands
module ChatCommands
  class << self
    # Save original parse method (if not already aliased by another module)
    unless method_defined?(:event_original_parse)
      alias event_original_parse parse
    end

    # Override parse to add event commands
    def parse(text)
      return event_original_parse(text) unless EVENT_TESTING_COMMANDS_ENABLED
      case text
      # Create event: /createevent shiny, /createevent family, /createevent boss
      when /^\/createevent\s+(shiny|family|boss)$/i
        { type: :create_event, event_type: $1.downcase }

      # End event: /endevent
      when /^\/endevent$/i
        { type: :end_event }

      # Check event status: /checkevent
      when /^\/checkevent$/i
        { type: :check_event }

      # Check shiny rate: /checkshinyrate
      when /^\/checkshinyrate$/i
        { type: :check_shiny_rate }

      # Event help: /eventhelp
      when /^\/eventhelp$/i
        { type: :event_help }

      # Modify event reward: /modifyevent reward1 blessing, /modifyevent reward2 pity
      when /^\/modifyevent\s+(reward)(\d)\s+(\w+)$/i
        slot = $2.to_i
        modifier_name = $3.downcase
        { type: :modify_event_reward, slot: slot, name: modifier_name }

      # Modify event challenge: /modifyevent challenge1 no_switching
      when /^\/modifyevent\s+(challenge)(\d)\s+(\w+)$/i
        slot = $2.to_i
        modifier_name = $3.downcase
        { type: :modify_event_challenge, slot: slot, name: modifier_name }

      # Modify event map scope: /modifyevent map global, /modifyevent map currentmap
      when /^\/modifyevent\s+map\s+(global|currentmap)$/i
        scope = $1.downcase
        { type: :modify_event_map, scope: scope }

      # Give event rewards: /giveeventrewards
      when /^\/giveeventrewards$/i
        { type: :give_event_rewards }

      # List available rewards: /listrewards
      when /^\/listrewards$/i
        { type: :list_rewards }

      # List available challenges: /listchallenges
      when /^\/listchallenges$/i
        { type: :list_challenges }

      else
        # Fall back to original parse (which may chain to other parsers)
        event_original_parse(text)
      end
    end
  end
end

# Extend ChatNetwork to handle event commands
module ChatNetwork
  class << self
    # Save original send_command method (if not already aliased by another module)
    unless method_defined?(:event_original_send_command)
      alias event_original_send_command send_command
    end

    # Override send_command to handle event commands
    def send_command(cmd)
      case cmd[:type]
      when :create_event
        handle_create_event(cmd[:event_type])
      when :end_event
        handle_end_event
      when :check_event
        handle_check_event
      when :check_shiny_rate
        handle_check_shiny_rate
      when :event_help
        handle_event_help
      when :modify_event_reward
        handle_modify_event_reward(cmd[:slot], cmd[:name])
      when :modify_event_challenge
        handle_modify_event_challenge(cmd[:slot], cmd[:name])
      when :modify_event_map
        handle_modify_event_map(cmd[:scope])
      when :give_event_rewards
        handle_give_event_rewards
      when :list_rewards
        handle_list_rewards
      when :list_challenges
        handle_list_challenges
      else
        # Fall back to original handler
        event_original_send_command(cmd)
      end
    end

    #---------------------------------------------------------------------------
    # Command Handlers
    #---------------------------------------------------------------------------

    # Create a new event
    def handle_create_event(event_type)
      unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Not connected to server")
        return
      end

      # Send event creation request to server
      MultiplayerClient.send_data("ADMIN_EVENT_CREATE:#{event_type}")
      ChatMessages.add_message("Global", "SYSTEM", "System", "Requesting #{event_type} event creation...")

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("EVENT-CMD", "Sent ADMIN_EVENT_CREATE:#{event_type}")
      end
    end

    # End the current active event
    def handle_end_event
      unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Not connected to server")
        return
      end

      # Check if there's an active event
      if defined?(EventSystem)
        events = EventSystem.active_events
        if events.empty?
          ChatMessages.add_message("Global", "SYSTEM", "System", "No active event to end")
          return
        end

        # Get the first active event ID
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

    # Check current event status
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

            # Show challenge modifiers
            challenges = event[:challenge_modifiers] || []
            if challenges.any?
              ChatMessages.add_message("Global", "SYSTEM", "System", "  Challenges: #{challenges.length}")
              challenges.each do |c|
                ChatMessages.add_message("Global", "SYSTEM", "System", "    - #{c}")
              end
            end

            # Show reward modifiers
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

    # Check current shiny rate
    def handle_check_shiny_rate
      ChatMessages.add_message("Global", "SYSTEM", "System", "=== Shiny Rate Check ===")

      # Get base shiny odds
      base_odds = 65536  # Default max
      if defined?($PokemonSystem) && $PokemonSystem.respond_to?(:shinyodds)
        base_odds = $PokemonSystem.shinyodds || 65536
      end

      base_rate = base_odds.to_f / 65536.0
      base_percent = (base_rate * 100).round(4)

      ChatMessages.add_message("Global", "SYSTEM", "System", "Base shiny odds: #{base_odds}/65536 (#{base_percent}%)")

      # Check if on event map
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

      # Check for event multiplier
      total_multiplier = 1.0
      if defined?(EventSystem) && EventSystem.has_active_event?("shiny")
        ChatMessages.add_message("Global", "SYSTEM", "System", "Shiny event ACTIVE!")
        ChatMessages.add_message("Global", "SYSTEM", "System", "On event map: #{on_event_map ? 'YES' : 'NO'}")

        if on_event_map
          # Base event multiplier
          event_mult = EventSystem.get_modifier_multiplier("shiny_multiplier", "shiny")
          if event_mult > 1
            total_multiplier *= event_mult
            ChatMessages.add_message("Global", "SYSTEM", "System", "  Event base: x#{event_mult}")
          end

          # Check passive modifiers (auto-active on event map)
          ChatMessages.add_message("Global", "SYSTEM", "System", "--- Passive Modifiers ---")
          player_id = get_local_player_id

          # Blessing (x100 for 30s on map entry) - buff-based
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

          # Squad Scaling (x1/x2/x3 based on squad size) - auto-active
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

          # Shooting Star Charm (permanent x1.5)
          if defined?(EventRewards) && EventRewards.has_shooting_star_charm?
            total_multiplier *= 1.5
            ChatMessages.add_message("Global", "SYSTEM", "System", "  Shooting Star Charm: x1.5 ACTIVE")
          end

          # End-of-event rewards (require eligibility + /giveeventrewards)
          ChatMessages.add_message("Global", "SYSTEM", "System", "--- End-of-Event Rewards ---")

          # Pity (guaranteed next shiny) - given to eligible players at event end
          if EventSystem.has_reward_modifier?("pity")
            if defined?(EventRewards) && EventRewards.has_buff?(player_id, :pity)
              ChatMessages.add_message("Global", "SYSTEM", "System", "  Pity: READY (next = 100% shiny)")
            else
              ChatMessages.add_message("Global", "SYSTEM", "System", "  Pity: not received (be eligible + /giveeventrewards)")
            end
          else
            ChatMessages.add_message("Global", "SYSTEM", "System", "  Pity: not set on event")
          end

          # Fusion (next fusion has shiny part) - given to eligible players at event end
          if EventSystem.has_reward_modifier?("fusion")
            if defined?(EventRewards) && EventRewards.has_buff?(player_id, :fusion_shiny)
              ChatMessages.add_message("Global", "SYSTEM", "System", "  Fusion: READY (next fusion = shiny part)")
            else
              ChatMessages.add_message("Global", "SYSTEM", "System", "  Fusion: not received (be eligible + /giveeventrewards)")
            end
          else
            ChatMessages.add_message("Global", "SYSTEM", "System", "  Fusion: not set on event")
          end

          # Calculate effective odds
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

    # Show event command help
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

    #---------------------------------------------------------------------------
    # Modifier Commands
    #---------------------------------------------------------------------------

    # Modify event reward
    def handle_modify_event_reward(slot, name)
      unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Not connected to server")
        return
      end

      unless defined?(EventSystem)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: EventSystem not loaded")
        return
      end

      # Validate slot (1-2)
      unless slot >= 1 && slot <= 2
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Reward slot must be 1 or 2")
        return
      end

      # Validate reward name
      if defined?(EventModifierRegistry) && !EventModifierRegistry.valid_shiny_reward?(name)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Unknown reward '#{name}'. Use /listrewards")
        return
      end

      # Check if event exists
      events = EventSystem.active_events
      if events.empty?
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No active event to modify")
        return
      end

      event_id = events.keys.first

      # Send modification request to server
      MultiplayerClient.send_data("ADMIN_EVENT_MODIFY:#{event_id}:reward:#{slot}:#{name}")

      # Also update local event data immediately for UI responsiveness
      update_local_event_reward(event_id, slot, name)

      ChatMessages.add_message("Global", "SYSTEM", "System", "Reward#{slot} set to '#{name}'")

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("EVENT-CMD", "Sent ADMIN_EVENT_MODIFY reward#{slot}=#{name}")
      end
    end

    # Update local event reward data (for immediate UI update)
    def update_local_event_reward(event_id, slot, name)
      return unless defined?(EventSystem)

      # Access the internal events hash directly for modification
      events_hash = EventSystem.instance_variable_get(:@active_events)
      mutex = EventSystem.instance_variable_get(:@event_mutex)

      mutex.synchronize do
        event = events_hash[event_id]
        return unless event

        # Initialize reward_modifiers array if needed
        event[:reward_modifiers] ||= []

        # Set the reward at the specified slot (1-indexed to 0-indexed)
        idx = slot - 1
        while event[:reward_modifiers].length <= idx
          event[:reward_modifiers] << nil
        end
        event[:reward_modifiers][idx] = name

        # Remove nil entries
        event[:reward_modifiers].compact!
      end

      # Update UI to show the modifier (as investigated/white)
      if defined?(EventUIManager)
        EventUIManager.investigate_modifier(name)
      end
    end

    # Modify event challenge
    def handle_modify_event_challenge(slot, name)
      unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Not connected to server")
        return
      end

      unless defined?(EventSystem)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: EventSystem not loaded")
        return
      end

      # Validate slot (1-3)
      unless slot >= 1 && slot <= 3
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Challenge slot must be 1, 2, or 3")
        return
      end

      # Validate challenge name
      if defined?(EventModifierRegistry) && !EventModifierRegistry.valid_shiny_challenge?(name)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Unknown challenge '#{name}'. Use /listchallenges")
        return
      end

      # Check if event exists
      events = EventSystem.active_events
      if events.empty?
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No active event to modify")
        return
      end

      event_id = events.keys.first

      # Send modification request to server
      MultiplayerClient.send_data("ADMIN_EVENT_MODIFY:#{event_id}:challenge:#{slot}:#{name}")

      # Also update local event data immediately for UI responsiveness
      update_local_event_challenge(event_id, slot, name)

      ChatMessages.add_message("Global", "SYSTEM", "System", "Challenge#{slot} set to '#{name}'")

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("EVENT-CMD", "Sent ADMIN_EVENT_MODIFY challenge#{slot}=#{name}")
      end
    end

    # Update local event challenge data (for immediate UI update)
    def update_local_event_challenge(event_id, slot, name)
      return unless defined?(EventSystem)

      # Access the internal events hash directly for modification
      events_hash = EventSystem.instance_variable_get(:@active_events)
      mutex = EventSystem.instance_variable_get(:@event_mutex)

      mutex.synchronize do
        event = events_hash[event_id]
        return unless event

        # Initialize challenge_modifiers array if needed
        event[:challenge_modifiers] ||= []

        # Set the challenge at the specified slot (1-indexed to 0-indexed)
        idx = slot - 1
        while event[:challenge_modifiers].length <= idx
          event[:challenge_modifiers] << nil
        end
        event[:challenge_modifiers][idx] = name

        # Remove nil entries
        event[:challenge_modifiers].compact!
      end

      # Update UI to show the modifier (as investigated/white)
      if defined?(EventUIManager)
        EventUIManager.investigate_modifier(name)
      end
    end

    # Modify event map scope
    def handle_modify_event_map(scope)
      unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: Not connected to server")
        return
      end

      unless defined?(EventSystem)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: EventSystem not loaded")
        return
      end

      # Check if event exists
      events = EventSystem.active_events
      if events.empty?
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No active event to modify")
        return
      end

      event_id = events.keys.first

      # Determine map value
      map_value = case scope
      when "global"
        "global"
      when "currentmap"
        # Get current map ID
        if defined?($game_map) && $game_map
          $game_map.map_id.to_s
        else
          "global"
        end
      else
        "global"
      end

      # Send modification request to server
      MultiplayerClient.send_data("ADMIN_EVENT_MODIFY:#{event_id}:map:#{map_value}")

      # Also update local event data immediately for UI responsiveness
      update_local_event_map(event_id, map_value)

      ChatMessages.add_message("Global", "SYSTEM", "System", "Event scope set to '#{scope}' (map: #{map_value})")

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("EVENT-CMD", "Sent ADMIN_EVENT_MODIFY map=#{map_value}")
      end
    end

    # Update local event map data (for immediate UI update)
    def update_local_event_map(event_id, map_value)
      return unless defined?(EventSystem)

      # Access the internal events hash directly for modification
      events_hash = EventSystem.instance_variable_get(:@active_events)
      mutex = EventSystem.instance_variable_get(:@event_mutex)

      mutex.synchronize do
        event = events_hash[event_id]
        return unless event

        # Set the map value
        event[:map] = map_value
      end

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("EVENT-CMD", "Local event map updated to: #{map_value}")
      end
    end

    # Give event rewards to all eligible participants
    def handle_give_event_rewards
      unless defined?(EventSystem)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: EventSystem not loaded")
        return
      end

      unless defined?(EventRewards)
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: EventRewards not loaded")
        return
      end

      # Check if event exists
      events = EventSystem.active_events
      if events.empty?
        ChatMessages.add_message("Global", "SYSTEM", "System", "Error: No active event")
        return
      end

      event_id = events.keys.first
      event = events.values.first

      ChatMessages.add_message("Global", "SYSTEM", "System", "=== Distributing Rewards ===")

      # Get reward modifiers
      reward_mods = event[:reward_modifiers] || []
      if reward_mods.empty?
        ChatMessages.add_message("Global", "SYSTEM", "System", "No reward modifiers set for this event")
        return
      end

      ChatMessages.add_message("Global", "SYSTEM", "System", "Active rewards: #{reward_mods.join(', ')}")

      # Note: This is an admin command - force-gives all rewards
      # Normal gameplay would check eligibility via EventRewards.eligible_for_rewards?
      player_id = get_local_player_id

      # Process each reward modifier - admin command gives ALL rewards
      reward_mods.each do |mod_id|
        reward_info = EventModifierRegistry.get_shiny_reward_info(mod_id)
        next unless reward_info

        case reward_info[:reward_type]
        when :item
          # Item rewards - admin command force-gives
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
          # End-of-event rewards (Pity, Fusion) - admin command grants directly
          grant_end_of_event_reward(mod_id, reward_info)

        when :passive
          # Passive rewards (Blessing, Squad Scaling) - just inform they're active
          grant_passive_reward(mod_id, reward_info)
        end
      end

      ChatMessages.add_message("Global", "SYSTEM", "System", "============================")
    end

    # Grant an end-of-event reward to an eligible player
    def grant_end_of_event_reward(mod_id, reward_info)
      mod_id_str = mod_id.to_s.downcase

      case mod_id_str
      when "pity"
        # Pity - guaranteed next shiny
        if defined?(ShinyRewardTracker)
          ShinyRewardTracker.grant_pity_buff
          ChatMessages.add_message("Global", "SYSTEM", "System", "Pity granted! Next encounter is guaranteed shiny!")
        end

      when "fusion"
        # Fusion - next fusion has shiny part
        if defined?(ShinyRewardTracker)
          ShinyRewardTracker.grant_fusion_shiny_buff
          ChatMessages.add_message("Global", "SYSTEM", "System", "Fusion granted! Next wild fusion will have a shiny part!")
        end

      else
        ChatMessages.add_message("Global", "SYSTEM", "System", "End-of-event reward '#{reward_info[:name]}' granted!")
        EventUIManager.activate_modifier(mod_id) if defined?(EventUIManager)
      end
    end

    # Inform about passive rewards (active automatically on event map)
    def grant_passive_reward(mod_id, reward_info)
      mod_id_str = mod_id.to_s.downcase

      case mod_id_str
      when "blessing"
        # Blessing - x100 for 30s on map entry
        ChatMessages.add_message("Global", "SYSTEM", "System", "Blessing active! x100 shiny chance for 30s when entering event map.")
        EventUIManager.activate_modifier("blessing") if defined?(EventUIManager)

      when "squad_scaling"
        # Squad scaling is auto-active based on squad size
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

    # Get local player ID for buff tracking
    def get_local_player_id
      if defined?(MultiplayerClient)
        MultiplayerClient.instance_variable_get(:@player_name) rescue "local"
      else
        "local"
      end
    end

    # List all available rewards
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

    # List all available challenges
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
  end
end

#===============================================================================
# Scene_Map Integration - Event HUD Update Hook
#===============================================================================
# Add EventUIManager.update to Scene_Map's update loop
class Scene_Map
  # Alias the updateSpritesets method to add our event UI update
  unless method_defined?(:event_system_original_updateSpritesets)
    alias event_system_original_updateSpritesets updateSpritesets
  end

  def updateSpritesets(refresh = false)
    # Call original method
    event_system_original_updateSpritesets(refresh)

    # Update event UI (HUD and notifications)
    EventUIManager.update if defined?(EventUIManager)
  end
end

#===============================================================================
# Module loaded
#===============================================================================
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("EVENT-CMD", "=" * 60)
  MultiplayerDebug.info("EVENT-CMD", "156_Event_Testing_Commands.rb loaded")
  MultiplayerDebug.info("EVENT-CMD", "Event chat commands registered:")
  MultiplayerDebug.info("EVENT-CMD", "  /createevent <type>      - Create shiny/family/boss event")
  MultiplayerDebug.info("EVENT-CMD", "  /endevent                - End current event")
  MultiplayerDebug.info("EVENT-CMD", "  /checkevent              - Check event status")
  MultiplayerDebug.info("EVENT-CMD", "  /checkshinyrate          - Check current shiny rate")
  MultiplayerDebug.info("EVENT-CMD", "  /modifyevent reward# <n> - Set reward modifier")
  MultiplayerDebug.info("EVENT-CMD", "  /modifyevent challenge#  - Set challenge modifier")
  MultiplayerDebug.info("EVENT-CMD", "  /modifyevent map <scope> - Set event map scope")
  MultiplayerDebug.info("EVENT-CMD", "  /giveeventrewards        - Distribute item rewards")
  MultiplayerDebug.info("EVENT-CMD", "  /listrewards             - List available rewards")
  MultiplayerDebug.info("EVENT-CMD", "  /listchallenges          - List available challenges")
  MultiplayerDebug.info("EVENT-CMD", "  /eventhelp               - Show event commands")
  MultiplayerDebug.info("EVENT-CMD", "Scene_Map integration: EventUIManager.update hooked")
  MultiplayerDebug.info("EVENT-CMD", "=" * 60)
end
