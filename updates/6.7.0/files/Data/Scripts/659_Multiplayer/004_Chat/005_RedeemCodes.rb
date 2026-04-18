#===============================================================================
# Chat Redeem Code System (Client Stub)
# File: 659_Multiplayer/004_Chat/005_RedeemCodes.rb
#
# Players type "/redeem CODE" in chat. The client sends the request to the
# server, which owns the code registry, validates Discord linking, checks
# expiry / one-time-per-Discord-ID, and grants rewards (platinum, items).
#
# Client only sends: REDEEM_CODE:<code_name>
# Server replies:    REDEEM_OK:<message>  or  REDEEM_FAIL:<message>
#===============================================================================

module RedeemCodes
  # Send a redeem request to the server.
  def self.redeem(code_name)
    code_name = code_name.to_s.strip.upcase

    unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
      _sys_msg("You must be connected to multiplayer to redeem codes.")
      return
    end

    if code_name.empty?
      _sys_msg("Usage: /redeem CODE_NAME")
      return
    end

    MultiplayerClient.send_data("REDEEM_CODE:#{code_name}")
    _sys_msg("Redeeming code '#{code_name}'...")
  end

  def self._sys_msg(text)
    if defined?(ChatMessages)
      ChatMessages.add_message("Global", "SYSTEM", "System", text)
    end
  end
end
