# ===========================================
# Party Inspect UI — blocking overlay showing
# another player's party (6 Pokemon max).
# Triggered from chat context menu.
# ===========================================

if defined?(MultiplayerClient)

  module MultiplayerUI
    module PartyInspect

      PANEL_W  = 486
      CARD_W   = 156
      CARD_H   = 138
      CARD_GAP = 5
      COLS     = 3
      HEADER_H = 26
      PAD      = 6
      PANEL_H  = HEADER_H + 2 * (CARD_H + CARD_GAP) - CARD_GAP + PAD + 10

      # Colors
      C_BG       = Color.new(20, 18, 30, 240)
      C_BORDER   = Color.new(80, 60, 140)
      C_HEADER   = Color.new(55, 30, 100)
      C_CARD_BG  = Color.new(28, 24, 42)
      C_CARD_BD  = Color.new(60, 50, 90)
      C_NAME     = Color.new(230, 220, 255)
      C_LVL      = Color.new(160, 150, 200)
      C_LABEL    = Color.new(130, 115, 175)
      C_VALUE    = Color.new(200, 190, 230)
      C_MOVE_BG  = Color.new(38, 32, 58)
      C_MOVE_BD  = Color.new(55, 45, 80)
      C_SHINY    = Color.new(255, 220, 80)
      C_DIM      = Color.new(90, 80, 120)
      C_IV_GOOD  = Color.new(100, 220, 120)
      C_IV_OK    = Color.new(200, 190, 230)
      C_IV_BAD   = Color.new(200, 100, 100)

      def self.open(target_sid)
        # Request party data
        MultiplayerClient.send_data("REQ_PARTY:#{target_sid}") rescue nil
        target_name = (MultiplayerClient.find_name_for_sid(target_sid) rescue target_sid)

        sw = Graphics.width
        sh = Graphics.height

        vp = Viewport.new(0, 0, sw, sh)
        vp.z = 100_500

        # Dim overlay
        ov = Sprite.new(vp)
        ov.bitmap = Bitmap.new(sw, sh)
        ov.bitmap.fill_rect(0, 0, sw, sh, Color.new(0, 0, 0, 160))
        ov.z = 0

        # Loading text
        loading = Sprite.new(vp)
        loading.bitmap = Bitmap.new(200, 20)
        loading.bitmap.font.name = "Power Green" rescue (loading.bitmap.font.name = "Arial")
        loading.bitmap.font.size = 16
        loading.bitmap.font.color = Color.new(200, 190, 230)
        loading.bitmap.draw_text(0, 0, 200, 20, "Loading party...", 1)
        loading.x = (sw - 200) / 2
        loading.y = sh / 2 - 10
        loading.z = 10

        # Wait for data (max 5 seconds)
        party_data = nil
        start = Time.now
        loop do
          Graphics.update
          Input.update

          # Check for cancel
          if Input.trigger?(Input::B) || (Input.trigger?(Input::MOUSERIGHT) rescue false)
            break
          end

          pd = MultiplayerClient.pop_party_data rescue nil
          if pd && pd[:sid].to_s.upcase == target_sid.to_s.upcase
            party_data = pd[:party]
            break
          end

          break if (Time.now - start) > 5.0
        end

        loading.bitmap.dispose rescue nil
        loading.dispose rescue nil

        unless party_data && party_data.is_a?(Array) && !party_data.empty?
          # Show error briefly
          err = Sprite.new(vp)
          err.bitmap = Bitmap.new(250, 20)
          err.bitmap.font.name = "Power Green" rescue (err.bitmap.font.name = "Arial")
          err.bitmap.font.size = 16
          err.bitmap.font.color = Color.new(220, 100, 100)
          msg = party_data ? "Party is empty." : "Could not retrieve party."
          err.bitmap.draw_text(0, 0, 250, 20, msg, 1)
          err.x = (sw - 250) / 2
          err.y = sh / 2 - 10
          err.z = 10

          30.times { Graphics.update; Input.update }

          err.bitmap.dispose rescue nil
          err.dispose rescue nil
          ov.bitmap.dispose rescue nil
          ov.dispose rescue nil
          vp.dispose rescue nil
          return
        end

        # Build panel
        px = (sw - PANEL_W) / 2
        py = (sh - PANEL_H) / 2

        panel = Sprite.new(vp)
        panel.bitmap = Bitmap.new(PANEL_W, PANEL_H)
        panel.x = px
        panel.y = py
        panel.z = 10

        # Text overlay (drawn on top of pokemon sprites)
        overlay = Sprite.new(vp)
        overlay.bitmap = Bitmap.new(PANEL_W, PANEL_H)
        overlay.x = px
        overlay.y = py
        overlay.z = 30

        # Pokemon sprites (overlay on cards)
        pkm_sprites = []

        # Move hover tooltip state
        move_rects = []   # [{x, y, w, h, id: move_sym}, ...] in screen coords
        tooltip = Sprite.new(vp)
        tooltip.bitmap = Bitmap.new(220, 110)
        tooltip.z = 40
        tooltip.visible = false
        hovered_move = nil

        _draw_panel(panel.bitmap, overlay.bitmap, vp, party_data, target_name, target_sid,
                    px, py, pkm_sprites, move_rects)

        # Blocking loop
        loop do
          Graphics.update
          Input.update

          if Input.trigger?(Input::B) || (Input.trigger?(Input::MOUSERIGHT) rescue false)
            break
          end
          if Input.trigger?(Input::C)
            break
          end
          clicked = (Input.trigger?(Input::MOUSELEFT) rescue false)
          if clicked
            mx = (Input.mouse_x rescue nil)
            my = (Input.mouse_y rescue nil)
            if mx && my
              break if mx < px || mx >= px + PANEL_W || my < py || my >= py + PANEL_H
            end
          end

          # Move tooltip hover
          mx = (Input.mouse_x rescue nil); my = (Input.mouse_y rescue nil)
          new_hover = nil
          if mx && my
            move_rects.each_with_index do |r, i|
              if mx >= r[:x] && mx < r[:x] + r[:w] && my >= r[:y] && my < r[:y] + r[:h]
                new_hover = i; break
              end
            end
          end
          if new_hover != hovered_move
            hovered_move = new_hover
            if hovered_move.nil?
              tooltip.visible = false
            else
              _draw_tooltip(tooltip, move_rects[hovered_move], sw, sh)
            end
          end
        end

        # Cleanup
        tooltip.bitmap.dispose rescue nil
        tooltip.dispose rescue nil
        pkm_sprites.each do |s|
          s.bitmap.dispose rescue nil
          s.dispose rescue nil
        end
        panel.bitmap.dispose rescue nil
        panel.dispose rescue nil
        overlay.bitmap.dispose rescue nil
        overlay.dispose rescue nil
        ov.bitmap.dispose rescue nil
        ov.dispose rescue nil
        vp.dispose rescue nil
      end

      def self._draw_panel(bmp, obmp, vp, party_data, name, sid, px, py, pkm_sprites, move_rects = nil)
        bmp.clear
        obmp.clear

        # Background
        bmp.fill_rect(0, 0, PANEL_W, PANEL_H, C_BG)
        _border(bmp, 0, 0, PANEL_W, PANEL_H, C_BORDER, 2)

        # Header
        bmp.fill_rect(2, 2, PANEL_W - 4, HEADER_H - 2, C_HEADER)
        _set_font(bmp, 18)
        bmp.font.bold  = true
        bmp.font.color = C_NAME
        title = "#{name}'s Party (#{party_data.length}/6)"
        bmp.draw_text(PAD, 4, PANEL_W - PAD * 2, 18, title, 1)
        bmp.font.bold  = false
        _set_font(bmp, 14, true)
        bmp.font.color = C_DIM
        bmp.draw_text(PAD, 5, PANEL_W - PAD * 2, 16, "[X / RMB] Close", 2)

        # Draw each Pokemon card
        party_data.each_with_index do |pj, i|
          next unless pj.is_a?(Hash)
          col = i % COLS
          row = i / COLS
          cx = PAD + col * (CARD_W + CARD_GAP)
          cy = HEADER_H + row * (CARD_H + CARD_GAP)

          _draw_card(bmp, obmp, vp, pj, cx, cy, px, py, pkm_sprites, move_rects)
        end
      end

      def self._draw_card(bmp, obmp, vp, pj, cx, cy, px, py, pkm_sprites, move_rects = nil)
        # Card background
        bmp.fill_rect(cx, cy, CARD_W, CARD_H, C_CARD_BG)
        _border(bmp, cx, cy, CARD_W, CARD_H, C_CARD_BD, 1)

        # Build temp Pokemon
        pkm = _build_pokemon(pj)

        # Pokemon sprite
        begin
          pspr = PokemonSprite.new(vp)
          pspr.setOffset(PictureOrigin::Center)
          if pkm
            pspr.setPokemonBitmap(pkm)
          else
            species = _resolve_species(pj["species"])
            s = !!(pj["shiny"] || pj["head_shiny"] || pj["body_shiny"] || pj["fakeshiny"])
            pspr.setPokemonBitmapFromId(species, false, s)
          end
          # Fixed 96x96 target box — scales any source sprite to that.
          # Positioned in the top-left of card, info/moves/IVs drawn on top via overlay.
          src_w = (pspr.bitmap.width rescue 128).to_f
          target = 96.0
          scale = (target / src_w)
          pspr.zoom_x = scale
          pspr.zoom_y = scale
          # Center-origin sprite: place center toward top-left of card
          pspr.x = px + cx + 32
          pspr.y = py + cy + 36
          pspr.z = 20
          pkm_sprites << pspr
        rescue; end

        # Name + Level
        name = pj["name"].to_s
        if name.empty?
          begin; name = GameData::Species.get(_resolve_species(pj["species"])).name; rescue; name = "???"; end
        end

        info_x = cx + 62
        info_w = CARD_W - 66

        is_shiny = !!(pj["shiny"] || pj["head_shiny"] || pj["body_shiny"] ||
                       pj["natural_shiny"] || pj["fakeshiny"])

        _set_font(obmp, 16)
        obmp.font.bold  = true
        obmp.font.color = is_shiny ? C_SHINY : C_NAME
        name_suffix = is_shiny ? " *" : ""
        obmp.draw_text(info_x, cy + 2, info_w, 16, name + name_suffix)

        lvl = (pj["level"] || 1).to_i
        obmp.font.bold  = false
        _set_font(obmp, 14, true)
        obmp.font.color = C_LVL
        obmp.draw_text(info_x, cy + 18, info_w, 14, "Lv.#{lvl}")

        # Nature + Ability
        nature_str = _get_nature(pkm, pj)
        ability_str = _get_ability(pkm, pj)
        _set_font(obmp, 14, true)
        obmp.font.color = C_LABEL
        obmp.draw_text(info_x, cy + 32, info_w, 14, "#{nature_str} / #{ability_str}")

        # Pokemon type icons (right under nature/ability, inside the info column)
        types = _get_pokemon_types(pkm, pj)
        types.each_with_index do |t, ti|
          _draw_type_icon(obmp, t, info_x + ti * 34, cy + 48, 32, 14)
        end

        # Held item
        item_id = pj["item"]
        if item_id && !item_id.to_s.empty?
          item_name = begin
            GameData::Item.get(item_id.to_s.to_sym).name
          rescue
            item_id.to_s
          end
          _set_font(obmp, 14, true)
          obmp.font.color = C_VALUE
          obmp.draw_text(info_x, cy + 64, info_w, 14, "@ #{item_name}")
        end

        # Moves (2x2 grid at bottom of card) — drawn to overlay so they sit over sprite
        move_names = _get_moves(pkm, pj)
        move_ids   = _get_move_ids(pkm, pj)
        move_y = cy + CARD_H - 42
        _set_font(obmp, 14, true)
        mw = (CARD_W - 10) / 2  # cell width
        2.times do |r|
          2.times do |c|
            mi = r * 2 + c
            mx = cx + 4 + c * (mw + 2)
            my = move_y + r * 20
            obmp.fill_rect(mx, my, mw, 18, C_MOVE_BG)
            _border(obmp, mx, my, mw, 18, C_MOVE_BD, 1)
            mv = move_names[mi] || "-"
            obmp.font.color = mv == "-" ? C_DIM : C_VALUE
            obmp.draw_text(mx + 3, my + 1, mw - 6, 15, mv)
            if move_rects && move_ids[mi]
              move_rects << { :x => px + mx, :y => py + my, :w => mw, :h => 18, :id => move_ids[mi] }
            end
          end
        end

        # IVs (compact row below name area) — drawn to overlay
        iv_map, _ev = _get_stats(pkm, pj)
        if iv_map
          iv_y = move_y - 28
          _set_font(obmp, 14, true)
          stats = [:HP, :ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED]
          labels = ["HP", "Atk", "Def", "SpA", "SpD", "Spe"]
          stat_w = (CARD_W - 8) / 6
          stats.each_with_index do |stat, si|
            val = iv_map[stat].to_i rescue 0
            sx = cx + 4 + si * stat_w
            obmp.font.color = val >= 28 ? C_IV_GOOD : (val >= 15 ? C_IV_OK : C_IV_BAD)
            obmp.draw_text(sx, iv_y, stat_w, 14, "#{labels[si]}", 1)
            obmp.draw_text(sx, iv_y + 12, stat_w, 14, "#{val}", 1)
          end
        end
      end

      # ── Helpers ─────────────────────────────────────────
      def self._set_font(bmp, size = 14, small = false)
        name = small ? "Power Green Small" : "Power Green"
        bmp.font.name = name rescue (bmp.font.name = "Arial")
        bmp.font.size = size
      end

      def self._border(bmp, x, y, w, h, c, t)
        bmp.fill_rect(x, y, w, t, c)
        bmp.fill_rect(x, y + h - t, w, t, c)
        bmp.fill_rect(x, y, t, h, c)
        bmp.fill_rect(x + w - t, y, t, h, c)
      end

      def self._resolve_species(raw)
        return :BULBASAUR unless raw
        sym = raw.to_s.upcase.to_sym rescue :BULBASAUR
        sym
      end

      def self._build_pokemon(pj)
        return nil unless pj && defined?(Pokemon)
        begin
          TradeUI.ensure_complete_stat_maps!(pj) if defined?(TradeUI) && TradeUI.respond_to?(:ensure_complete_stat_maps!)
          sid = _resolve_species(pj["species"])
          p = Pokemon.new(sid, [(pj["level"] || 1).to_i, 1].max)
          p.load_json(pj)
          TradeUI.force_species_id!(p) if defined?(TradeUI) && TradeUI.respond_to?(:force_species_id!)
          p
        rescue
          nil
        end
      end

      def self._get_nature(pkm, pj)
        begin
          return pkm.nature.name.to_s if pkm && pkm.respond_to?(:nature) && pkm.nature
          raw = pj["nature"] || pj["nature_for_stats"]
          return GameData::Nature.get(raw).name.to_s if defined?(GameData::Nature) && raw
        rescue; end
        "-"
      end

      def self._get_ability(pkm, pj)
        begin
          return pkm.ability.name.to_s if pkm && pkm.respond_to?(:ability) && pkm.ability
          raw = pj["ability"] || pj["ability_index"]
          return GameData::Ability.get(raw).name.to_s if defined?(GameData::Ability) && raw
        rescue; end
        "-"
      end

      def self._get_moves(pkm, pj)
        names = []
        begin
          if pkm && pkm.respond_to?(:moves)
            names = pkm.moves.map { |m| m&.name.to_s rescue nil }.compact
          else
            arr = pj["moves"]
            if arr.is_a?(Array)
              names = arr.map { |m|
                id = m.is_a?(Hash) ? (m["id"] || m["move"] || m["name"]) : m
                next if id.nil?
                (defined?(GameData::Move) ? GameData::Move.get(id).name.to_s : id.to_s) rescue id.to_s
              }.compact
            end
          end
        rescue; end
        names
      end

      # Lazily load the types spritesheet (cached across opens).
      def self._typebitmap
        return @typebitmap if defined?(@typebitmap) && @typebitmap && !@typebitmap.disposed?
        begin
          @typebitmap = AnimatedBitmap.new(_INTL("Graphics/Pictures/types"))
        rescue
          @typebitmap = nil
        end
        @typebitmap
      end

      TYPE_SRC_W = 64
      TYPE_SRC_H = 28

      def self._draw_type_icon(bmp, type_sym, x, y, w = 32, h = 14)
        return unless type_sym
        tb = _typebitmap
        return unless tb && defined?(GameData::Type)
        begin
          type_data = GameData::Type.get(type_sym)
          type_num = type_data.id_number rescue 0
          src = Rect.new(0, type_num * TYPE_SRC_H, TYPE_SRC_W, TYPE_SRC_H)
          dst = Rect.new(x, y, w, h)
          bmp.stretch_blt(dst, tb.bitmap, src)
          # Clear the 2x2 corner blocks (source sheet has stray white corners)
          clear = Color.new(0, 0, 0, 0)
          bmp.fill_rect(x, y, 2, 2, clear)
          bmp.fill_rect(x + w - 2, y, 2, 2, clear)
          bmp.fill_rect(x, y + h - 2, 2, 2, clear)
          bmp.fill_rect(x + w - 2, y + h - 2, 2, 2, clear)
        rescue; end
      end

      def self._get_pokemon_types(pkm, pj)
        types = []
        begin
          if pkm && pkm.respond_to?(:types)
            types = pkm.types.compact rescue []
          end
        rescue; end
        if types.empty?
          begin
            sid = _resolve_species(pj["species"])
            sd = GameData::Species.get(sid)
            t1 = sd.type1 rescue nil
            t2 = sd.type2 rescue nil
            types << t1 if t1
            types << t2 if t2 && t2 != t1
          rescue; end
        end
        types
      end

      def self._get_move_ids(pkm, pj)
        ids = []
        begin
          if pkm && pkm.respond_to?(:moves)
            ids = pkm.moves.map { |m| (m.id rescue nil) }
          else
            arr = pj["moves"]
            if arr.is_a?(Array)
              ids = arr.map { |m|
                raw = m.is_a?(Hash) ? (m["id"] || m["move"] || m["name"]) : m
                next nil if raw.nil?
                raw.to_s.to_sym rescue nil
              }
            end
          end
        rescue; end
        ids || []
      end

      def self._draw_tooltip(tooltip, rect, sw, sh)
        mid = rect[:id]
        md = begin
          GameData::Move.get(mid)
        rescue
          nil
        end
        unless md
          tooltip.visible = false
          return
        end

        tw = 220; th = 110
        b = tooltip.bitmap
        b.clear
        b.fill_rect(0, 0, tw, th, C_BG)
        _border(b, 0, 0, tw, th, C_BORDER, 2)

        # Name + type icon (top-right)
        type_sym = (md.type rescue nil)
        _set_font(b, 16)
        b.font.bold = true
        b.font.color = C_NAME
        b.draw_text(6, 2, tw - 12 - 36, 18, md.name.to_s)
        b.font.bold = false
        _draw_type_icon(b, type_sym, tw - 38, 5, 32, 14) if type_sym

        # Category | Power | Accuracy
        cat = case (md.category rescue -1)
              when 0 then "Physical"
              when 1 then "Special"
              else "Status"
              end
        pow = ((md.base_damage rescue 0).to_i > 0) ? md.base_damage.to_s : "—"
        acc = ((md.accuracy rescue 0).to_i > 0) ? md.accuracy.to_s : "—"
        _set_font(b, 14, true)
        b.font.color = C_LABEL
        b.draw_text(6, 26, tw - 12, 14, "#{cat}  |  Pow: #{pow}  |  Acc: #{acc}")

        # Separator
        b.fill_rect(6, 40, tw - 12, 1, C_CARD_BD)

        # Description (word-wrapped)
        desc = (md.description.to_s rescue "")
        _set_font(b, 14, true)
        b.font.color = C_VALUE
        y = 44
        _wrap(desc, tw - 14, b).each do |line|
          break if y + 14 > th - 4
          b.draw_text(6, y, tw - 12, 14, line)
          y += 14
        end

        # Position tooltip near the cell
        tx = rect[:x]
        ty = rect[:y] + rect[:h] + 4
        tx = [tx, sw - tw - 2].min
        tx = [tx, 2].max
        if ty + th > sh - 2
          ty = rect[:y] - th - 4
        end
        ty = [ty, 2].max

        tooltip.x = tx
        tooltip.y = ty
        tooltip.visible = true
      end

      def self._wrap(text, max_w, bmp)
        lines = []
        text.to_s.split(/\n/).each do |para|
          words = para.split(/\s+/)
          cur = ""
          words.each do |w|
            trial = cur.empty? ? w : (cur + " " + w)
            if (bmp.text_size(trial).width rescue 0) <= max_w
              cur = trial
            else
              lines << cur unless cur.empty?
              cur = w
            end
          end
          lines << cur unless cur.empty?
        end
        lines
      end

      def self._get_stats(pkm, pj)
        iv = nil; ev = nil
        begin
          if pkm && pkm.respond_to?(:iv) && pkm.respond_to?(:ev)
            iv = pkm.iv; ev = pkm.ev
          else
            piv = pj["iv"]; pev = pj["ev"]
            if piv.is_a?(Hash); iv = {}; piv.each { |k, v| iv[k.to_s.upcase.to_sym] = v.to_i }; end
            if pev.is_a?(Hash); ev = {}; pev.each { |k, v| ev[k.to_s.upcase.to_sym] = v.to_i }; end
          end
        rescue; end
        [iv, ev]
      end

      def self._shiny_label(pj)
        return "Fake" if pj["fakeshiny"]
        return "Natural" if pj["natural_shiny"]
        "Yes"
      end

    end
  end

end
