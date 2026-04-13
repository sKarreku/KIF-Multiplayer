#===============================================================================
# MODULE: Ping Display UI - Ping helper for player list grid
#===============================================================================
# Provides ping lookup used by PlayerListGrid cells.
# The old openPlayerList override is removed — the new grid UI in
# 002_PlayerList.rb handles everything, including ping display.
#===============================================================================

module MultiplayerUI
  # Get formatted ping string for a SID
  def self.ping_text_for(sid)
    return nil unless defined?(PingTracker)
    ping = PingTracker.get_ping(sid) rescue 0
    ping > 0 ? "#{ping}ms" : nil
  end
end

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("PING-UI", "Ping display helper loaded")
end
