# ===========================================
# File: 016_TitleSelectUI.rb
# Purpose: Grid-based title selection overlay.
#          4-column cell grid, floating tooltip on hover.
#          Hover shows pulsing glow. Tooltip shows name, effect,
#          description, and progress if available.
# ===========================================

if defined?(Scene_Map)

  module MultiplayerUI
    module TitleSelectUI

      # ── Layout constants ─────────────────────────────────────────
      PANEL_W   = 480
      COLS      = 4
      CELL_W    = 112
      CELL_H    = 44
      CELL_GAP  = 4
      ROW_PITCH = CELL_H + CELL_GAP   # 48
      ROWS_VIS  = 6
      HEADER_H  = 28
      GRID_PAD_TOP = 8                 # gap between header and first row
      FOOTER_H  = 20
      PAD       = 10
      SCROLL_W  = 6
      SCROLL_X  = PAD + COLS * (CELL_W + CELL_GAP)   # 472
      GRID_Y    = HEADER_H + GRID_PAD_TOP           # top of the cell grid
      PANEL_H   = GRID_Y + ROWS_VIS * ROW_PITCH - CELL_GAP + FOOTER_H

      TT_W      = 196   # tooltip width
      TT_PAD    = 8

      # ── Entry point ──────────────────────────────────────────────
      def self.open(titles, active_id)
        titles    = titles.is_a?(Array) ? titles : []
        active_id = active_id.to_s

        items = [{ "id" => "", "name" => "[ No Title ]",
                   "effect" => "solid", "color1" => [100, 80, 140],
                   "owned" => true }]
        # Owned titles first, then unowned
        owned   = titles.select { |t| t.is_a?(Hash) && t["owned"] }
        unowned = titles.select { |t| t.is_a?(Hash) && !t["owned"] }
        (owned + unowned).each { |t| items << t }

        total_rows = (items.length + COLS - 1) / COLS
        max_scroll = [total_rows - ROWS_VIS, 0].max

        cursor = 0
        if !active_id.empty?
          idx = items.index { |t| t["id"].to_s == active_id }
          cursor = idx if idx
        end
        scroll_row = [cursor / COLS - ROWS_VIS / 2, 0].max.clamp(0, max_scroll)

        sw = Graphics.width
        sh = Graphics.height
        px = (sw - PANEL_W) / 2
        py = (sh - PANEL_H) / 2

        vp = Viewport.new(0, 0, sw, sh)
        vp.z = 99_600

        ov = Sprite.new(vp)
        ov.bitmap = Bitmap.new(sw, sh)
        ov.bitmap.fill_rect(0, 0, sw, sh, Color.new(0, 0, 0, 165))
        ov.z = 0

        ps = Sprite.new(vp)
        ps.bitmap = Bitmap.new(PANEL_W, PANEL_H)
        ps.x = px
        ps.y = py
        ps.z = 10

        # Tooltip sprite — floats next to hovered cell, fixed-size bitmap
        tt_spr = Sprite.new(vp)
        tt_spr.bitmap  = Bitmap.new(TT_W, 160)
        tt_spr.z       = 20
        tt_spr.visible = false

        hover       = nil
        prev_hover  = nil
        hover_start = nil    # wall-clock Time when hover began
        phase       = 0.0
        result      = nil
        done        = false
        drag_scroll = false
        drag_offset = 0

        loop do
          Graphics.update
          Input.update
          phase += 0.016

          mx      = (Input.mouse_x rescue nil)
          my      = (Input.mouse_y rescue nil)
          clicked = (Input.trigger?(Input::MOUSELEFT)  rescue false)
          rclick  = (Input.trigger?(Input::MOUSERIGHT) rescue false)
          held    = (Input.press?(Input::MOUSELEFT)    rescue false)
          mw      = (Input.mouse_wheel rescue 0).to_i

          # ── Close ─────────────────────────────────────────────
          if rclick || Input.trigger?(Input::B)
            break
          end
          if clicked && mx && my
            break if mx < px || mx >= px + PANEL_W || my < py || my >= py + PANEL_H
          end

          # ── Keyboard navigation ───────────────────────────────
          moved = false
          if Input.trigger?(Input::LEFT) || Input.repeat?(Input::LEFT)
            cursor = [cursor - 1, 0].max;                   moved = true
          elsif Input.trigger?(Input::RIGHT) || Input.repeat?(Input::RIGHT)
            cursor = [cursor + 1, items.length - 1].min;    moved = true
          elsif Input.trigger?(Input::UP) || Input.repeat?(Input::UP)
            cursor = [cursor - COLS, 0].max;                moved = true
          elsif Input.trigger?(Input::DOWN) || Input.repeat?(Input::DOWN)
            cursor = [cursor + COLS, items.length - 1].min; moved = true
          elsif Input.trigger?(Input::C)
            if items[cursor]["owned"]
              result = items[cursor]["id"].to_s
              done   = true
            end
          end

          if moved
            cur_row = cursor / COLS
            if cur_row < scroll_row
              scroll_row = cur_row
            elsif cur_row >= scroll_row + ROWS_VIS
              scroll_row = cur_row - ROWS_VIS + 1
            end
            scroll_row = scroll_row.clamp(0, max_scroll)
            hover = nil
          end

          break if done

          # ── Mouse ─────────────────────────────────────────────
          if mx && my
            lx = mx - px
            ly = my - py

            # Scroll wheel
            if mw != 0 && lx >= 0 && lx < PANEL_W && ly >= 0 && ly < PANEL_H
              scroll_row = (scroll_row - mw).clamp(0, max_scroll)
            end

            # Scrollbar
            track_h = ROWS_VIS * ROW_PITCH - CELL_GAP
            th = _thumb_h(total_rows, track_h)
            ty = GRID_Y + _thumb_y(scroll_row, total_rows, track_h, th)

            if drag_scroll
              if !held
                drag_scroll = false
              else
                rel = (ly - GRID_Y - drag_offset).clamp(0, track_h - th)
                scroll_row = max_scroll > 0 ?
                  (rel.to_f / (track_h - th) * max_scroll).round.clamp(0, max_scroll) : 0
              end
            elsif total_rows > ROWS_VIS &&
                  lx >= SCROLL_X && lx < SCROLL_X + SCROLL_W &&
                  ly >= GRID_Y && ly < GRID_Y + track_h
              if clicked
                if ly >= ty && ly < ty + th
                  drag_scroll = true
                  drag_offset = ly - ty
                else
                  rel = (ly - GRID_Y - th / 2.0).clamp(0, track_h - th)
                  scroll_row = max_scroll > 0 ?
                    (rel / (track_h - th) * max_scroll).round.clamp(0, max_scroll) : 0
                end
              end
            end

            # Cell hover + click (hover is purely visual, does not move cursor)
            unless drag_scroll
              cell_idx = _cell_at(lx, ly, scroll_row, items.length)
              hover    = cell_idx
              if clicked && cell_idx && items[cell_idx]["owned"]
                result = items[cell_idx]["id"].to_s
                done   = true
              end
            end
          else
            hover = nil
          end

          break if done

          # ── Draw main grid ────────────────────────────────────
          _draw(ps.bitmap, items, cursor, scroll_row, active_id,
                phase, hover, total_rows, drag_scroll)

          # ── Hover time tracking (wall-clock, ignores game speed) ──
          if hover != prev_hover
            hover_start = hover ? Time.now : nil
            prev_hover  = hover
          end
          hover_time = (hover && hover_start) ? (Time.now - hover_start).to_f : 0.0

          # ── Draw tooltip ──────────────────────────────────────
          if hover && !drag_scroll
            t_item = items[hover]
            h_col = hover % COLS
            h_row = hover / COLS - scroll_row
            cell_sx = px + PAD + h_col * (CELL_W + CELL_GAP)
            cell_sy = py + GRID_Y + h_row * ROW_PITCH
            _draw_tooltip(tt_spr, t_item, active_id, phase,
                          cell_sx, cell_sy, sw, sh, hover_time)
            tt_spr.visible = true
          else
            tt_spr.visible = false
          end
        end

        begin
          tt_spr.bitmap.dispose rescue nil; tt_spr.dispose rescue nil
          ps.bitmap.dispose     rescue nil; ps.dispose     rescue nil
          ov.bitmap.dispose     rescue nil; ov.dispose     rescue nil
          vp.dispose            rescue nil
        rescue; end

        result
      end

      # ── Main grid draw ────────────────────────────────────────────

      def self._draw(bmp, items, cursor, scroll_row, active_id,
                     phase, hover, total_rows, drag_scroll)
        bmp.clear

        bmp.fill_rect(0, 0, PANEL_W, PANEL_H, Color.new(120, 65, 195, 255))
        bmp.fill_rect(2, 2, PANEL_W - 4, PANEL_H - 4, Color.new(12, 8, 22, 255))

        # Header
        bmp.fill_rect(2, 2, PANEL_W - 4, HEADER_H - 2, Color.new(72, 28, 125, 255))
        bmp.font.bold  = true
        bmp.font.size  = 14
        bmp.font.color = Color.new(210, 170, 255)
        bmp.draw_text(0, 4, PANEL_W, 18, "Select Title", 1)
        bmp.font.bold  = false
        bmp.font.size  = 11
        bmp.font.color = Color.new(110, 85, 155)
        bmp.draw_text(0, 4, PANEL_W - 8, 18, "[Z] Equip   [X / RMB] Cancel", 2)

        pulse = (Math.sin(phase * 5.0) + 1.0) / 2.0   # 0..1

        ROWS_VIS.times do |r|
          COLS.times do |c|
            idx = (scroll_row + r) * COLS + c
            break if idx >= items.length
            t = items[idx]

            cx = PAD + c * (CELL_W + CELL_GAP)
            cy = GRID_Y + r * ROW_PITCH

            is_cursor  = (idx == cursor)
            is_hover   = (idx == hover)
            is_active  = !active_id.empty? && t["id"].to_s == active_id
            is_owned   = t["owned"] ? true : false
            is_hidden  = t["hidden"] && !is_owned
            is_gilded  = t["gilded"] ? true : false

            # Cell background (all opaque to avoid bleed-through lines)
            if is_gilded && is_owned
              # Gilded: animated gold plate fill
              bmp.fill_rect(cx, cy, CELL_W, CELL_H, Color.new(16, 12, 28))
              _draw_gilded_plate(bmp, cx + 2, cy + 2, CELL_W - 4, CELL_H - 4, Time.now.to_f)
            elsif !is_owned
              bmp.fill_rect(cx, cy, CELL_W, CELL_H, Color.new(16, 12, 28))
            elsif is_cursor
              bmp.fill_rect(cx, cy, CELL_W, CELL_H, Color.new(80, 38, 138))
            elsif is_hover
              pa = (38 + pulse * 30).to_i
              bmp.fill_rect(cx, cy, CELL_W, CELL_H, Color.new(pa, 16, pa + 55))
            else
              bmp.fill_rect(cx, cy, CELL_W, CELL_H, Color.new(22, 14, 42))
            end

            # Cell border
            if is_gilded && is_owned
              # Gilded: gold border (plate already drawn as background)
              bc = Color.new(200, 165, 20, 220)
              _draw_border(bmp, cx, cy, CELL_W, CELL_H, bc, 2)
            elsif is_active
              bc = Color.new(255, 198, 55)
              _draw_border(bmp, cx, cy, CELL_W, CELL_H, bc, 2)
            elsif !is_owned
              bc = Color.new(35, 25, 55)
              _draw_border(bmp, cx, cy, CELL_W, CELL_H, bc, 1)
            elsif is_cursor
              bc = Color.new(175, 110, 255)
              _draw_border(bmp, cx, cy, CELL_W, CELL_H, bc, 2)
            elsif is_hover
              bv = (130 + pulse * 110).to_i
              bc = Color.new(bv, bv / 2, 255)
              _draw_border(bmp, cx, cy, CELL_W, CELL_H, bc, 2)
              glow_a = (pulse * 55).to_i
              bmp.fill_rect(cx + 2, cy + 2, CELL_W - 4, 2,
                            Color.new(200, 160, 255, glow_a))
            else
              bc = Color.new(55, 40, 82)
              _draw_border(bmp, cx, cy, CELL_W, CELL_H, bc, 1)
            end

            # Active dot (top-right corner of cell)
            if is_active
              bmp.fill_rect(cx + CELL_W - 8, cy + 4, 5, 5,
                            Color.new(255, 200, 55))
            end

            # Title name — hidden unowned titles show "???"
            name   = is_hidden ? "???" : t["name"].to_s
            text_y = cy + (CELL_H - 16) / 2
            bmp.font.bold  = is_cursor && is_owned
            bmp.font.size  = 14
            if is_gilded && is_owned
              # Gilded: black engraved text on gold plate + shine
              bmp.font.color = Color.new(0, 0, 0, 60)
              bmp.draw_text(cx + 1, text_y + 1, CELL_W - 2, 16, name, 1)
              bmp.font.color = Color.new(15, 10, 0, 255)
              bmp.draw_text(cx,     text_y,     CELL_W - 2, 16, name, 1)
            else
              col    = is_owned ? _title_color(t, phase) : Color.new(60, 45, 85)
              bmp.font.color = Color.new(0, 0, 0, 130)
              bmp.draw_text(cx + 1, text_y + 1, CELL_W - 2, 16, name, 1)
              bmp.font.color = col
              bmp.draw_text(cx,     text_y,     CELL_W - 2, 16, name, 1)
            end
          end
        end

        # Scrollbar
        if total_rows > ROWS_VIS
          track_h = ROWS_VIS * ROW_PITCH - CELL_GAP
          th = _thumb_h(total_rows, track_h)
          ty = GRID_Y + _thumb_y(scroll_row, total_rows, track_h, th)
          bmp.fill_rect(SCROLL_X, GRID_Y, SCROLL_W, track_h,
                        Color.new(32, 18, 55, 210))
          tc = drag_scroll ? Color.new(210, 145, 255) : Color.new(148, 88, 218, 255)
          bmp.fill_rect(SCROLL_X, ty, SCROLL_W, th, tc)
        end

        # Footer
        fy = PANEL_H - FOOTER_H
        bmp.fill_rect(2, fy, PANEL_W - 4, FOOTER_H - 2, Color.new(22, 10, 48, 255))
        bmp.font.bold  = false
        bmp.font.size  = 11
        bmp.font.color = Color.new(85, 65, 125)
        bmp.draw_text(0, fy + 4, PANEL_W, 12, "#{cursor + 1} / #{items.length}", 1)
      end

      # ── Tooltip draw ─────────────────────────────────────────────

      DESC_LINE_H    = 13    # px per description line
      DESC_MAX_VIS   = 3     # visible lines before scrolling kicks in
      DESC_DELAY     = 1.2   # seconds before scrolling starts
      DESC_SPEED     = 12.0  # pixels per second scroll speed
      DESC_PAUSE     = 2.0   # seconds to pause at top/bottom extremities

      def self._draw_tooltip(spr, t, active_id, phase, cell_sx, cell_sy, sw, sh, hover_time = 0.0)
        is_owned  = t["owned"] ? true : false
        is_hidden = t["hidden"] && !is_owned
        name   = is_hidden ? "???" : t["name"].to_s
        effect = is_hidden ? "" : t["effect"].to_s
        desc   = is_hidden ? "This title has not been discovered yet." : t["description"].to_s
        prog   = is_hidden ? nil : t["progress"]
        prog_label = t["progress_label"].to_s

        effect_label = case effect
          when "gradient"  then "Gradient"
          when "tricolor"  then "Tricolor"
          when "rainbow"   then "Rainbow"
          when "shadow"    then "Shadow"
          when "outline"   then "Outline"
          when "solid"     then "Solid"
          else effect.empty? ? "Solid" : effect.capitalize
        end

        # Wrap description — measure with bitmap for accurate width
        desc_lines = []
        unless desc.empty?
          mb = spr.bitmap
          pbSetSmallFont(mb) rescue nil
          mb.font.size = 12
          usable_w = TT_W - TT_PAD * 2 - 6  # 6px safety margin for rendering
          words = desc.split(" ")
          line  = ""
          words.each do |w|
            test = line.empty? ? w : "#{line} #{w}"
            tw   = (mb.text_size(test).width rescue test.length * 7)
            if tw > usable_w && !line.empty?
              desc_lines << line
              line = w
            else
              line = test
            end
          end
          desc_lines << line unless line.empty?
        end

        has_progress  = prog.is_a?(Numeric)
        unlock_tiers  = t["unlock_tiers"]
        tier_rewards  = t["tier_rewards"]
        tier_claimed  = (t["tier_claimed"] || 0).to_i
        has_tiers     = unlock_tiers.is_a?(Array) && unlock_tiers.length >= 3
        num_tiers     = has_tiers ? unlock_tiers.length : 0
        is_gilded     = t["gilded"] ? true : false
        vis_desc      = [desc_lines.length, DESC_MAX_VIS].min

        # Compute tooltip height (fixed based on visible lines, not total)
        tt_h  = TT_PAD          # top padding
        tt_h += 18              # title name
        tt_h += 14 unless is_owned  # "Locked" label
        tt_h += 2               # gap
        tt_h += 16              # effect label
        tt_h += 6               # separator
        tt_h += vis_desc * DESC_LINE_H unless desc_lines.empty?
        tt_h += 4               # gap before progress
        if has_tiers && has_progress
          tt_h += 14            # progress label
          tt_h += 10            # bar
          tt_h += 4             # gap
          # Show tiers 1-3 always; show tier 4 only if claimed (secret)
          visible_tiers = tier_claimed >= 3 && num_tiers >= 4 ? 4 : 3
          tt_h += 13 * visible_tiers
        elsif has_progress
          tt_h += 14            # bar label
          tt_h += 10            # bar
        end
        tt_h += TT_PAD          # bottom padding
        tt_h = [tt_h, 60].max

        # Position tooltip
        tt_x = cell_sx + CELL_W + 6
        tt_x = cell_sx - TT_W - 6 if tt_x + TT_W > sw - 2
        tt_y = cell_sy
        tt_y = sh - tt_h - 4 if tt_y + tt_h > sh - 2
        tt_y = [tt_y, 2].max

        spr.x = tt_x
        spr.y = tt_y

        if spr.bitmap.nil? || spr.bitmap.disposed? || spr.bitmap.height < tt_h
          spr.bitmap.dispose rescue nil
          spr.bitmap = Bitmap.new(TT_W, tt_h)
        end
        bmp = spr.bitmap
        bmp.clear

        # Background
        bmp.fill_rect(0, 0, TT_W, tt_h, Color.new(110, 60, 185, 255))
        bmp.fill_rect(2, 2, TT_W - 4, tt_h - 4, Color.new(10, 6, 20, 255))

        y = TT_PAD

        # Title name
        col = is_owned ? _title_color(t, phase) : Color.new(60, 45, 85)
        bmp.font.bold  = true
        bmp.font.size  = 13
        bmp.font.color = Color.new(0, 0, 0, 120)
        bmp.draw_text(TT_PAD + 1, y + 1, TT_W - TT_PAD * 2, 16, name)
        bmp.font.color = col
        bmp.draw_text(TT_PAD,     y,     TT_W - TT_PAD * 2, 16, name)
        y += 18

        # "Locked" label for unowned titles
        unless is_owned
          pbSetSmallFont(bmp) rescue nil
          bmp.font.size  = 12
          bmp.font.color = Color.new(120, 70, 70)
          bmp.draw_text(TT_PAD, y, TT_W - TT_PAD * 2, 13, "Locked")
          y += 14
        end

        # Effect label
        pbSetSmallFont(bmp) rescue nil
        bmp.font.size  = 14
        bmp.font.color = Color.new(140, 110, 180)
        eff_text = effect_label.empty? ? "" : "Effect: #{effect_label}"
        bmp.draw_text(TT_PAD, y, TT_W - TT_PAD * 2, 14, eff_text)
        y += 16

        # Separator
        bmp.fill_rect(TT_PAD, y + 2, TT_W - TT_PAD * 2, 1,
                      Color.new(70, 45, 110, 180))
        y += 6

        # Description — scrolling if more than DESC_MAX_VIS lines
        unless desc_lines.empty?
          desc_area_h  = vis_desc * DESC_LINE_H
          total_desc_h = desc_lines.length * DESC_LINE_H
          desc_w       = TT_W - TT_PAD * 2

          # Compute scroll offset with pauses at extremities
          desc_scroll = 0
          if desc_lines.length > DESC_MAX_VIS
            overflow    = total_desc_h - desc_area_h
            scroll_time = hover_time - DESC_DELAY
            if scroll_time > 0
              # Each half-cycle: scroll overflow px + pause DESC_PAUSE seconds
              scroll_dur  = overflow / DESC_SPEED   # time to scroll one direction
              half_cycle  = scroll_dur + DESC_PAUSE # scroll + pause at end
              full_cycle  = half_cycle * 2           # down-pause-up-pause
              t_in_cycle  = scroll_time % full_cycle

              if t_in_cycle < scroll_dur
                # Scrolling down
                desc_scroll = (t_in_cycle * DESC_SPEED).to_i
              elsif t_in_cycle < half_cycle
                # Paused at bottom
                desc_scroll = overflow
              elsif t_in_cycle < half_cycle + scroll_dur
                # Scrolling up
                desc_scroll = overflow - ((t_in_cycle - half_cycle) * DESC_SPEED).to_i
              else
                # Paused at top
                desc_scroll = 0
              end
              desc_scroll = desc_scroll.clamp(0, overflow)
            end
          end

          # Draw lines directly, then paint over any overflow
          pbSetSmallFont(bmp) rescue nil
          bmp.font.size  = 12
          bmp.font.color = Color.new(195, 175, 230)
          desc_lines.each_with_index do |line, li|
            ly = y + li * DESC_LINE_H - desc_scroll
            next if ly + DESC_LINE_H <= y          # fully above window
            next if ly >= y + desc_area_h          # fully below window
            bmp.draw_text(TT_PAD, ly, desc_w, DESC_LINE_H, line)
          end

          # Paint over any partial-line spillover above/below the desc window
          bg = Color.new(10, 6, 20, 255)
          bmp.fill_rect(TT_PAD, y - DESC_LINE_H, desc_w, DESC_LINE_H, bg) if desc_scroll > 0
          bmp.fill_rect(TT_PAD, y + desc_area_h, desc_w, DESC_LINE_H, bg)

          # Fade edges when scrolling (top/bottom gradient hints)
          if desc_scroll > 0
            bmp.fill_rect(TT_PAD, y, desc_w, 2,
                          Color.new(10, 6, 20, 200))
          end
          if desc_scroll < (total_desc_h - desc_area_h)
            bmp.fill_rect(TT_PAD, y + desc_area_h - 2, desc_w, 2,
                          Color.new(10, 6, 20, 200))
          end

          y += desc_area_h
        end

        y += 4

        # Progress — tiered or simple
        if has_tiers && has_progress
          frac = prog.to_f.clamp(0.0, 1.0)
          current_val = (t["progress_current"] || 0).to_i
          max_val     = unlock_tiers[2]
          bmp.font.size  = 12
          bmp.font.color = Color.new(140, 110, 180)
          # Format numbers for readability
          fmt_cur = _fmt_number(current_val)
          fmt_max = _fmt_number(max_val)
          bmp.draw_text(TT_PAD, y, TT_W - TT_PAD * 2, 13,
                        "Progress: #{fmt_cur} / #{fmt_max}")
          y += 14

          bar_w = TT_W - TT_PAD * 2
          bar_h = 7
          bar_x = TT_PAD

          # Bar background
          bmp.fill_rect(bar_x, y, bar_w, bar_h, Color.new(35, 20, 60, 220))

          # Fill
          fill_w = (bar_w * frac).to_i
          if fill_w > 0
            bmp.fill_rect(bar_x, y, fill_w, bar_h, Color.new(150, 90, 240, 240))
          end

          # Tier markers on bar
          3.times do |i|
            tier_frac = unlock_tiers[i].to_f / max_val
            mx = bar_x + (bar_w * tier_frac).to_i
            claimed = (i + 1) <= tier_claimed
            mc = claimed ? Color.new(100, 255, 100) : Color.new(180, 140, 220)
            bmp.fill_rect(mx - 1, y - 2, 2, bar_h + 4, mc)
          end

          # Bar border
          bmp.fill_rect(bar_x, y, bar_w, 1, Color.new(80, 50, 120, 180))
          bmp.fill_rect(bar_x, y + bar_h - 1, bar_w, 1, Color.new(80, 50, 120, 180))
          bmp.fill_rect(bar_x, y, 1, bar_h, Color.new(80, 50, 120, 180))
          bmp.fill_rect(bar_x + bar_w - 1, y, 1, bar_h, Color.new(80, 50, 120, 180))
          y += bar_h + 4

          # Tier reward lines (3 always shown; 4th only if tier 3 claimed and tier 4 exists)
          tier_labels = tier_rewards || ["200 Plat", "3 Cases + 1K Plat", "Title", "Gilded"]
          show_count = tier_claimed >= 3 && num_tiers >= 4 ? 4 : [num_tiers, 3].min
          show_count.times do |i|
            claimed = (i + 1) <= tier_claimed
            reached = unlock_tiers[i] && current_val >= unlock_tiers[i]
            bmp.font.size = 11
            if i == 3
              # Tier 4 — gilded: gold color scheme
              if claimed
                bmp.font.color = Color.new(255, 215, 0)
                prefix = "[*]"
              else
                bmp.font.color = Color.new(160, 130, 50)
                prefix = "[?]"
              end
            elsif claimed
              bmp.font.color = Color.new(100, 255, 100)
              prefix = "[x]"
            elsif reached
              bmp.font.color = Color.new(255, 200, 80)
              prefix = "[ ]"
            else
              bmp.font.color = Color.new(80, 60, 120)
              prefix = "[ ]"
            end
            thr = unlock_tiers[i] || 0
            thr_str = _fmt_number(thr)
            rlabel = tier_labels[i] || "???"
            label = "#{prefix} #{thr_str} — #{rlabel}"
            bmp.draw_text(TT_PAD, y, TT_W - TT_PAD * 2, 13, label)
            y += 13
          end

        elsif has_progress
          frac = prog.to_f.clamp(0.0, 1.0)
          bmp.font.size  = 12
          bmp.font.color = Color.new(140, 110, 180)
          label_str = prog_label.empty? ? "#{(frac * 100).to_i}%" : prog_label
          bmp.draw_text(TT_PAD, y, TT_W - TT_PAD * 2, 13, "Progress: #{label_str}")
          y += 14
          bar_w = TT_W - TT_PAD * 2
          bar_h = 7
          bmp.fill_rect(TT_PAD,     y, bar_w,               bar_h,
                        Color.new(35, 20, 60, 220))
          fill_w = (bar_w * frac).to_i
          if fill_w > 0
            bmp.fill_rect(TT_PAD, y, fill_w, bar_h,
                          Color.new(150, 90, 240, 240))
          end
          bmp.fill_rect(TT_PAD,              y,              bar_w, 1, Color.new(80, 50, 120, 180))
          bmp.fill_rect(TT_PAD,              y + bar_h - 1,  bar_w, 1, Color.new(80, 50, 120, 180))
          bmp.fill_rect(TT_PAD,              y,              1, bar_h, Color.new(80, 50, 120, 180))
          bmp.fill_rect(TT_PAD + bar_w - 1,  y,              1, bar_h, Color.new(80, 50, 120, 180))
        end
      rescue => e
        # silently skip tooltip on error
      end

      # ── Helpers ───────────────────────────────────────────────────

      def self._draw_gilded_plate(bmp, x, y, w, h, phase)
        ph = phase % 100.0
        p1 = (Math.sin(ph * 2.5) + 1.0) / 2.0
        p2 = (Math.sin(ph * 1.1 + 1.2) + 1.0) / 2.0
        glow = p1 * 0.6 + p2 * 0.4
        br = (30 + glow * 45).to_i; bg = (22 + glow * 38).to_i
        bmp.fill_rect(x, y, w, h, Color.new(br, bg, 5))
        tr = (160 + glow * 95).to_i; tg = (130 + glow * 80).to_i; tb = (25 + glow * 45).to_i
        bmp.fill_rect(x + 1, y, w - 2, 1, Color.new(tr, tg, tb))
        bmp.fill_rect(x + 1, y + 1, w - 2, 1, Color.new(tr - 50, tg - 40, [tb - 10, 0].max))
        bmp.fill_rect(x + 1, y + h - 2, w - 2, 1, Color.new((65 + glow * 30).to_i, (50 + glow * 22).to_i, 12))
        bmp.fill_rect(x + 1, y + h - 1, w - 2, 1, Color.new(35, 25, 8))
        bmp.fill_rect(x, y + 1, 1, h - 2, Color.new((140 + glow * 60).to_i, (115 + glow * 50).to_i, (20 + glow * 25).to_i))
        bmp.fill_rect(x + w - 1, y + 1, 1, h - 2, Color.new((85 + glow * 35).to_i, (60 + glow * 28).to_i, 15))
        inner_x = x + 2; inner_w = w - 4; mid_y = y + h / 2
        (2...h - 2).each do |dy|
          py = y + dy; dist = (py - mid_y).abs.to_f / (h / 2.0)
          bright = (1.0 - dist) * (0.5 + glow * 0.5)
          r = (100 + bright * 130).to_i.clamp(0, 240)
          g = (75 + bright * 105).to_i.clamp(0, 190)
          b = (10 + bright * 25).to_i.clamp(0, 40)
          bmp.fill_rect(inner_x, py, inner_w, 1, Color.new(r, g, b))
        end
        cr = (200 + glow * 55).to_i; cg = (170 + glow * 50).to_i
        bmp.fill_rect(x + 1, y + 1, 2, 2, Color.new(cr, cg, 45))
        bmp.fill_rect(x + w - 3, y + 1, 2, 2, Color.new(cr, cg, 45))
        bmp.fill_rect(x + 1, y + h - 3, 2, 2, Color.new((160 + glow * 40).to_i, (130 + glow * 35).to_i, 30))
        bmp.fill_rect(x + w - 3, y + h - 3, 2, 2, Color.new((160 + glow * 40).to_i, (130 + glow * 35).to_i, 30))
      end

      def self._draw_border(bmp, x, y, w, h, color, thickness)
        bmp.fill_rect(x,         y,         w, thickness, color)
        bmp.fill_rect(x,         y + h - thickness, w, thickness, color)
        bmp.fill_rect(x,         y,         thickness, h, color)
        bmp.fill_rect(x + w - thickness, y, thickness, h, color)
      end

      def self._fmt_number(n)
        n = n.to_i
        if n >= 1_000_000
          "#{(n / 1_000_000.0).round(1)}M"
        elsif n >= 10_000
          "#{(n / 1_000.0).round(1)}K"
        else
          n.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        end
      end

      def self._cell_at(lx, ly, scroll_row, total_items)
        grid_right = PAD + COLS * (CELL_W + CELL_GAP) - CELL_GAP
        return nil if lx < PAD || lx >= grid_right
        return nil if ly < GRID_Y || ly >= GRID_Y + ROWS_VIS * ROW_PITCH

        rel_x     = lx - PAD
        rel_y     = ly - GRID_Y
        col       = rel_x / (CELL_W + CELL_GAP)
        cx_offset = rel_x % (CELL_W + CELL_GAP)
        return nil if col >= COLS || cx_offset >= CELL_W

        row       = rel_y / ROW_PITCH
        cy_offset = rel_y % ROW_PITCH
        return nil if row >= ROWS_VIS || cy_offset >= CELL_H

        idx = (scroll_row + row) * COLS + col
        idx < total_items ? idx : nil
      end

      def self._thumb_h(total_rows, track_h)
        [track_h * ROWS_VIS / [total_rows, 1].max, 16].max
      end

      def self._thumb_y(scroll_row, total_rows, track_h, th)
        max_sr = [total_rows - ROWS_VIS, 1].max
        ((track_h - th) * scroll_row / max_sr).to_i
      end

      def self._title_color(td, phase, alpha = 255)
        return Color.new(180, 160, 220, alpha) unless td.is_a?(Hash)
        c1     = td["color1"] || [255, 255, 255]
        c2     = td["color2"] || c1
        effect = td["effect"].to_s
        speed  = (td["speed"] || 0.3).to_f

        case effect
        when "solid", "outline"
          Color.new(c1[0].to_i, c1[1].to_i, c1[2].to_i, alpha)
        when "gradient"
          t = (Math.sin(phase * speed * Math::PI * 2) + 1.0) / 2.0
          Color.new(_lerp(c1[0], c2[0], t), _lerp(c1[1], c2[1], t),
                    _lerp(c1[2], c2[2], t), alpha)
        when "tricolor"
          c3 = td["color3"] || c2
          p2 = (phase * speed * 3.0) % 3.0
          ca, cb, t = if    p2 < 1.0 then [c1, c2, p2]
                      elsif p2 < 2.0 then [c2, c3, p2 - 1.0]
                      else                [c3, c1, p2 - 2.0]
                      end
          t = (1.0 - Math.cos(t * Math::PI)) / 2.0
          Color.new(_lerp(ca[0], cb[0], t), _lerp(ca[1], cb[1], t),
                    _lerp(ca[2], cb[2], t), alpha)
        when "rainbow"
          hue = (phase * [speed, 0.1].max * 360.0) % 360.0
          r, g, b = _hue_to_rgb(hue)
          Color.new(r, g, b, alpha)
        when "shadow"
          Color.new(75, 60, 95, alpha)
        else
          Color.new(255, 255, 255, alpha)
        end
      rescue
        Color.new(255, 255, 255, alpha)
      end

      def self._lerp(a, b, t)
        (a.to_i + (b.to_i - a.to_i) * t).to_i.clamp(0, 255)
      end

      def self._hue_to_rgb(h)
        h = h.to_f / 60.0
        i = h.floor % 6
        f = h - h.floor
        q = 1.0 - f
        case i
        when 0 then [255, (f * 255).to_i, 0]
        when 1 then [(q * 255).to_i, 255, 0]
        when 2 then [0, 255, (f * 255).to_i]
        when 3 then [0, (q * 255).to_i, 255]
        when 4 then [(f * 255).to_i, 0, 255]
        when 5 then [255, 0, (q * 255).to_i]
        else        [255, 255, 255]
        end
      end

    end
  end

  # ── Override ProfilePanel._handle_change_title ────────────────────

  module MultiplayerUI
    module ProfilePanel
      def self._handle_change_title
        titles    = (MultiplayerClient.own_titles rescue [])
        active_id = (@data && @data["active_title"] && @data["active_title"]["id"]).to_s

        result = MultiplayerUI::TitleSelectUI.open(titles, active_id)
        return if result.nil?

        if result.empty? || result == active_id
          MultiplayerClient.equip_title("") rescue nil
        else
          MultiplayerClient.equip_title(result) rescue nil
        end

        close
        MultiplayerUI::ProfilePanel.open(uuid: "self")
      rescue => e
        # silently recover
      end
    end
  end

end
