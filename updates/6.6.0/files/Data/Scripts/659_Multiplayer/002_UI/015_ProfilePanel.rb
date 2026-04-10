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
      PANEL_W   = 330
      PANEL_H   = 260
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

      # Mouse hover state for Change Title button
      @btn_hovered   = false

      # Cache: keyed by UUID, stores { data:, sprite_bmp:, fetch_time: }
      @cache         = {}

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
        @title_phase  = 0.0
        @request_time = Time.now

        # Use cached data if available — show immediately, refresh in background
        cached = @cache[@target_uuid]
        if cached
          @data       = cached[:data]
          @fetch_time = cached[:fetch_time]
          @loading    = true  # still fetch fresh data in background
          _dispose_sprite_bmp
          @sprite_bmp = cached[:sprite_bmp]  # reuse cached sprite bitmap
        else
          @data       = nil
          @fetch_time = nil
          @loading    = true
          _dispose_sprite_bmp
        end

        MultiplayerClient.request_profile(@target_uuid)
        _ensure_viewport
        _redraw
      end

      def self.close
        # Cache current data for instant re-open
        if @target_uuid && @data
          @cache[@target_uuid] = {
            data: @data,
            sprite_bmp: @sprite_bmp,
            fetch_time: @fetch_time
          }
          @sprite_bmp = nil  # prevent _dispose_panel from disposing cached bitmap
        end
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

        # Right-click anywhere to close
        if (Input.trigger?(Input::MOUSERIGHT) rescue false)
          close
          return
        end

        # Poll for PROFILE_DATA response
        if @loading
          pd = MultiplayerClient.pop_profile_data rescue nil
          if pd.is_a?(Hash)
            @data       = pd
            @loading    = false
            @fetch_time = Time.now
            _dispose_sprite_bmp
            _build_sprite_bmp(@data["sprite_data"])
            # Update cache with fresh data
            @cache[@target_uuid] = {
              data: @data,
              sprite_bmp: @sprite_bmp,
              fetch_time: @fetch_time
            }
            _redraw
          elsif @request_time && (Time.now - @request_time) > REQUEST_TIMEOUT
            @loading = false  # Show timeout state
            _redraw
          end
        end

        # Advance gradient animation (gradient/tricolor need full redraw)
        td = @data && @data["active_title"]
        if td.is_a?(Hash)
          if td["effect"] == "gradient" || td["effect"] == "tricolor"
            speed = (td["speed"] || 0.3).to_f
            @title_phase += speed / 60.0
            _redraw
          elsif td["gilded"]
            _redraw
          end
        end

        # Change Title button — Z/C key or mouse click, only on own profile
        if !@loading && @data
          my_uuid = (MultiplayerClient.platinum_uuid rescue nil)
          if my_uuid && @target_uuid == my_uuid
            # Keyboard
            if Input.trigger?(Input::C)
              _handle_change_title
            end
            # Mouse hover + click
            _handle_btn_mouse(my_uuid)
          else
            if @btn_hovered
              @btn_hovered = false
              _redraw
            end
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
        bg_color  = Color.new(15, 10, 25, 255)    # dark purple-black (fully opaque)
        brd_color = Color.new(130, 70, 200, 255)   # violet border (fully opaque)
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
          bmp.font.size  = 10
          bmp.font.bold  = false
          if td["gilded"]
            tw = (bmp.text_size(title_str).width rescue title_str.length * 7)
            _draw_gilded_plate(bmp, left_x - 2, title_y, tw + 4, 14, Time.now.to_f)
            bmp.font.color = Color.new(15, 10, 0, 255)
            bmp.draw_text(left_x, title_y, left_w, 14, title_str, 0)
          else
            title_color = _panel_title_color(td)
            bmp.font.color = Color.new(0, 0, 0, 110)
            bmp.draw_text(left_x + 1, title_y + 1, left_w, 14, title_str, 0)
            bmp.font.color = title_color
            bmp.draw_text(left_x,     title_y,     left_w, 14, title_str, 0)
          end
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
        if is_own && @btn_hovered
          btn_bg  = Color.new(80, 40, 130, 230)
          btn_brd = Color.new(180, 100, 255, 255)
        elsif is_own
          btn_bg  = Color.new(55, 25,  90, 210)
          btn_brd = Color.new(130, 65, 190, 220)
        else
          btn_bg  = Color.new(35, 25, 55, 150)
          btn_brd = Color.new(70, 55, 90, 160)
        end
        bmp.fill_rect(btn_x,     row_y,     btn_w,     btn_h,     btn_brd)
        bmp.fill_rect(btn_x + 2, row_y + 2, btn_w - 4, btn_h - 4, btn_bg)

        mid = row_y + btn_h / 2
        if is_own
          bmp.font.bold  = true
          bmp.font.size  = 12
          bmp.font.color = @btn_hovered ? Color.new(240, 200, 255) : Color.new(200, 160, 255)
          bmp.draw_text(btn_x, mid - 18, btn_w, 18, "Change", 1)
          bmp.draw_text(btn_x, mid,      btn_w, 18, "Title",  1)
          bmp.font.bold  = false
          bmp.font.size  = 9
          bmp.font.color = @btn_hovered ? Color.new(180, 140, 220) : Color.new(130, 100, 170)
          bmp.draw_text(btn_x, mid + 18, btn_w, 12, @btn_hovered ? "Click to change" : "[Z / Enter]", 1)
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
        stats = d["stats"] || {}
        # Left column: battle/capture progress
        left_rows = [
          ["NPC Battles:",    stats["trainer_battles"].to_i],
          ["Wild Captured:",  stats["wild_captured"].to_i],
          ["Wild Fainted:",   stats["wild_fainted"].to_i],
          ["Eggs Hatched:",   stats["eggs_hatched"].to_i],
          ["Badges:",         stats["badges"].to_i],
          ["Dex Caught:",     stats["pokemon_caught"].to_i],
        ]
        # Right column: economy / social / titles
        right_rows = [
          ["Steps Taken:",    stats["steps"].to_i],
          ["Chat Sent:",      stats["chat_messages"].to_i],
          ["$ Won:",          stats["platinum_won"].to_i],
          ["$ Spent:",        stats["platinum_spent"].to_i],
          ["Titles:",         stats["titles_collected"].to_i],
          ["Bosses:",         stats["bosses_fainted"].to_i],
        ]
        label_color = Color.new(160, 130, 210)
        value_color = Color.new(230, 230, 255)
        col_w       = (PANEL_W - 24) / 2   # 153
        col1_x      = 12
        col2_x      = col1_x + col_w + 0
        label_w     = 78
        value_w     = col_w - label_w - 4
        base_y      = div_y + 10
        row_h       = 17
        bmp.font.bold = false
        bmp.font.size = 12

        draw_row = lambda do |x, y, label, value|
          bmp.font.color = label_color
          bmp.draw_text(x, y, label_w, 16, label, 0)
          bmp.font.color = value_color
          bmp.draw_text(x + label_w, y, value_w, 16, _fmt_num(value), 0)
        end

        left_rows.each_with_index  { |(l, v), i| draw_row.call(col1_x, base_y + i * row_h, l, v) }
        right_rows.each_with_index { |(l, v), i| draw_row.call(col2_x, base_y + i * row_h, l, v) }

        # ── Timestamp (bottom) ────────────────────────────────────
        bmp.font.size  = 9
        bmp.font.color = Color.new(90, 75, 120)
        bmp.draw_text(8, PANEL_H - 16, PANEL_W - 16, 14,
                      "Last fetched: #{_ago_str(@fetch_time)}", 0)
      end

      # Mouse hover + click detection for the Change Title button.
      def self._handle_btn_mouse(my_uuid)
        mx = (Input.mouse_x rescue nil)
        my = (Input.mouse_y rescue nil)
        return unless mx && my

        # Button screen coordinates
        sw = Graphics.width
        sh = Graphics.height
        px = (sw - PANEL_W) / 2
        py = (sh - PANEL_H) / 2

        row_y    = 26
        top_h    = SPRITE_H
        left_x   = 8
        left_w   = 80
        sprite_x = left_x + left_w + 4 - 25
        btn_x    = sprite_x + SPRITE_W + 6 + 30
        btn_w    = PANEL_W - btn_x - 6
        btn_h    = top_h + 30

        abs_btn_x = px + btn_x
        abs_btn_y = py + row_y

        over = mx >= abs_btn_x && mx < abs_btn_x + btn_w &&
               my >= abs_btn_y && my < abs_btn_y + btn_h

        if over != @btn_hovered
          @btn_hovered = over
          _redraw
        end

        if over && (Input.trigger?(Input::MOUSELEFT) rescue false)
          _handle_change_title
        end
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

      # Format a large integer with thousand separators (e.g. 1,234,567).
      def self._fmt_num(n)
        n.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      rescue
        n.to_s
      end

      # Gilded gold bar with pulsing glow. All opaque.
      # phase: Time.now.to_f — drives the glow pulse.
      def self._draw_gilded_plate(bmp, x, y, w, h, phase)
        # Two layered waves — use modulo to keep phase in sane range
        ph = phase % 100.0
        p1 = (Math.sin(ph * 2.5) + 1.0) / 2.0
        p2 = (Math.sin(ph * 1.1 + 1.2) + 1.0) / 2.0
        glow = p1 * 0.6 + p2 * 0.4  # 0..1
        # Base — wide swing: dark brown-gold ↔ warm gold
        br = (30 + glow * 45).to_i; bg = (22 + glow * 38).to_i
        bmp.fill_rect(x, y, w, h, Color.new(br, bg, 5))
        # Top bevel — muted ↔ bright
        tr = (160 + glow * 95).to_i; tg = (130 + glow * 80).to_i; tb = (25 + glow * 45).to_i
        bmp.fill_rect(x + 1, y, w - 2, 1, Color.new(tr, tg, tb))
        bmp.fill_rect(x + 1, y + 1, w - 2, 1, Color.new(tr - 50, tg - 40, [tb - 10, 0].max))
        # Bottom bevel
        bmp.fill_rect(x + 1, y + h - 2, w - 2, 1, Color.new((65 + glow * 30).to_i, (50 + glow * 22).to_i, 12))
        bmp.fill_rect(x + 1, y + h - 1, w - 2, 1, Color.new(35, 25, 8))
        # Side bevels
        bmp.fill_rect(x, y + 1, 1, h - 2, Color.new((140 + glow * 60).to_i, (115 + glow * 50).to_i, (20 + glow * 25).to_i))
        bmp.fill_rect(x + w - 1, y + 1, 1, h - 2, Color.new((85 + glow * 35).to_i, (60 + glow * 28).to_i, 15))
        # Inner gold body — bands breathe with glow
        inner_x = x + 2; inner_w = w - 4; mid_y = y + h / 2
        (2...h - 2).each do |dy|
          py = y + dy
          dist = (py - mid_y).abs.to_f / (h / 2.0)
          bright = (1.0 - dist) * (0.5 + glow * 0.5)
          r = (100 + bright * 130).to_i.clamp(0, 240)
          g = (75  + bright * 105).to_i.clamp(0, 190)
          b = (10  + bright * 25).to_i.clamp(0, 40)
          bmp.fill_rect(inner_x, py, inner_w, 1, Color.new(r, g, b))
        end
        # Corner rivets
        cr = (200 + glow * 55).to_i; cg = (170 + glow * 50).to_i
        bmp.fill_rect(x + 1, y + 1, 2, 2, Color.new(cr, cg, 45))
        bmp.fill_rect(x + w - 3, y + 1, 2, 2, Color.new(cr, cg, 45))
        bmp.fill_rect(x + 1, y + h - 3, 2, 2, Color.new((160 + glow * 40).to_i, (130 + glow * 35).to_i, 30))
        bmp.fill_rect(x + w - 3, y + h - 3, 2, 2, Color.new((160 + glow * 40).to_i, (130 + glow * 35).to_i, 30))
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
