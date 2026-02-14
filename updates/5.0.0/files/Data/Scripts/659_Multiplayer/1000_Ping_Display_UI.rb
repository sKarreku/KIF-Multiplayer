#===============================================================================
# MODULE: Ping Display UI - Adds ping display to player list
#===============================================================================
# Hooks the player list to show latency next to each player name
#===============================================================================

module MultiplayerUI
  class << self
    # Format a player entry with ping information
    def format_player_with_ping(player_entry)
      # Parse the entry to get SID and name
      sid, name = parse_player_entry(player_entry)

      # If we can't parse it, return as-is
      return player_entry if sid.nil?

      # Get ping for this player
      ping = 0
      if defined?(PingTracker)
        ping = PingTracker.get_ping(sid)
      end

      # Format with ping
      ping_text = ping > 0 ? "#{ping}ms" : "?ms"

      # Return formatted string: "SID - Name (XXXms)"
      return "#{sid} - #{name} (#{ping_text})"
    end

    # Hook openPlayerList to add ping to player entries
    alias ping_display_original_openPlayerList openPlayerList
    def openPlayerList
      # Intercept by wrapping the method entirely
      # We need to check if connected, same as original
      unless MultiplayerClient.instance_variable_get(:@connected)
        pbMessage(_INTL("You are not connected to the server."))
        return
      end

      # Prevent multiple simultaneous windows
      if MultiplayerUI.instance_variable_get(:@playerlist_open)
        return
      end

      # Set flag to prevent multiple windows
      MultiplayerUI.instance_variable_set(:@playerlist_open, true)
      MultiplayerUI.instance_variable_set(:@playerlist_close_requested, false)

      begin
        MultiplayerClient.send_data("REQ_PLAYERS")

        # --- Viewport setup ---
        viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
        viewport.z = 99999

        # Background (semi-transparent)
        bg = Sprite.new(viewport)
        bg.bitmap = Bitmap.new(Graphics.width, Graphics.height)
        bg.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 160))

        # Centered loading window
        loading = Window_UnformattedTextPokemon.newWithSize(
          _INTL("Loading player list... 0%"), 0, 0, Graphics.width - 64, 64, viewport
        )
        loading.x = (Graphics.width - loading.width) / 2
        loading.y = (Graphics.height - loading.height) / 2

        start_time = Time.now
        timeout_seconds = 3.0
        players = nil

        # --- Non-blocking wait with progress bar ---
        while Time.now - start_time < timeout_seconds
          Graphics.update
          Input.update

          # Update loading progress bar
          elapsed = Time.now - start_time
          progress = (elapsed / timeout_seconds * 100).to_i
          loading.text = _INTL("Loading player list... {1}%", progress)

          players = MultiplayerClient.instance_variable_get(:@player_list)
          break if players && players.any?
        end

        # Final quick recheck
        if (!players || players.empty?) && MultiplayerClient.instance_variable_get(:@player_list)
          players = MultiplayerClient.instance_variable_get(:@player_list)
        end
        loading.dispose if !loading.disposed?

        if !players || players.empty?
          pbSEPlay("GUI menu close")
          bg.dispose if !bg.disposed?
          viewport.dispose if !viewport.disposed?
          pbMessage(_INTL("No player data received from server."))
          return
        end

        # --- HERE IS THE KEY CHANGE: Add ping to each player entry ---
        cmds = players.map { |p| format_player_with_ping(p) }

        # --- Scroll window ---
        win = Window_CommandPokemon.new(cmds)
        win.viewport = viewport
        win.width  = Graphics.width - 32
        win.height = Graphics.height - 32
        win.x = 16
        win.y = 16
        win.opacity = 210
        win.index = 0

        # --- Main loop ---
        loop do
          Graphics.update
          Input.update
          win.update

          # Check for F3 close request
          if MultiplayerUI.instance_variable_get(:@playerlist_close_requested)
            MultiplayerUI.instance_variable_set(:@playerlist_close_requested, false)
            pbSEPlay("GUI menu close")
            break
          end

          if Input.trigger?(Input::BACK)
            pbSEPlay("GUI menu close")
            break
          elsif Input.trigger?(Input::USE)
            sel = win.index
            chosen_line = cmds[sel]
            pbSEPlay("GUI select")

            sid, name = MultiplayerUI.parse_player_entry(chosen_line)
            if sid.nil? || sid.empty?
              pbMessage(_INTL("Invalid player entry."))
              next
            end

            my_sid = MultiplayerClient.session_id rescue nil
            if my_sid && sid == my_sid
              pbMessage(_INTL("You cannot select yourself."))
              next
            end

            # Build per-player actions
            actions = [_INTL("Invite to Squad"), _INTL("Let's Battle!"), _INTL("Request Trade"), _INTL("Cancel")]
            # Remove ping suffix from name for display
            display_name = name.gsub(/\s*\(\d+ms\)$/, '').gsub(/\s*\(\?ms\)$/, '')
            act = pbMessage(_INTL("Player: {1}", display_name), actions, 0)

            case act
            when 0
              begin
                sq = MultiplayerClient.squad
                if sq && sq[:members].is_a?(Array) && sq[:members].length >= 3
                  pbMessage(_INTL("Your squad is full."))
                else
                  MultiplayerClient.invite_player(sid)
                  pbMessage(_INTL("Invite sent to {1}.", display_name))
                end
              rescue => e
                pbMessage(_INTL("Failed to send invite."))
              end

            when 1
              # Let's Battle!
              begin
                if defined?(PvPBattleState) && defined?(MultiplayerClient.pvp_active?) && MultiplayerClient.pvp_active?
                  pbMessage(_INTL("You are already in a PvP battle setup."))
                elsif MultiplayerClient.trade_active?
                  pbMessage(_INTL("You are currently trading."))
                elsif defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
                  pbMessage(_INTL("You are currently in a coop battle."))
                else
                  MultiplayerClient.pvp_invite(sid)
                  pbMessage(_INTL("Battle request sent to {1}.", display_name))
                end
              rescue => e
                ##MultiplayerDebug.error("UI-PL-PVP-ERR", "Error sending battle request: #{e.message}") if defined?(MultiplayerDebug)
                pbMessage(_INTL("Failed to send battle request."))
              end

            when 2
              # Request Trade
              begin
                if MultiplayerClient.trade_active?
                  pbMessage(_INTL("You are already in a trade."))
                else
                  MultiplayerClient.trade_invite(sid)
                  pbMessage(_INTL("Trade request sent to {1}.", display_name))
                end
              rescue => e
                pbMessage(_INTL("Failed to send trade request."))
              end
            end
          end
        end

        # --- Cleanup ---
        win.dispose if !win.disposed?
        bg.dispose if !bg.disposed?
        viewport.dispose if !viewport.disposed?
        Graphics.update

      ensure
        MultiplayerUI.instance_variable_set(:@playerlist_open, false)
      end
    end
  end
end

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("PING-UI", "Ping display UI hook loaded")
end
