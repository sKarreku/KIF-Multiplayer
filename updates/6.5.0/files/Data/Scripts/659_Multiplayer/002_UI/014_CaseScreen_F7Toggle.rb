# ===========================================
# File: 014_CaseScreen_F7Toggle.rb
# Purpose: Open the Case Screen on F7 (connected players, overworld only)
# Pattern mirrors 003_Trading/002_GTSUI.rb tick_open_shortcut exactly.
# ===========================================

module KIFCasesF7Toggle
  def self.tick_open_shortcut
    begin
      return unless defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:session_id)
      return unless MultiplayerClient.session_id
      return unless defined?(Input::F7) && Input.trigger?(Input::F7)

      if KIFCases.screen_open?
        KIFCases.request_close
      else
        KIFCases::CaseSelectScreen.open
      end
    rescue => e
    end
  end
end

# ---------- Hook Scene_Map update (non-invasive) ----------
if defined?(Scene_Map)
  class ::Scene_Map
    alias kif_cases_f7_update update unless method_defined?(:kif_cases_f7_update)
    def update
      kif_cases_f7_update
      KIFCasesF7Toggle.tick_open_shortcut
    end
  end
end
