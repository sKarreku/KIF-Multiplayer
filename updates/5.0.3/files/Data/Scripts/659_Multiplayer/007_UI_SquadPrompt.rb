# ===========================================
# File: 007_UI_SquadPrompt.rb
# Purpose: Show squad invite prompts and queued toasts on the MAIN thread
# Hook: Scene_Map#update (no base edits)
# ===========================================

##MultiplayerDebug.info("UI-SQ-PROMPT", "Squad prompt/toast hook loaded.")

if defined?(Scene_Map)
  class Scene_Map
    alias kif_squad_update update unless method_defined?(:kif_squad_update)

    def update
      kif_squad_update

      begin
        # --- Drain one queued toast per frame (non-blocking feel) ---
        if MultiplayerClient.toast_pending?
          t = MultiplayerClient.dequeue_toast
          if t && t[:text] && !t[:text].empty?
            begin
              pbMessage(_INTL("{1}", t[:text]))
            rescue
              # headless fallback: print to console
              puts "[Multiplayer] #{t[:text]}"
            end
          end
        end

        # --- Invite prompt (only if connected and no active prompt) ---
        if MultiplayerClient.instance_variable_get(:@connected) &&
           !MultiplayerClient.invite_prompt_active?

          inv = MultiplayerClient.peek_next_invite
          if inv
            inv = MultiplayerClient.pop_next_invite
            inviter_sid  = inv[:sid]
            inviter_name = inv[:name].to_s

            choice = nil
            begin
              choice = pbMessage(
                _INTL("{1} wants you to join their Squad! Do you accept?", inviter_name),
                [_INTL("Yes"), _INTL("No")], 0
              )
            rescue
              choice = 1 # default to decline in headless cases
            end

            decision = (choice == 0) ? "ACCEPT" : "DECLINE"
            MultiplayerClient.send_squad_response(inviter_sid, decision)
          end
        end
      rescue => e
        ##MultiplayerDebug.error("UI-SQ-PROMPT", "Error in update: #{e.message}")
      ensure
        MultiplayerClient.finish_invite_prompt if MultiplayerClient.invite_prompt_active?
      end
    end
  end
  ##MultiplayerDebug.info("UI-SQ-PROMPT", "Hooked Scene_Map#update.")
else
  ##MultiplayerDebug.warn("UI-SQ-PROMPT", "Scene_Map not defined; squad prompts/toasts disabled.")
end
