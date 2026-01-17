# ===========================================
# File: 013_UI_GTS.rb
# Purpose: Simple Global Trading System (GTS) UI over existing TCP
# Notes:
#   - No core edits: only hooks/aliases.
#   - Requires 002_Client.rb with GTS client calls (gts_register/snapshot/list/buy/cancel).
#   - Reuses TradeUI helpers for popups, bag/party, autosave & sprites.
#   - F6 shortcut to open; ESC/BACK to close. (No pause-menu entry.)
#   - Extra hotkeys: U/I/O/J/K/L via Win32API polling on Windows (only while this scene is open).
#   - FIX: Local Pokémon cache so CANCEL always restores the mon even if server omits pokemon_json.
# ===========================================

##MultiplayerDebug.info("UI-GTS", "GTS UI loading...")

module GTSUI
  # ---------------- Colors / Theme (match TradeUI purple) ----------------
  PURPLE_DARK   = Color.new(36,  14,  48)
  PURPLE_MED    = Color.new(62,  24,  92)
  PURPLE_LIGHT  = Color.new(110, 60, 150)
  PURPLE_SCREEN = Color.new(50,  28,  70, 220)
  LAVENDER      = Color.new(200, 180, 230)
  WHITE         = Color.new(255, 255, 255)

  TAB_ITEMS   = 0
  TAB_POKEMON = 1

  # heights
  TITLE_H  = 48
  FOOTER_H = 28
  DESC_H   = 120 # description bar (kept separate from footer)

  # ---------------- Small helpers (delegate to TradeUI where possible) ----------
  def self.pbChooseNumber(caption, max, default_val=0)
    if defined?(TradeUI) && TradeUI.respond_to?(:pbInputNumber)
      return TradeUI.pbInputNumber(caption, max, default_val)
    end
    default_val.to_i
  end

  def self.pbChooseMoney(caption, max, default_val=0)
    if defined?(TradeUI) && TradeUI.respond_to?(:pbInputMoney)
      return TradeUI.pbInputMoney(caption, max, default_val)
    end
    default_val.to_i
  end

  def self.item_name(sym_or_id)
    return TradeUI.item_name(sym_or_id) if defined?(TradeUI) && TradeUI.respond_to?(:item_name)
    sym_or_id.to_s
  end

  def self.item_sym(id)
    return TradeUI.item_sym(id) if defined?(TradeUI) && TradeUI.respond_to?(:item_sym)
    id.to_s.to_sym
  end

  def self.money
    # Use platinum balance instead of PokéDollars
    return MultiplayerPlatinum.cached_balance if defined?(MultiplayerPlatinum)
    0
  end

  def self.has_money?(amt)
    # Use platinum affordability check
    return MultiplayerPlatinum.can_afford?(amt) if defined?(MultiplayerPlatinum)
    false
  end

  def self.add_money(delta)
    # Server handles all platinum changes - this is a no-op for compatibility
    return true
  end

  def self.bag_item_list
    return TradeUI.bag_item_list if defined?(TradeUI) && TradeUI.respond_to?(:bag_item_list)
    []
  end

  def self.bag_has?(sym, qty)
    return TradeUI.bag_has?(sym, qty) if defined?(TradeUI) && TradeUI.respond_to?(:bag_has?)
    false
  end

  def self.bag_can_add?(sym, qty)
    return TradeUI.bag_can_add?(sym, qty) if defined?(TradeUI) && TradeUI.respond_to?(:bag_can_add?)
    true
  end

  def self.bag_add(sym, qty)
    return TradeUI.bag_add(sym, qty) if defined?(TradeUI) && TradeUI.respond_to?(:bag_add)
    false
  end

  def self.bag_remove(sym, qty)
    return TradeUI.bag_remove(sym, qty) if defined?(TradeUI) && TradeUI.respond_to?(:bag_remove)
    false
  end

  def self.party
    return TradeUI.party if defined?(TradeUI) && TradeUI.respond_to?(:party)
    []
  end

  def self.party_count
    return TradeUI.party_count if defined?(TradeUI) && TradeUI.respond_to?(:party_count)
    party.length
  end

  def self.remove_pokemon_at(idx)
    return TradeUI.remove_pokemon_at(idx) if defined?(TradeUI) && TradeUI.respond_to?(:remove_pokemon_at)
    false
  end

  def self.add_pokemon_from_json(poke_hash)
    return TradeUI.add_pokemon_from_json(poke_hash) if defined?(TradeUI) && TradeUI.respond_to?(:add_pokemon_from_json)
    false
  end

  def self.autosave_safely
    return TradeUI.autosave_safely if defined?(TradeUI) && TradeUI.respond_to?(:autosave_safely)
    false
  end

  def self.resolve_species_id(v)
    return TradeUI.resolve_species_id(v) if defined?(TradeUI) && TradeUI.respond_to?(:resolve_species_id)
    v
  end

  # ------- fast direct price input (robust, with fallbacks + logging) -------
  def self.commify(n)
    s = n.to_i.to_s
    s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  def self._try_free_text(prompt, default_str, maxlen)
    text = nil
    begin
      # common signature (prompt, default, password?, maxlen)
      text = pbMessageFreeText(prompt, default_str, false, maxlen) if defined?(pbMessageFreeText)
    rescue => e
      ##MultiplayerDebug.warn("UI-GTS", "pbMessageFreeText 4-arg failed: #{e.message}")
    end
    if text.nil? && defined?(pbMessageFreeText)
      begin
        # some forks use (prompt, default, password?)
        text = pbMessageFreeText(prompt, default_str, false)
      rescue => e
        ##MultiplayerDebug.warn("UI-GTS", "pbMessageFreeText 3-arg failed: #{e.message}")
      end
    end
    if text.nil?
      begin
        # older fallback: pbEnterText(prompt, maxLen)
        text = pbEnterText(prompt, maxlen) if defined?(pbEnterText)
      rescue => e
        ##MultiplayerDebug.warn("UI-GTS", "pbEnterText failed: #{e.message}")
      end
    end
    text
  end

  def self.pbAskPrice(caption, max=999_999, default_val=1000)
    prompt = _INTL("{1}\n(Type digits only, up to {2})", caption, commify(max))
    default_str = default_val.to_i.to_s
    text = _try_free_text(prompt, default_str, 9)

    if text.nil?
      ##MultiplayerDebug.info("UI-GTS", "pbAskPrice: no free-text UI, falling back to picker")
      return GTSUI.pbChooseMoney(caption, max, default_val)
    end

    raw = text.to_s
    amt = raw.gsub(/[^\d]/, "").to_i
    ##MultiplayerDebug.info("UI-GTS", "pbAskPrice: raw='#{raw}' -> amt=#{amt}")

    return nil if amt <= 0
    [[amt, max].min, 0].max
  end

  # -------------- Letter key compatibility for Windows via Win32API --------------
  module KeyCompat
    module_function
    begin
      GetAsyncKeyState = Win32API.new('user32', 'GetAsyncKeyState', ['i'], 'i')
    rescue
      GetAsyncKeyState = nil
    end

    VK = { 'U'=>0x55, 'I'=>0x49, 'O'=>0x4F, 'J'=>0x4A, 'K'=>0x4B, 'L'=>0x4C }

    def letter_trigger?(char)
      code = VK[char.to_s.upcase]
      return false unless code && GetAsyncKeyState
      # low-order bit toggles when key went down since last call (scene is active, so OK)
      (GetAsyncKeyState.call(code) & 0x01) != 0
    rescue
      false
    end
  end

  # ---------------- Scene ----------------
  class Scene_GTS
    def initialize
      @vp = @bg = @panel = nil
      @tab = TAB_ITEMS
      @listings = []
      @rev = 0
      @sel_index = 0
      @scroll = 0
      @uid = nil
      @list_icons = []
      @title_spr = nil
      @footer_spr = nil
      @desc_spr = nil
      @last_refresh_at = 0
      @running = false

      # To apply local inventory mutations after host OK (seller path)
      @pending_list_action = nil  # { kind: "item"/"pokemon", item_sym:, qty:, party_index:, price:, pokemon_json: {} }

      # NEW: local pokemon cache by listing_id -> pokemon_json
      @local_poke_cache = {}  # ensures CANCEL can restore even if server omits pokemon_json
    end

    def main
      setup
      initial_requests
      begin
        loop do
          Graphics.update
          Input.update
          pump_gts_events
          process_toasts  # Show toast messages while in GTS window
          handle_input
          break unless @running
        end
      ensure
        teardown
      end
    end

    # ---------- setup / teardown ----------
    def setup
      @vp = Viewport.new(0,0,Graphics.width,Graphics.height); @vp.z = 99_500

      @bg = Sprite.new(@vp)
      @bg.bitmap = Bitmap.new(Graphics.width, Graphics.height)
      draw_background

      list_h = Graphics.height - TITLE_H - FOOTER_H - DESC_H - 16
      @panel = Sprite.new(@vp)
      @panel.bitmap = Bitmap.new(Graphics.width-32, list_h)
      @panel.x = 16; @panel.y = TITLE_H
      @panel.z = 99_600

      @desc_spr = Sprite.new(@vp)
      @desc_spr.bitmap = Bitmap.new(Graphics.width-32, DESC_H)
      @desc_spr.x = 16
      @desc_spr.y = TITLE_H + list_h
      @desc_spr.z = 99_650
      draw_desc(nil) # empty

      @title_spr = Sprite.new(@vp)
      @title_spr.bitmap = Bitmap.new(Graphics.width, TITLE_H)
      @title_spr.z = 99_700

      @footer_spr = Sprite.new(@vp)
      @footer_spr.bitmap = Bitmap.new(Graphics.width, FOOTER_H)
      @footer_spr.y = Graphics.height - FOOTER_H
      @footer_spr.z = 99_700

      @running = true
      refresh_title
      refresh_footer
      redraw_list
      update_desc_for_selection
    end

    def teardown
      clear_row_icons
      [@desc_spr, @footer_spr, @title_spr, @panel, @bg].compact.each do |s|
        begin
          s.bitmap.dispose if s && s.bitmap && !s.bitmap.disposed?
          s.dispose if s
        rescue; end
      end
      @vp.dispose if @vp
      @vp = nil
    end

    def draw_background
      b = @bg.bitmap
      b.fill_rect(0,0,b.width,b.height, Color.new(10, 5, 16, 220))
      b.fill_rect(0,0,b.width,TITLE_H,PURPLE_LIGHT)
      b.fill_rect(0,TITLE_H,b.width,2,WHITE)
      b.fill_rect(0,Graphics.height-FOOTER_H,b.width,FOOTER_H, PURPLE_LIGHT)
    end

    def refresh_title
      b = @title_spr.bitmap
      b.clear
      b.font.color = WHITE
      b.font.size = 24
      tabs = [(_INTL("Items")), (_INTL("Pokémon"))]
      label = _INTL("Global Trade (GTS) — {1}", tabs[@tab])
      b.draw_text(0, 0, b.width, TITLE_H-2, label, 1)
    end

    def refresh_footer
      b = @footer_spr.bitmap
      b.clear
      b.font.size = 16
      b.font.color = WHITE
      help = _INTL("Q/E : Tabs , W/S : Move , Shift : List , Enter : Interact , F6 : Close")
      b.draw_text(8, 4, b.width-16, FOOTER_H-8, help, 1)
    end

    def draw_desc(text_or_lines)
      b = @desc_spr.bitmap
      b.clear

      # panel
      b.fill_rect(0, 0, b.width, DESC_H, Color.new(15, 8, 24, 230))
      b.fill_rect(0, 0, b.width, 2, PURPLE_LIGHT)

      # title
      b.font.size  = 18
      b.font.color = WHITE
      b.draw_text(8, 6, b.width - 16, 24, (@tab == TAB_ITEMS) ? _INTL("Item") : _INTL("Pokémon"))

      # nothing else to draw?
      return if text_or_lines.nil? || (text_or_lines.is_a?(String) && text_or_lines.empty?)
      
      # body
      b.font.size  = 16
      b.font.color = LAVENDER
      line_h       = 20
      y0           = 28
      max_w        = b.width - 16

      # Accept String (wrap to fit) or Array (draw up to 4 lines as-is)
      lines =
        case text_or_lines
        when Array
          # draw up to 4 provided lines (Moves/IVs/EVs etc.)
          text_or_lines.compact.map(&:to_s)[0, 4]
        else
          # single string (items) — wrap to fit, still cap to 4 lines
          wrap_text(text_or_lines.to_s, b.width - 20, b)[0, 4]
        end

      lines.each_with_index do |ln, i|
        next if ln.nil? || ln.empty?
        b.draw_text(8, y0 + i * line_h, max_w, line_h, ln)
      end
    end


    def wrap_text(text, max_w, bmp)
      words = text.to_s.split(/\s+/)
      lines = []; cur = ""
      words.each do |w|
        test = (cur=="" ? w : "#{cur} #{w}")
        if bmp.text_size(test).width > max_w
          lines << (cur=="" ? w : cur)
          cur = w
        else
          cur = test
        end
      end
      lines << cur unless cur==""
      lines
    end

    # ---------- net ----------
    def initial_requests
      begin
        # GTS registration removed - auto-registers on first use
      rescue => e
        ##MultiplayerDebug.warn("UI-GTS", "gts_register failed: #{e.message}")
      end
      begin
        MultiplayerClient.gts_snapshot(@rev) if MultiplayerClient.respond_to?(:gts_snapshot)
      rescue => e
        ##MultiplayerDebug.warn("UI-GTS", "gts_snapshot failed: #{e.message}")
      end
    end

    def pump_gts_events
    begin
        # Check for disconnection - close GTS window if disconnected
        unless MultiplayerClient.instance_variable_get(:@connected)
          ##MultiplayerDebug.warn("UI-GTS", "Disconnected - closing GTS window")
          @running = false
          return
        end

        while MultiplayerClient.respond_to?(:gts_events_pending?) && MultiplayerClient.gts_events_pending?
        ev = MultiplayerClient.next_gts_event
        # Defensive guards
        unless ev && ev.is_a?(Hash) && ev[:data].is_a?(Hash)
            ##MultiplayerDebug.warn("UI-GTS", "pump: dropped non-hash or nil event: #{ev.inspect rescue 'inspect_failed'}")
            next
        end

        data    = ev[:data] || {}
        act     = (data["action"] || "").to_s
        payload = data["payload"].is_a?(Hash) ? data["payload"] : {}

        case ev[:type]
        when :ok
            # capture uid if present
            @uid ||= payload["uid"] if payload["uid"]

            case act
            when "GTS_REGISTER"
            # nothing
            when "GTS_SNAPSHOT"
            apply_snapshot(payload || {})
            when "GTS_LIST"
            begin
                ##MultiplayerDebug.info("GTS-DBG", "=== GTS_LIST OK (UI) ===")
                ##MultiplayerDebug.info("GTS-DBG", "  Full event: #{ev.inspect}")
                ##MultiplayerDebug.info("GTS-DBG", "  data.keys = #{data.keys.inspect}")
                ##MultiplayerDebug.info("GTS-DBG", "  payload.keys = #{payload.keys.inspect}")
                ##MultiplayerDebug.info("GTS-DBG", "  payload=#{payload.inspect}")

                # Update revision if provided (prevents stale snapshots from overwriting)
                if data["new_rev"]
                  @rev = data["new_rev"].to_i
                  ##MultiplayerDebug.info("GTS-DBG", "  Updated @rev to #{@rev}")
                end

                listing = payload["listing"].is_a?(Hash) ? payload["listing"] : {}
                ##MultiplayerDebug.info("GTS-DBG", "  listing=#{listing.inspect}")
                ##MultiplayerDebug.info("GTS-DBG", "  listing['id']=#{listing['id'].inspect}")

                # Validation: Only process if listing has a valid ID
                if listing["id"] && !listing["id"].to_s.empty?
                  if listing["kind"].to_s == "pokemon" && listing["seller"].to_s == my_uid.to_s
                    if @pending_list_action && @pending_list_action[:kind] == "pokemon" && @pending_list_action[:pokemon_json]
                      @local_poke_cache[listing["id"].to_s] = deep_copy_hash(@pending_list_action[:pokemon_json])
                    end
                  end
                  add_or_replace_listing(listing)
                  apply_local_after_list_ok(listing) if listing["seller"].to_s == my_uid.to_s
                else
                  ##MultiplayerDebug.warn("GTS-DBG", "  Skipping listing with no ID")
                end
            rescue => e
                ##MultiplayerDebug.warn("UI-GTS", "LIST handler error: #{e.class}: #{e.message}\n#{(e.backtrace||[])[0,5].join(' | ')}")
            end
            # DON'T trigger_refresh here - the listing was already added locally above
            # Refreshing now causes a race condition where the snapshot might not include
            # the new listing yet, causing it to disappear from the UI

            when "GTS_CANCEL"
              begin
                # Update revision if provided (prevents stale snapshots from overwriting)
                if data["new_rev"]
                  @rev = data["new_rev"].to_i
                  ##MultiplayerDebug.info("GTS-DBG", "  [CANCEL] Updated @rev to #{@rev}")
                end

                raw_listing = payload["listing"].is_a?(Hash) ? payload["listing"] : {}
                lid = (raw_listing["id"] || payload["listing_id"]).to_s
                if lid.nil? || lid.empty?
                  ##MultiplayerDebug.warn("UI-GTS", "[CANCEL ACK] Missing listing id. payload_keys=#{payload.keys.join(',') rescue 'nil'}")
                  trigger_refresh
                  next
                end

                # UI: Hide the row immediately so the list looks responsive,
                # but DO NOT restore here. Restore happens only on GTS_RETURN (transport).
                ##MultiplayerDebug.info("UI-GTS", "[CANCEL ACK] id=#{lid} (waiting for GTS_RETURN to restore)")
                remove_listing_by_id(lid)
              rescue => e
                ##MultiplayerDebug.warn("UI-GTS", "CANCEL ACK handler error: #{e.class}: #{e.message}\n#{(e.backtrace||[])[0,5].join(' | ')}")
              end
              # DON'T trigger_refresh here - causes race condition where stale snapshot wipes list
              # The periodic auto-refresh will sync with server naturally


            when "GTS_BUY"
            begin
                # Update revision if provided (prevents stale snapshots from overwriting)
                if data["new_rev"]
                  @rev = data["new_rev"].to_i
                  ##MultiplayerDebug.info("GTS-DBG", "  [BUY] Updated @rev to #{@rev}")
                end

                listing = payload["listing"].is_a?(Hash) ? payload["listing"] : {}
                if listing["id"]
                remove_listing_by_id(listing["id"])
                buyer = (payload["buyer"] || my_uid).to_s
                apply_local_after_buy_ok(listing) if buyer == my_uid.to_s
                @local_poke_cache.delete(listing["id"].to_s)
                end
            rescue => e
                ##MultiplayerDebug.warn("UI-GTS", "BUY handler error: #{e.class}: #{e.message}\n#{(e.backtrace||[])[0,5].join(' | ')}")
            end
            # DON'T trigger_refresh here - causes race condition where stale snapshot wipes list
            # The periodic auto-refresh will sync with server naturally
            else
            ##MultiplayerDebug.warn("UI-GTS", "pump: unknown :ok action=#{act}")
            end

        when :err
            msg = (data["msg"] || data["code"] || "GTS error").to_s
            pbMessage(_INTL("GTS: {1}", msg)) rescue nil
        else
            ##MultiplayerDebug.warn("UI-GTS", "pump: unknown event type=#{ev[:type].inspect}")
        end
        end
    rescue => e
        ##MultiplayerDebug.warn("UI-GTS", "pump_gts_events fatal: #{e.class}: #{e.message}\n#{(e.backtrace||[])[0,8].join(' | ')}")
    end
    end

    def process_toasts
      # Process toast messages while in GTS window
      return unless MultiplayerClient.respond_to?(:toast_pending?)
      return unless MultiplayerClient.toast_pending?

      begin
        toast = MultiplayerClient.dequeue_toast
        if toast && toast[:text] && !toast[:text].empty?
          pbMessage(_INTL("{1}", toast[:text]))

          # Clear input after toast to prevent button press from triggering GTS actions
          # The button press that closed the toast shouldn't trigger list navigation/actions
          begin
            Graphics.update
            Input.update
          rescue => e2
            ##MultiplayerDebug.warn("UI-GTS", "Input flush after toast failed: #{e2.message}")
          end
        end
      rescue => e
        ##MultiplayerDebug.warn("UI-GTS", "process_toasts error: #{e.message}")
      end
    end

    def trigger_refresh
      begin
        MultiplayerClient.gts_snapshot(@rev)
      rescue => e
        ##MultiplayerDebug.warn("UI-GTS", "post-mutate snapshot failed: #{e.message}")
      end
    end

    def my_uid
      return MultiplayerClient.platinum_uuid if MultiplayerClient.respond_to?(:platinum_uuid)
      @uid
    end

    def apply_snapshot(payload)
      begin
        old_count = @listings.length
        new_rev = (payload["rev"] || @rev).to_i
        server_listings = payload["listings"].is_a?(Array) ? payload["listings"] : []

        ##MultiplayerDebug.info("GTS-DBG", "apply_snapshot: new_rev=#{new_rev}, current_rev=#{@rev}, server has #{server_listings.length} listings, local has #{old_count}")

        # CRITICAL: Ignore stale snapshots with older revisions
        # This prevents race conditions where a delayed snapshot wipes newer local data
        if new_rev < @rev
          ##MultiplayerDebug.warn("GTS-DBG", "  IGNORING stale snapshot (new_rev=#{new_rev} < current_rev=#{@rev})")
          return
        end

        # CRITICAL: Ignore empty snapshots when we have local listings
        # This prevents server database lag from wiping the UI
        # Only accept empty snapshots if we're at rev 0 (initial load) or already empty
        if server_listings.empty? && old_count > 0 && @rev > 0
          ##MultiplayerDebug.warn("GTS-DBG", "  IGNORING empty snapshot (server has 0, local has #{old_count}, not initial load)")
          return
        end

        @rev = new_rev

        # Build a set of listing IDs from the server snapshot
        server_ids = server_listings.map { |l| l["id"].to_s }.compact

        # Remove local listings that are no longer on the server
        removed = @listings.select { |l| !server_ids.include?(l["id"].to_s) }
        @listings.delete_if { |l| !server_ids.include?(l["id"].to_s) }
        ##MultiplayerDebug.info("GTS-DBG", "  Removed #{removed.length} listings no longer on server")

        # Merge server listings with local listings (server data takes precedence)
        added = 0
        server_listings.each do |listing|
          next unless listing["id"]
          idx = @listings.index { |l| l["id"].to_s == listing["id"].to_s }
          if idx
            @listings[idx] = listing  # Update existing
          else
            @listings << listing      # Add new
            added += 1
          end
        end
        ##MultiplayerDebug.info("GTS-DBG", "  Added #{added} new listings from server. Total now: #{@listings.length}")

        @sel_index = 0 if @sel_index >= @listings.length
        redraw_list
        update_desc_for_selection
      rescue => e
        ##MultiplayerDebug.warn("UI-GTS", "apply_snapshot failed: #{e.message}")
      end
    end

    def add_or_replace_listing(listing)
      # Guard: Skip if listing has no valid ID
      unless listing && listing["id"] && !listing["id"].to_s.empty?
        ##MultiplayerDebug.warn("GTS-DBG", "add_or_replace_listing: Skipping listing with no ID")
        return
      end

      idx = @listings.index { |l| l["id"].to_s == listing["id"].to_s }
      if idx
        @listings[idx] = listing
      else
        @listings << listing
      end
      redraw_list
      update_desc_for_selection
    end

    def remove_listing_by_id(id)
    @listings.delete_if { |l| l["id"].to_s == id.to_s }
    vis = filtered_list
    @sel_index = [[@sel_index, 0].max, [vis.length - 1, 0].max].min
    redraw_list
    update_desc_for_selection
    end


    # ---------- local inventory mutations on OK ----------
    def apply_local_after_list_ok(listing)
      begin
        if listing["kind"].to_s == "item"
          sym = GTSUI.item_sym(listing["item_id"])
          qty = listing["qty"].to_i
          unless GTSUI.bag_remove(sym, qty)
            ##MultiplayerDebug.warn("UI-GTS", "Local bag_remove failed after LIST OK for #{sym} x#{qty}")
          end
        else
          # pokemon: we must remove the one we selected earlier
          if @pending_list_action && @pending_list_action[:kind] == "pokemon"
            idx = @pending_list_action[:party_index].to_i
            unless GTSUI.remove_pokemon_at(idx)
              ##MultiplayerDebug.warn("UI-GTS", "Local remove_pokemon_at(#{idx}) failed after LIST OK")
            end
          end
        end
        GTSUI.autosave_safely
      rescue => e
        ##MultiplayerDebug.warn("UI-GTS", "apply_local_after_list_ok error: #{e.message}")
      ensure
        @pending_list_action = nil
      end
    end

    def apply_local_after_cancel_ok(listing)
      begin
        if listing["kind"].to_s == "item"
          sym = GTSUI.item_sym(listing["item_id"])
          qty = [listing["qty"].to_i, 1].max
          ok  = GTSUI.bag_add(sym, qty)
          ##MultiplayerDebug.info("UI-GTS", "CANCEL item restore #{sym} x#{qty} -> #{ok}")
          GTSUI.autosave_safely
          return
        end

        # --- Pokémon path ---
        pj = listing["pokemon_json"]
        if !pj
          pj = @local_poke_cache[listing["id"].to_s]
          if pj
            ##MultiplayerDebug.info("UI-GTS", "Using local cache for CANCEL of #{listing['id']}")
          else
            ##MultiplayerDebug.warn("UI-GTS", "No pokemon_json from server and no local cache for CANCEL id=#{listing['id']}")
          end
        end

        # Respect Trainer helpers for capacity checks
        party_cnt = (defined?($Trainer) && $Trainer.respond_to?(:party_count)) ? $Trainer.party_count : (GTSUI.party_count rescue -1)
        is_full   = (defined?($Trainer) && $Trainer.respond_to?(:party_full?)) ? $Trainer.party_full? : (party_cnt >= 6)

        if is_full
          ##MultiplayerDebug.info("UI-GTS", "CANCEL mon restore blocked: party_count=#{party_cnt}, full?=#{is_full}")
          pbMessage(_INTL("Could not restore Pokémon to your party.\nMake space and try again."))
          return
        end

        party_before = party_cnt
        ok = pj && GTSUI.add_pokemon_from_json(pj)
        party_after = (defined?($Trainer) && $Trainer.respond_to?(:party_count)) ? $Trainer.party_count : (GTSUI.party_count rescue -1)
        ##MultiplayerDebug.info("UI-GTS", "CANCEL mon restore id=#{listing['id']} party_before=#{party_before} ok=#{ok} party_after=#{party_after}")

        if ok
          @local_poke_cache.delete(listing["id"].to_s)
          GTSUI.autosave_safely
        else
          pbMessage(_INTL("Could not restore Pokémon to your party.\nMake space and try again."))
          ##MultiplayerDebug.warn("UI-GTS", "add_pokemon_from_json failed after CANCEL OK; cache kept for id=#{listing['id']}")
        end
      rescue => e
        ##MultiplayerDebug.warn("UI-GTS", "apply_local_after_cancel_ok error: #{e.class}: #{e.message}")
      end
    end



    def apply_local_after_buy_ok(listing)
      begin
        price = listing["price"].to_i
        GTSUI.add_money(-price) if price > 0
        if listing["kind"].to_s == "item"
          sym = GTSUI.item_sym(listing["item_id"])
          qty = listing["qty"].to_i
          unless GTSUI.bag_add(sym, qty)
            ##MultiplayerDebug.warn("UI-GTS", "Local bag_add failed after BUY OK for #{sym} x#{qty}")
          end
        else
          pj = listing["pokemon_json"]
          unless pj && GTSUI.add_pokemon_from_json(pj)
            ##MultiplayerDebug.warn("UI-GTS", "Local add_pokemon_from_json failed after BUY OK (no pj or add failed)")
          end
        end
        GTSUI.autosave_safely
      rescue => e
        ##MultiplayerDebug.warn("UI-GTS", "apply_local_after_buy_ok error: #{e.message}")
      end
    end

    # ---------- key helpers ----------
    def trig_u?; KeyCompat.letter_trigger?("U"); end
    def trig_i?; KeyCompat.letter_trigger?("I"); end
    def trig_o?; KeyCompat.letter_trigger?("O"); end
    def trig_j?; KeyCompat.letter_trigger?("J"); end
    def trig_k?; KeyCompat.letter_trigger?("K"); end
    def trig_l?; KeyCompat.letter_trigger?("L"); end

    # ---------- input ----------
    def handle_input
      # close (BACK or F6)
      if Input.trigger?(Input::BACK) || (defined?(Input::F6) && Input.trigger?(Input::F6))
        @running = false
        return
      end

      # tabs (U/L or L/R)
      if trig_u? || (defined?(Input::L) && Input.trigger?(Input::L))
        @tab = (@tab == TAB_ITEMS) ? TAB_POKEMON : TAB_ITEMS
        refresh_title
        redraw_list
        update_desc_for_selection
      elsif trig_l? || (defined?(Input::R) && Input.trigger?(Input::R))
        @tab = (@tab == TAB_ITEMS) ? TAB_POKEMON : TAB_ITEMS
        refresh_title
        redraw_list
        update_desc_for_selection
      end

      # actions (I or ACTION)
      if trig_i? || Input.trigger?(Input::ACTION)
        open_actions_menu
        return
      end

      # selection (J/K or Up/Down)
      visible = filtered_list
      if (trig_k? || Input.repeat?(Input::DOWN)) && visible.any?
        @sel_index = [@sel_index + 1, visible.length - 1].min
        ensure_visible_row
        redraw_list
        update_desc_for_selection
      elsif (trig_j? || Input.repeat?(Input::UP)) && visible.any?
        @sel_index = [@sel_index - 1, 0].max
        ensure_visible_row
        redraw_list
        update_desc_for_selection
      end

      # buy/info/cancel (O or USE)
      if (trig_o? || Input.trigger?(Input::USE)) && visible.any?
        entry = visible[@sel_index]
        act_buy_or_info(entry)
      end

      # periodic soft refresh (every ~5s)
      if Graphics.frame_count - @last_refresh_at > (Graphics.frame_rate * 5)
        begin
          MultiplayerClient.gts_snapshot(@rev)
        rescue => e
          ##MultiplayerDebug.warn("UI-GTS", "periodic snapshot failed: #{e.message}")
        end
        @last_refresh_at = Graphics.frame_count
      end
    end

    def open_actions_menu
      cmds = [
        _INTL("List Item"),
        _INTL("List Pokémon"),
        _INTL("Refresh"),
        _INTL("Close"),
      ]
      ch = pbMessage(_INTL("GTS — Choose an action."), cmds, cmds.length - 1)
      case ch
      when 0 then action_list_item
      when 1 then action_list_pokemon
      when 2
        begin; MultiplayerClient.gts_snapshot(@rev); rescue => e
          ##MultiplayerDebug.warn("UI-GTS", "manual refresh failed: #{e.message}")
        end
      when 3 then @running = false
      end
    end

    def filtered_list
      @listings.select { |l| (l["kind"].to_s == (@tab == TAB_ITEMS ? "item" : "pokemon")) }
    end

    def ensure_visible_row
      rows_per = rows_per_page
      top = @scroll
      bot = @scroll + rows_per - 1
      if @sel_index < top
        @scroll = @sel_index
      elsif @sel_index > bot
        @scroll = @sel_index - (rows_per - 1)
      end
      @scroll = 0 if @scroll < 0
    end

    # ---------- list drawing ----------
    def rows_per_page
      ((@panel.bitmap.height - 16) / 48).floor
    end

    def clear_row_icons
      @list_icons.each do |s|
        begin
          if s.is_a?(Array)
            s.each { |spr| spr.dispose if spr }
          else
            s.dispose if s
          end
        rescue; end
      end
      @list_icons.clear
    end

    def redraw_list
    b = @panel.bitmap
    b.clear
    clear_row_icons

    b.font.size = 18
    b.font.color = LAVENDER
    hdr = (@tab == TAB_ITEMS) ? _INTL("Item / Qty / Price / Seller") : _INTL("Pokémon / Lv / Price / Seller")
    b.draw_text(8, 0, b.width-16, 24, hdr)

    vis = filtered_list
    if vis.empty?
        ##MultiplayerDebug.info("GTS-DBG", "redraw_list: filtered_list is EMPTY. @listings.length=#{@listings.length}, tab=#{@tab}")
        @sel_index = 0
        return
    end

    # Clamp selection to filtered list
    @sel_index = [[@sel_index, 0].max, [vis.length - 1, 0].max].min

    per = rows_per_page
    @scroll = [[@scroll, 0].max, [vis.length - per, 0].max].min
    wnd = vis[@scroll, per] || []

    y = 24
    wnd.each_with_index do |entry, idx|
        row_y = y + idx*48
        draw_row(entry, row_y, (idx + @scroll) == @sel_index)
    end
    end


    def draw_row(entry, y, selected)
      b = @panel.bitmap
      w = b.width
      # bg
      if selected
        b.fill_rect(0, y, w, 46, Color.new(255,255,255,24))
      else
        b.fill_rect(0, y, w, 46, Color.new(255,255,255,8))
      end

      price = entry["price"].to_i
      seller = (entry["seller_name"] || entry["seller"] || "-").to_s

      if entry["kind"].to_s == "item"
        # icon
        begin
          icon = ItemIconSprite.new(0,0,nil,@vp)
          icon.setOffset(PictureOrigin::Center)
          icon.x = @panel.x + 24
          icon.y = @panel.y + y + 23
          icon.item = GTSUI.item_sym(entry["item_id"])
          @list_icons << icon
        rescue => e
          ##MultiplayerDebug.warn("UI-GTS", "item icon failed: #{e.message}")
        end

        # name/qty
        b.font.size = 18; b.font.color = WHITE
        b.draw_text(48, y+4, w-56, 20, GTSUI.item_name(entry["item_id"]))
        b.font.size = 16; b.font.color = LAVENDER
        b.draw_text(48, y+24, 120, 18, _INTL("x{1}", entry["qty"].to_i))
      else
        begin
          pj = entry["pokemon_json"] || {}
          species = nil; gender=0; form=0; shiny=false
          begin; species = GTSUI.resolve_species_id(pj["species"]); rescue; end
          begin; gender  = pj["gender"].to_i; rescue; end
          begin; form    = pj["form"].to_i;   rescue; end
          # Accept multiple shiny flags used by KIF
          shiny = !!(pj["shiny"] || pj["head_shiny"] || pj["body_shiny"] || pj["fakeshiny"])

          picon = PokemonSpeciesIconSprite.new(species, @vp)
          picon.setOffset(PictureOrigin::Center)
          picon.pbSetParams(species, gender, form, shiny)
          picon.x = @panel.x + 24
          picon.y = @panel.y + y + 23
          @list_icons << picon

          name = pj["name"].to_s
          if name.to_s == "" && defined?(GameData::Species) && species
            begin; name = GameData::Species.get(species).name; rescue; name = "Pokémon"; end
          end
          lvl  = 0; begin; lvl = pj["level"].to_i; rescue; end
          b.font.size = 18; b.font.color = WHITE
          b.draw_text(48, y+4, w-56, 20, name)
          b.font.size = 16; b.font.color = LAVENDER
          b.draw_text(48, y+24, 120, 18, _INTL("Lv.{1}", lvl))
        rescue => e
          ##MultiplayerDebug.warn("UI-GTS", "pokemon row failed: #{e.message}")
        end
      end

      # price (right), seller (center/right)
      # Draw platinum icon + amount
      icon_size = 16
      text_x_offset = w - 8
      icon_loaded = false

      # Try to load platinum icon
      begin
        if pbResolveBitmap("Graphics/Pictures/Trainer Card/platinum_icon")
          icon_bitmap = RPG::Cache.load_bitmap("Graphics/Pictures/Trainer Card/", "platinum_icon")
          src_rect = Rect.new(0, 0, icon_bitmap.width, icon_bitmap.height)
          dest_rect = Rect.new(text_x_offset - icon_size - 2, y + 6, icon_size, icon_size)
          b.stretch_blt(dest_rect, icon_bitmap, src_rect)
          icon_loaded = true
        elsif pbResolveBitmap("Graphics/Pictures/platinum")
          icon_bitmap = RPG::Cache.load_bitmap("Graphics/Pictures/", "platinum")
          src_rect = Rect.new(0, 0, icon_bitmap.width, icon_bitmap.height)
          dest_rect = Rect.new(text_x_offset - icon_size - 2, y + 6, icon_size, icon_size)
          b.stretch_blt(dest_rect, icon_bitmap, src_rect)
          icon_loaded = true
        end
      rescue => e
        # Fallback to "Pt" text
      end

      # Draw price with dynamic scaling
      price_text = price.to_s_formatted
      b.font.size = 18
      text_size = b.text_size(price_text)
      text_width = text_size.width
      max_width = w - 8 - (icon_loaded ? icon_size + 4 : 24)

      # Scale down if too wide
      if text_width > max_width
        scale_factor = max_width.to_f / text_width
        b.font.size = (18 * scale_factor).to_i
        b.font.size = [b.font.size, 10].max
        text_size = b.text_size(price_text)
        text_width = text_size.width
      end

      b.font.color = WHITE
      price_x = text_x_offset - text_width - (icon_loaded ? icon_size + 4 : 24)
      b.draw_text(price_x, y+6, text_width, 20, price_text)

      # Draw "Pt" if icon not loaded
      unless icon_loaded
        b.font.size = 14
        b.draw_text(price_x + text_width + 2, y+8, 20, 16, "Pt")
      end

      b.font.size = 14; b.font.color = LAVENDER
      b.draw_text(0, y+24, w-8, 18, seller, 2)
    end

    # ---------- description ----------
    def update_desc_for_selection
      vis = filtered_list
      if vis.empty?
        @sel_index = 0
        draw_desc([])               # clear desc
        return
      end

      # Clamp selection to filtered list
      @sel_index = [[@sel_index, 0].max, [vis.length - 1, 0].max].min
      entry = vis[@sel_index]
      unless entry
        draw_desc([])               # clear desc
        return
      end

      if entry["kind"].to_s == "item"
        # draw one line for items
        draw_desc([item_description(entry["item_id"])])
      else
        # draw 4 lines for Pokémon
        draw_desc(pokemon_short_lines(entry["pokemon_json"]))
      end
    end



    def item_description(item_id)
      begin
        if defined?(GameData::Item)
          sym = GTSUI.item_sym(item_id)
          return GameData::Item.get(sym).description.to_s
        end
      rescue; end
      ""
    end
    # Returns 4 strings ready to draw on the description panel.
    def pokemon_short_lines(pj)
      pj ||= {}
      pkm = nil
      begin
        pkm = build_temp_pokemon_from_json(pj)
      rescue
        pkm = nil
      end

      # --- Basics ---
      lvl = (pkm && pkm.respond_to?(:level) ? pkm.level : pj["level"]).to_i

      # Nature
      nature_str =
        begin
          if pkm && pkm.respond_to?(:nature) && pkm.nature
            pkm.nature.name.to_s
          else
            raw = pj["nature"] || pj[:nature] || pj["nature_for_stats"] || pj[:nature_for_stats]
            if defined?(GameData::Nature) && raw
              GameData::Nature.get(raw).name.to_s
            else
              raw.to_s
            end
          end
        rescue
          ""
        end
      nature_str = "-" if nature_str.nil? || nature_str.empty?

      # Ability
      ability_str =
        begin
          if pkm && pkm.respond_to?(:ability) && pkm.ability
            pkm.ability.name.to_s
          else
            raw = pj["ability"] || pj[:ability] || pj["ability_index"] || pj[:ability_index]
            if defined?(GameData::Ability) && !raw.to_s.empty?
              GameData::Ability.get(raw).name.to_s
            else
              raw.to_s
            end
          end
        rescue
          ""
        end
      ability_str = "-" if ability_str.nil? || ability_str.empty?

      # --- Shiny type (No | Natural | Debug | Fake) ---
      shiny_type = shiny_label_from(pkm, pj)  # uses your helpers via a temp Pokémon

      # --- Moves (up to 4) ---
      move_names = []
      begin
        if pkm && pkm.respond_to?(:moves)
          move_names = pkm.moves.map { |m| (m && m.name) ? m.name.to_s : nil }.compact
        else
          arr = pj["moves"] || pj[:moves]
          if arr.is_a?(Array)
            move_names = arr.map do |m|
              id =
                if m.is_a?(Hash)
                  m["id"] || m[:id] || m["move"] || m[:move] || m["name"] || m[:name]
                else
                  m
                end
              next if id.nil?
              begin
                if defined?(GameData::Move)
                  GameData::Move.get(id).name.to_s
                else
                  id.to_s
                end
              rescue
                id.to_s
              end
            end.compact
          end
        end
      rescue
      end
      moves_str = move_names[0, 4].join("/") ; moves_str = "-" if moves_str.empty?

      # --- IVs / EVs in HP/Atk/Def/SpA/SpD/Spe order ---
      order = [:HP, :ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED]

      iv_map = nil
      ev_map = nil
      begin
        if pkm && pkm.respond_to?(:iv) && pkm.respond_to?(:ev)
          iv_map = pkm.iv
          ev_map = pkm.ev
        else
          piv = pj["iv"] || pj[:iv]
          pev = pj["ev"] || pj[:ev]
          if piv.is_a?(Hash)
            iv_map = {}
            piv.each { |k, v| iv_map[k.to_s.upcase.to_sym] = v.to_i }
          end
          if pev.is_a?(Hash)
            ev_map = {}
            pev.each { |k, v| ev_map[k.to_s.upcase.to_sym] = v.to_i }
          end
        end
      rescue
      end

      fmt_stats = proc do |map|
        unless map.is_a?(Hash)
          "-"
        else
          order.map { |k| (map[k] || 0).to_i }.join("/")
        end
      end

      ivs_str = fmt_stats.call(iv_map)
      evs_str = fmt_stats.call(ev_map)

      line1 = _INTL("Lv.{1}  Nature: {2}  Ability: {3}  Shiny: {4}", lvl, nature_str, ability_str, shiny_type)
      line2 = _INTL("Moves: {1}", moves_str)
      line3 = _INTL("IVs {1}", ivs_str)
      line4 = _INTL("EVs {1}", evs_str)
      [line1, line2, line3, line4]
    end




    # ---------- actions ----------
    def act_buy_or_info(entry)
      is_mine = false
      begin
        if MultiplayerClient.respond_to?(:platinum_uuid) && MultiplayerClient.platinum_uuid
          is_mine = (entry["seller"].to_s == MultiplayerClient.platinum_uuid.to_s)
        end
      rescue; end

      if is_mine
        do_cancel = false
        begin
          do_cancel = TradeUI.selfpbConfirm(_INTL("Cancel this listing?"))
        rescue
          do_cancel = false
        end
        if do_cancel
          # --- PRECHECK: ensure we can restore locally before contacting server ---
          if entry["kind"].to_s == "pokemon"
            # Party must have space for restoration
            if GTSUI.party_count >= 6
              pbMessage(_INTL("Your party is full.\nFree a slot before canceling this listing."))
              return
            end
          else
            # Item: bag must be able to accept the quantity
            sym = GTSUI.item_sym(entry["item_id"])
            qty = entry["qty"].to_i
            unless GTSUI.bag_can_add?(sym, qty)
              pbMessage(_INTL("Your bag is full.\nMake space before canceling this listing."))
              return
            end
          end

          # Passed prechecks — safe to ask the server to cancel now
          begin
            MultiplayerClient.gts_cancel(entry["id"].to_s)
          rescue => e
            ##MultiplayerDebug.warn("UI-GTS", "gts_cancel failed: #{e.message}")
          end
        end
        return
      end


      if entry["kind"].to_s == "pokemon"
        cmds = [_INTL("Buy"), _INTL("Info"), _INTL("Cancel")]
        choice = -1

        begin
          if defined?(TradeUI) && TradeUI.respond_to?(:selfpbShowCommands)
            # This path already returns -1 on ESC, so no fixup needed.
            choice = TradeUI.selfpbShowCommands(cmds, 2, 2)
          else
            # Centered dialog; default = Cancel (index 2)
            raw = pbMessage(_INTL("Choose an action."), cmds, 2)

            # --- Key fix: if ESC/B was the last key used to close the window,
            # treat it as cancel NO MATTER what pbMessage returned.
            if (defined?(Input::BACK) && (Input.trigger?(Input::BACK) || Input.press?(Input::BACK))) ||
              (defined?(Input::B)    && (Input.trigger?(Input::B)    || Input.press?(Input::B)))
              choice = -1
            else
              choice = raw
            end
          end
        rescue
          choice = -1
        ensure
          # small debounce so no key bleeds into the next frame
          begin; Graphics.update; Input.update; rescue; end
        end

        case choice
        when 0 then do_buy_listing(entry)
        when 1 then show_pokemon_info(entry["pokemon_json"])
        else
          # cancel -> do nothing
        end
      else
        # Items: just confirm buy
        do_buy_listing(entry)
      end
    end


    def do_buy_listing(entry)
      price = entry["price"].to_i
      unless GTSUI.has_money?(price)
        pbMessage(_INTL("Not enough Platinum!"))
        return
      end
      do_buy = false
      begin
        do_buy = TradeUI.selfpbConfirm(_INTL("Buy for ${1}?", price))
      rescue
        do_buy = false
      end
      if do_buy
        begin
          MultiplayerClient.gts_buy(entry["id"].to_s)
        rescue => e
          ##MultiplayerDebug.warn("UI-GTS", "gts_buy failed: #{e.message}")
        end
      end
    end

    # Build a temporary Pokemon from a JSON hash (for Summary screen).
    def build_temp_pokemon_from_json(pj)
      return nil unless pj && defined?(Pokemon)
      begin
        # Minimal safety: ensure stat maps are complete if helper exists
        TradeUI.ensure_complete_stat_maps!(pj) if defined?(TradeUI) && TradeUI.respond_to?(:ensure_complete_stat_maps!)
        sid   = GTSUI.resolve_species_id(pj["species"])
        level = [(pj["level"] || 1).to_i, 1].max
        p = Pokemon.new(sid, level)
        p.load_json(pj)
        # KIF: force species id if needed
        TradeUI.force_species_id!(p) if defined?(TradeUI) && TradeUI.respond_to?(:force_species_id!)
        return p
      rescue => e
        ##MultiplayerDebug.warn("UI-GTS", "build_temp_pokemon_from_json failed: #{e.message}")
        return nil
      end
    end

    def show_pokemon_info(pj)
      p = build_temp_pokemon_from_json(pj)
      if p.nil?
        pbMessage(_INTL("Can't show info for this Pokémon."))
        return
      end
      # Summary screen (single-entry array)
      begin
        if defined?(PokemonSummary_Scene) && defined?(PokemonSummaryScreen)
          pbFadeOutIn {
            scene  = PokemonSummary_Scene.new
            screen = PokemonSummaryScreen.new(scene)
            screen.pbStartScreen([p], 0)  # behaves like party Summary, shows IV/EV tabs etc.
          }
        else
          # Fallback: compact info
          ivs = p.iv
          evs = p.ev
          lines = []
          lines << _INTL("{1}  Lv.{2}", p.name, p.level)
          lines << _INTL("Nature: {1}  Ability: {2}", p.nature.name, p.ability.name)
          lines << _INTL("IVs  HP {1} / Atk {2} / Def {3}", ivs[:HP], ivs[:ATTACK], ivs[:DEFENSE])
          lines << _INTL("     SpA {1} / SpD {2} / Spe {3}", ivs[:SPECIAL_ATTACK], ivs[:SPECIAL_DEFENSE], ivs[:SPEED])
          lines << _INTL("EVs  HP {1} / Atk {2} / Def {3}", evs[:HP], evs[:ATTACK], evs[:DEFENSE])
          lines << _INTL("     SpA {1} / SpD {2} / Spe {3}", evs[:SPECIAL_ATTACK], evs[:SPECIAL_DEFENSE], evs[:SPEED])
          pbMessage(lines.join("\n"))
        end
      rescue => e
        ##MultiplayerDebug.warn("UI-GTS", "Summary display failed: #{e.message}")
        pbMessage(_INTL("Error opening summary."))
      end
    end

    def action_list_item
      list = GTSUI.bag_item_list
      if list.empty?
        pbMessage(_INTL("You don't have any items suitable for listing."))
        return
      end
      labels = list.map { |sym, q| "#{GTSUI.item_name(sym)} x#{q}" } + [_INTL("Cancel")]
      sel = pbMessage(_INTL("Pick an item to list."), labels, labels.length-1)
      return if sel < 0 || sel >= list.length
      sym, have = list[sel]
      max_q = [have.to_i, 999].min
      qty = GTSUI.pbChooseNumber(_INTL("Quantity to list (max {1})", max_q), max_q, 1)
      return if !qty || qty <= 0
      price = GTSUI.pbAskPrice(_INTL("Set price (Platinum)"), 999_999, 100)
      return if !price || price <= 0
      begin
        @pending_list_action = { kind: "item", item_sym: sym, qty: qty, price: price }
        MultiplayerClient.gts_list_item(sym.to_s, qty, price)
      rescue => e
        ##MultiplayerDebug.warn("UI-GTS", "gts_list_item failed: #{e.message}")
        @pending_list_action = nil
      end
    end
    # Classify shiny type using only payload flags (no side-effects).
    # Returns "No", "Natural", "Debug", or "Fake".
    def shiny_label_from(pkm, pj)
      pj ||= {}

      # 1) Is it shiny at all?
      is_shiny = !!(
        pj["shiny"] || pj[:shiny] ||
        pj["head_shiny"] || pj[:head_shiny] ||
        pj["body_shiny"] || pj[:body_shiny] ||
        pj["natural_shiny"] || pj[:natural_shiny] ||
        pj["fakeshiny"] || pj[:fakeshiny] ||
        pj["debug_shiny"] || pj[:debug_shiny]
      )

      return "No" unless is_shiny

      # 2) Type precedence
      fake    = !!(pj["fakeshiny"]      || pj[:fakeshiny])
      natural = !!(pj["natural_shiny"]  || pj[:natural_shiny])
      head    = !!(pj["head_shiny"]     || pj[:head_shiny])
      body    = !!(pj["body_shiny"]     || pj[:body_shiny])
      dbgflag = !!(pj["debug_shiny"]    || pj[:debug_shiny])

      return "Fake"    if fake
      return "Natural" if natural
      return "Debug"   if head || body || dbgflag

      # Fallback: shiny with no subtype flags → treat as Natural
      "Natural"
    end




    def action_list_pokemon
      party = GTSUI.party
      if party.length <= 1
        pbMessage(_INTL("You must keep at least one Pokémon."))
        return
      end
      names = party.each_with_index.map { |pk,i|
        (pk.respond_to?(:name) && pk.respond_to?(:level)) ? _INTL("{1}  Lv.{2}", pk.name, pk.level) : _INTL("Slot {1}", i+1)
      }
      sel = pbMessage(_INTL("Pick a Pokémon to list."), names + [_INTL("Cancel")], names.length)
      return if sel < 0 || sel >= names.length
      if party.length <= 1
        pbMessage(_INTL("You must keep at least one Pokémon."))
        return
      end
      pk = party[sel]
      pj = nil
      begin
        pj = pk.to_json
        TradeUI.ensure_complete_stat_maps!(pj) if defined?(TradeUI)
      rescue
        pbMessage(_INTL("This Pokémon cannot be serialized."))
        return
      end
      price = GTSUI.pbAskPrice(_INTL("Set price (Platinum)"), 999_999, 1000)
      return if !price || price <= 0
      begin
        # keep the JSON so we can seed cache on LIST OK (when server returns id)
        @pending_list_action = { kind: "pokemon", party_index: sel, price: price, pokemon_json: pj }
        MultiplayerClient.gts_list_pokemon(pj, price)
      rescue => e
        ##MultiplayerDebug.warn("UI-GTS", "gts_list_pokemon failed: #{e.message}")
        @pending_list_action = nil
      end
    end

    # ---------- tiny utility ----------
    # Deep copy a hash without using Marshal (security: avoid deserializing untrusted data)
    def deep_copy_hash(h)
      return nil unless h.is_a?(Hash)
      # Use JSON round-trip for safe deep copy
      if defined?(MiniJSON)
        MiniJSON.parse(MiniJSON.dump(h))
      else
        # Manual fallback
        deep_copy_recursive(h)
      end
    rescue
      # Manual fallback if JSON fails
      deep_copy_recursive(h)
    end

    def deep_copy_recursive(obj)
      case obj
      when Hash
        out = {}
        obj.each { |k, v| out[k] = deep_copy_recursive(v) }
        out
      when Array
        obj.map { |e| deep_copy_recursive(e) }
      else
        # Primitives (String, Integer, etc.) - return as-is (immutable or copied by value)
        obj
      end
    end
  end

  # ---------------- Public open helper ----------------
  def self.open
    unless MultiplayerClient && MultiplayerClient.instance_variable_get(:@connected)
      pbMessage(_INTL("You are not connected to any server."))
      return
    end
    scene = Scene_GTS.new
    scene.main
  end

  # ---------------- Scene_Map hook: optional open shortcut + event pump ----------
  def self.tick_open_shortcut
    begin
      return unless defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:players)
      return unless MultiplayerClient.session_id
      if defined?(Input::F6) && Input.trigger?(Input::F6)
        GTSUI.open
      end
    rescue => e
      ##MultiplayerDebug.warn("UI-GTS", "tick_open_shortcut error: #{e.message}")
    end
  end

  def self.tick_gts_events_only
    begin
      # GTS registration removed - auto-registers on first listing

      # Do NOT drain events here.
    rescue => e
      ##MultiplayerDebug.warn("UI-GTS", "tick_gts_events_only error: #{e.message}")
    end
  end
end   # <-- CLOSES module GTSUI



# ---------- Hook Scene_Map update (non-invasive) ----------
if defined?(Scene_Map)
  class ::Scene_Map
    alias kif_gts_update update unless method_defined?(:kif_gts_update)
    def update
      kif_gts_update
      GTSUI.tick_open_shortcut
      GTSUI.tick_gts_events_only
    end
  end
  ##MultiplayerDebug.info("UI-GTS", "Hooked Scene_Map#update for GTS (shortcut + event pump).")
else
  ##MultiplayerDebug.warn("UI-GTS", "Scene_Map not found; GTS hook inactive.")
end

##MultiplayerDebug.info("UI-GTS", "GTS UI loaded (F6 open; U/I/O/J/K/L hotkeys; item desc + Pokémon summary; safe cancel restore).")
