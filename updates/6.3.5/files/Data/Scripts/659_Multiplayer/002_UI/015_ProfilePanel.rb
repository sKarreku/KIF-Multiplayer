# ===========================================
# File: 015_ProfilePanel.rb
# Purpose: Floating centered profile overlay panel.
#          Shows stats, title, and sprite for any player (own or others).
#          Toggled with F8; also opened from the Player List.
#          Non-blocking overlay — drawn every frame via Scene_Map hook.
# ===========================================

if defined?(Scene_Map)

  module MultiplayerUI
    module ProfilePanel

      # ── Panel dimensions ─────────────────────────────────────────
      PANEL_W   = 270
      PANEL_H   = 230
      SPRITE_W  = 32
      SPRITE_H  = 48

      # ── State ────────────────────────────────────────────────────
      @open          = false
      @loading       = false
      @target_uuid   = nil   # UUID of the profile being shown
      @data          = nil   # Last received PROFILE_DATA hash
      @request_time  = nil   # Time.now when request was sent
      @fetch_time    = nil   # Time when PROFILE_DATA was received
      REQUEST_TIMEOUT = 4.0  # seconds before showing "No response"

      # Sprite resources (created on first open, disposed on panel close)
      @viewport      = nil
      @panel_spr     = nil
      @sprite_bmp    = nil   # trainer sprite bitmap (static frame)

      # Title animation (gradient phase)
      @title_phase   = 0.0

      # ── Public API ───────────────────────────────────────────────

      def self.open?; @open; end

      # Open the panel targeting a specific UUID ("self" or a platinum_uuid).
      def self.open(uuid: "self")
        return unless defined?(MultiplayerClient) && MultiplayerClient.session_id
        return if ($game_temp&.in_battle rescue false)
        return if ($game_temp&.in_menu   rescue false)

        uuid = MultiplayerClient.platinum_uuid || "self" if uuid == "self" || uuid.to_s.empty?

        @target_uuid  = uuid.to_s
        @open         = true
        @loading      = true
        @data         = nil
        @request_time = Time.now
        @fetch_time   = nil
        @title_phase  = 0.0
        _dispose_sprite_bmp

        MultiplayerClient.request_profile(@target_uuid)
        _ensure_viewport
        _redraw
      end

      def self.close
        @open    = false
        @loading = false
        @data    = nil
        _dispose_panel
      end

      def self.toggle(uuid: "self")
        if @open && @target_uuid == (uuid == "self" ? (MultiplayerClient.platinum_uuid || "self") : uuid)
          close
        else
          close  # close any existing panel first
          open(uuid: uuid)
        end
      end

      # Called every frame from Scene_Map.update hook.
      def self.tick
        return unless @open

        # Poll for PROFILE_DATA response
        if @loading
          pd = MultiplayerClient.pop_profile_data rescue nil
          if pd.is_a?(Hash)
            @data       = pd
            @loading    = false
            @fetch_time = Time.now
            _dispose_sprite_bmp
            _build_sprite_bmp(@data["sprite_data"])
            _redraw
          elsif @request_time && (Time.now - @request_time) > REQUEST_TIMEOUT
            @loading = false  # Show timeout state
            _redraw
          end
        end

        # Advance gradient animation (if title present with gradient effect)
        td = @data && @data["active_title"]
        if td.is_a?(Hash) && (td["effect"] == "gradient" || td["effect"] == "tricolor")
          speed = (td["speed"] || 0.3).to_f
          @title_phase += speed / 60.0
          _redraw  # redraw each frame for animation (cheap since it's just text)
        end

        # Change Title button — Z/C key, only on own profile
        if !@loading && @data
          my_uuid = (MultiplayerClient.platinum_uuid rescue nil)
          if my_uuid && @target_uuid == my_uuid && Input.trigger?(Input::C)
            _handle_change_title
          end
        end

        # Guard: close if we go into battle or menu
        if ($game_temp&.in_battle rescue false) || ($game_temp&.in_menu rescue false)
          close
        end
      end

      # ── Private ──────────────────────────────────────────────────

      def self._ensure_viewport
        return if @viewport && !@viewport.disposed?
        @viewport   = Viewport.new(0, 0, Graphics.width, Graphics.height)
        @viewport.z = 99_400
      end

      def self._dispose_panel
        begin
          if @panel_spr && !@panel_spr.disposed?
            @panel_spr.bitmap.dispose rescue nil
            @panel_spr.dispose
          end
        rescue; end
        begin
          @viewport.dispose if @viewport && !@viewport.disposed?
        rescue; end
        @panel_spr = nil
        @viewport  = nil
        _dispose_sprite_bmp
      end

      def self._dispose_sprite_bmp
        begin
          @sprite_bmp.dispose if @sprite_bmp && !@sprite_bmp.disposed?
        rescue; end
        @sprite_bmp = nil
      end

      # Try to build a trainer sprite bitmap from sprite_data hash.
      def self._build_sprite_bmp(sd)
        return unless sd.is_a?(Hash) && defined?(generateClothedBitmapStatic) && defined?(RemoteTrainer)
        remote_trainer = RemoteTrainer.new(
          (sd["clothes"] || "001").to_s,
          (sd["hat"]     || "000").to_s,
          (sd["hair"]    || "000").to_s,
          sd["skin_tone"].to_i,
          sd["hair_color"].to_i,
          sd["hat_color"].to_i,
          sd["clothes_color"].to_i
        )
        @sprite_bmp = generateClothedBitmapStatic(remote_trainer, "walk")
      rescue => e
        ##MultiplayerDebug.warn("PROFILE-PANEL", "Sprite build failed: #{e.message}")
        @sprite_bmp = nil
      end

      # Draw (or redraw) the full panel bitmap.
      def self._redraw
        return unless @viewport && !@viewport.disposed?

        sw = Graphics.width
        sh = Graphics.height
        px = (sw - PANEL_W) / 2
        py = (sh - PANEL_H) / 2

        if @panel_spr.nil? || @panel_spr.disposed?
          @panel_spr   = Sprite.new(@viewport)
          @panel_spr.x = px
          @panel_spr.y = py
          @panel_spr.z = 100
        end

        if @panel_spr.bitmap.nil? || @panel_spr.bitmap.disposed? ||
           @panel_spr.bitmap.width != PANEL_W || @panel_spr.bitmap.height != PANEL_H
          @panel_spr.bitmap.dispose rescue nil
          @panel_spr.bitmap = Bitmap.new(PANEL_W, PANEL_H)
        else
          @panel_spr.bitmap.clear
        end

        bmp = @panel_spr.bitmap

        # ── Background ───────────────────────────────────────────
        bg_color  = Color.new(15, 10, 25, 210)    # dark purple-black
        brd_color = Color.new(130, 70, 200, 220)   # violet border
        bmp.fill_rect(0, 0, PANEL_W, PANEL_H, brd_color)
        bmp.fill_rect(2, 2, PANEL_W - 4, PANEL_H - 4, bg_color)

        # ── Header bar ───────────────────────────────────────────
        hdr_color = Color.new(80, 35, 140, 230)
        bmp.fill_rect(2, 2, PANEL_W - 4, 20, hdr_color)
        bmp.font.size  = 13
        bmp.font.bold  = true
        bmp.font.color = Color.new(200, 160, 255)
        bmp.draw_text(5, 3, PANEL_W - 30, 16, "PROFILE", 0)
        # Close hint
        bmp.font.size  = 10
        bmp.font.bold  = false
        bmp.font.color = Color.new(140, 110, 180)
        bmp.draw_text(5, 3, PANEL_W - 8, 16, "[F8 / Esc]", 2)

        if @loading && (@request_time.nil? || (Time.now - @request_time) <= REQUEST_TIMEOUT)
          # ── Loading state ──────────────────────────────────────
          bmp.font.size  = 13
          bmp.font.bold  = false
          bmp.font.color = Color.new(180, 160, 220)
          dots = "." * ((Time.now.to_i % 3) + 1)
          bmp.draw_text(0, PANEL_H / 2 - 8, PANEL_W, 20, "Loading#{dots}", 1)
        elsif @data.nil?
          # ── Timeout / no data ─────────────────────────────────
          bmp.font.size  = 12
          bmp.font.color = Color.new(180, 100, 100)
          bmp.draw_text(0, PANEL_H / 2 - 8, PANEL_W, 20, "No response from server.", 1)
        else
          _draw_profile(bmp)
        end
      rescue => e
        ##MultiplayerDebug.error("PROFILE-PANEL", "Redraw error: #{e.message}")
      end

      # Draw the actual profile content once @data is available.
      def self._draw_profile(bmp)
        d = @data

        # ── Layout ───────────────────────────────────────────────
        # Three columns in the top band (all share y=26, height=SPRITE_H):
        #   Left  (x=8,  w=80):  Name + Title stacked
        #   Mid   (x=92, w=32):  Trainer sprite
        #   Right (x=130,w=134): Change Title button
        # Thick divider below the band, then stats.
        row_y     = 26
        top_h     = SPRITE_H          # 48
        left_x    = 8
        left_w    = 80
        sprite_x  = left_x + left_w + 4 - 25  # 67 — eats 25px into left transparent padding
        sprite_y  = row_y - 5                  # 21 — eats 5px into top transparent padding
        btn_x     = sprite_x + SPRITE_W + 6 + 30  # 135 — shrunk 30px from left
        btn_w     = PANEL_W - btn_x - 6           # 129
        btn_h     = top_h + 30                    # 78 — expanded 30px downward
        div_y     = row_y + top_h + 8 + 30    # 112 — lowered 30px for breathing room
        my_uuid   = (MultiplayerClient.platinum_uuid rescue nil)
        is_own    = my_uuid && @target_uuid == my_uuid

        # ── Name (left, top of band) ──────────────────────────────
        name_str = (d["name"] || "Unknown").to_s
        bmp.font.size  = 14
        bmp.font.bold  = true
        bmp.font.color = Color.new(0, 0, 0, 130)
        bmp.draw_text(left_x + 1, row_y + 1, left_w, 20, name_str, 0)
        bmp.font.color = Color.new(255, 255, 255)
        bmp.draw_text(left_x,     row_y,     left_w, 20, name_str, 0)

        # ── Title (left, below name) ──────────────────────────────
        title_y = row_y + 22
        td = d["active_title"]
        if td.is_a?(Hash) && !td["name"].to_s.empty?
          title_str   = td["name"].to_s
          title_color = _panel_title_color(td)
          bmp.font.size  = 10
          bmp.font.bold  = false
          bmp.font.color = Color.new(0, 0, 0, 110)
          bmp.draw_text(left_x + 1, title_y + 1, left_w, 14, title_str, 0)
          bmp.font.color = title_color
          bmp.draw_text(left_x,     title_y,     left_w, 14, title_str, 0)
        else
          bmp.font.size  = 10
          bmp.font.bold  = false
          bmp.font.color = Color.new(90, 75, 120)
          bmp.draw_text(left_x, title_y, left_w, 14, "No title", 0)
        end

        # ── Trainer sprite (middle column) ────────────────────────
        if @sprite_bmp && !@sprite_bmp.disposed?
          frame_w = (@sprite_bmp.width  / 4 rescue SPRITE_W)
          frame_h = (@sprite_bmp.height / 4 rescue SPRITE_H)
          bmp.blt(sprite_x, sprite_y, @sprite_bmp, Rect.new(0, 0, frame_w, frame_h))
        else
          ph = Color.new(100, 80, 140, 180)
          bmp.fill_rect(sprite_x + 8,  sprite_y,      16,  2, ph)
          bmp.fill_rect(sprite_x + 6,  sprite_y +  2, 20, 12, ph)
          bmp.fill_rect(sprite_x + 8,  sprite_y + 14, 16,  2, ph)
          bmp.fill_rect(sprite_x + 6,  sprite_y + 17, 20, 18, ph)
          bmp.fill_rect(sprite_x + 6,  sprite_y + 35,  8, 12, ph)
          bmp.fill_rect(sprite_x + 18, sprite_y + 35,  8, 12, ph)
        end

        # ── Change Title button (right column) ────────────────────
        btn_bg  = is_own ? Color.new(55, 25,  90, 210) : Color.new(35, 25, 55, 150)
        btn_brd = is_own ? Color.new(130, 65, 190, 220) : Color.new(70, 55, 90, 160)
        bmp.fill_rect(btn_x,     row_y,     btn_w,     btn_h,     btn_brd)
        bmp.fill_rect(btn_x + 2, row_y + 2, btn_w - 4, btn_h - 4, btn_bg)

        mid = row_y + btn_h / 2
        if is_own
          bmp.font.bold  = true
          bmp.font.size  = 12
          bmp.font.color = Color.new(200, 160, 255)
          bmp.draw_text(btn_x, mid - 18, btn_w, 18, "Change", 1)
          bmp.draw_text(btn_x, mid,      btn_w, 18, "Title",  1)
          bmp.font.bold  = false
          bmp.font.size  = 9
          bmp.font.color = Color.new(130, 100, 170)
          bmp.draw_text(btn_x, mid + 18, btn_w, 12, "[Z / Enter]", 1)
        else
          bmp.font.bold  = false
          bmp.font.size  = 10
          bmp.font.color = Color.new(90, 75, 110)
          bmp.draw_text(btn_x, mid - 7, btn_w, 14, "Own profile", 1)
          bmp.draw_text(btn_x, mid + 7, btn_w, 14, "only",        1)
        end

        # ── Thick divider ─────────────────────────────────────────
        bmp.fill_rect(6,     div_y,     PANEL_W - 12, 3, Color.new(80, 40, 130, 200))
        bmp.fill_rect(6 + 1, div_y + 1, PANEL_W - 14, 1, Color.new(160, 100, 220, 120))

        # ── Stats (2-column grid below divider) ───────────────────
        stats     = d["stats"] || {}
        stat_rows = [
          ["NPC Battles:",    stats["trainer_battles"].to_i],
          ["Wild Captured:",  stats["wild_captured"].to_i],
          ["Wild Fainted:",   stats["wild_fainted"].to_i],
          ["Current Badges:", stats["badges"].to_i],
        ]
        label_color = Color.new(160, 130, 210)
        value_color = Color.new(230, 230, 255)
        row_y = div_y + 10
        bmp.font.bold = false
        bmp.font.size = 12
        stat_rows.each do |label, value|
          bmp.font.color = label_color
          bmp.draw_text(12,  row_y, 148, 16, label, 0)
          bmp.font.color = value_color
          bmp.draw_text(162, row_y, PANEL_W - 170, 16, value.to_s, 0)
          row_y += 18
        end

        # ── Timestamp (bottom) ────────────────────────────────────
        bmp.font.size  = 9
        bmp.font.color = Color.new(90, 75, 120)
        bmp.draw_text(8, PANEL_H - 16, PANEL_W - 16, 14,
                      "Last fetched: #{_ago_str(@fetch_time)}", 0)
      end

      # Handle the Change Title menu (blocking, called from tick).
      def self._handle_change_title
        titles = (MultiplayerClient.own_titles rescue [])
        if titles.nil? || titles.empty?
          pbMessage(_INTL("You don't own any titles yet."))
          return
        end
        active_id = @data && @data["active_title"] && @data["active_title"]["id"]
        options = titles.map do |t|
          name = t.is_a?(Hash) ? t["name"].to_s : t.to_s
          t.is_a?(Hash) && t["id"] == active_id ? "#{name} (active)" : name
        end
        options << _INTL("[ Remove Title ]") if active_id
        options << _INTL("Cancel")
        choice = pbMessage(_INTL("Choose a title to equip:"), options, options.length - 1)
        return if choice < 0 || choice >= options.length - 1
        # "Remove Title" slot
        if active_id && choice == options.length - 2
          MultiplayerClient.equip_title("") rescue nil
          pbMessage(_INTL("Title removed."))
        else
          td = titles[choice]
          title_id = td.is_a?(Hash) ? td["id"].to_s : nil
          return if title_id.nil? || title_id.empty?
          if title_id == active_id
            MultiplayerClient.equip_title("") rescue nil
            pbMessage(_INTL("Title unequipped."))
          else
            MultiplayerClient.equip_title(title_id) rescue nil
            pbMessage(_INTL("Title equipped!"))
          end
        end
        # Refresh own profile to reflect change
        close
        MultiplayerUI::ProfilePanel.open(uuid: "self")
      rescue => e
        # Silently recover
      end

      # Compute title color for the panel (gradient uses @title_phase).
      def self._panel_title_color(td, alpha = 255)
        return Color.new(255, 255, 255, alpha) unless td.is_a?(Hash)
        c1 = td["color1"] || [255, 255, 255]
        c2 = td["color2"] || c1
        case td["effect"].to_s
        when "solid", "outline"
          Color.new(c1[0].to_i, c1[1].to_i, c1[2].to_i, alpha)
        when "gradient"
          t = (Math.sin(@title_phase * Math::PI * 2) + 1.0) / 2.0
          r = (c1[0].to_i + (c2[0].to_i - c1[0].to_i) * t).to_i.clamp(0, 255)
          g = (c1[1].to_i + (c2[1].to_i - c1[1].to_i) * t).to_i.clamp(0, 255)
          b = (c1[2].to_i + (c2[2].to_i - c1[2].to_i) * t).to_i.clamp(0, 255)
          Color.new(r, g, b, alpha)
        when "tricolor"
          c3 = td["color3"] || c2
          phase = (@title_phase * 3.0) % 3.0
          if phase < 1.0
            ca, cb = c1, c2; t = phase
          elsif phase < 2.0
            ca, cb = c2, c3; t = phase - 1.0
          else
            ca, cb = c3, c1; t = phase - 2.0
          end
          t = (1.0 - Math.cos(t * Math::PI)) / 2.0
          r = (ca[0].to_i + (cb[0].to_i - ca[0].to_i) * t).to_i.clamp(0, 255)
          g = (ca[1].to_i + (cb[1].to_i - ca[1].to_i) * t).to_i.clamp(0, 255)
          b = (ca[2].to_i + (cb[2].to_i - ca[2].to_i) * t).to_i.clamp(0, 255)
          Color.new(r, g, b, alpha)
        else
          Color.new(255, 255, 255, alpha)
        end
      rescue
        Color.new(255, 255, 255, alpha)
      end

      # Human-readable "X ago" string for a Time object.
      def self._ago_str(t)
        return "never" unless t
        secs = (Time.now - t).to_i
        return "just now"      if secs < 5
        return "#{secs}s ago"  if secs < 60
        return "#{secs/60}m ago" if secs < 3600
        "#{secs/3600}h ago"
      end

    end
  end

  # ── Hook into Scene_Map ──────────────────────────────────────────
  class ::Scene_Map
    alias kif_profile_panel_update update unless method_defined?(:kif_profile_panel_update)

    def update
      kif_profile_panel_update
      MultiplayerUI::ProfilePanel.tick rescue nil
    end
  end

end
