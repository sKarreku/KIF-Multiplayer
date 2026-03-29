#===============================================================================
# STABILITY MODULE 7: COOP_BATTLE_END Relay
#===============================================================================
# Problem: When battle ends, each client independently calls end_battle().
#          Server clears battle slot on first COOP_BATTLE_END but doesn't
#          relay to other clients. If one client finishes faster, a new
#          encounter can start before the slower client has finished.
#
# Solution:
#   - Client: Send COOP_BATTLE_END on battle end (patched into CoopBattleState)
#   - Server: Relay COOP_BATTLE_END to squad (see server.rb changes)
#   - Client: Handle received COOP_BATTLE_END (listener handler in 002_Client.rb)
#
# This file handles the CLIENT-SIDE changes only.
# Server changes are in server.rb (separate file).
#===============================================================================

#===============================================================================
# Patch CoopBattleState.end_battle to send COOP_BATTLE_END
#===============================================================================
if defined?(CoopBattleState)
  module CoopBattleState
    class << self
      alias _end_battle_before_relay end_battle

      def end_battle
        # Send COOP_BATTLE_END to server BEFORE cleanup
        # This ensures the server can relay to allies while we're still in a known state
        if @current_battle_id && defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:send_data)
          begin
            connected = MultiplayerClient.instance_variable_get(:@connected) rescue false
            if connected
              MultiplayerClient.send_data("COOP_BATTLE_END:#{@current_battle_id}")
              StabilityDebug.info("BATTLE-END", "Sent COOP_BATTLE_END for battle #{@current_battle_id}") if defined?(StabilityDebug)
            end
          rescue => e
            StabilityDebug.error("BATTLE-END", "Failed to send COOP_BATTLE_END: #{e.class}: #{e.message}") if defined?(StabilityDebug)
          end
        end

        # Call original end_battle
        _end_battle_before_relay
      end
    end
  end

  StabilityDebug.info("BATTLE-END", "Patched CoopBattleState.end_battle with COOP_BATTLE_END relay") if defined?(StabilityDebug)
end

#===============================================================================
# Client-side handler for received COOP_BATTLE_END from ally
# This is informational - our own battle end is handled locally.
# The main benefit: we know the ally finished, so we can safely
# extend the encounter guard cooldown if needed.
#===============================================================================
# NOTE: This handler needs to be registered in the listener thread.
# Since we can't easily patch the listener's if/elsif chain from outside,
# we store a flag and let the existing dispatch check for it.
# The actual handler registration happens in the listener thread's message
# processing. For now, we define the handler method that the listener can call.

if defined?(MultiplayerClient)
  class << MultiplayerClient
    def _handle_coop_battle_end_relay(from_sid, battle_id = nil)
      StabilityDebug.info("BATTLE-END", "Received COOP_BATTLE_END from ally #{from_sid} (battle: #{battle_id})") if defined?(StabilityDebug)

      # If we're still in an active battle, this is just informational
      if defined?(CoopBattleState) && CoopBattleState.active?
        StabilityDebug.info("BATTLE-END", "We're still in battle - ally #{from_sid} finished first") if defined?(StabilityDebug)
      end

      # If we already finished our battle, refresh the cooldown
      if defined?(CoopEncounterGuard) && !CoopEncounterGuard.instance_variable_get(:@suppressed)
        CoopEncounterGuard.unsuppress!  # Refreshes cooldown timer
        StabilityDebug.info("BATTLE-END", "Refreshed encounter cooldown from ally battle end") if defined?(StabilityDebug)
      end
    end
  end
end

StabilityDebug.info("BATTLE-END", "Module 907_BattleEndRelay loaded") if defined?(StabilityDebug)
