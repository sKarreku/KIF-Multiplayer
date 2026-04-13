#===============================================================================
# KIF Cases — Case Selection Grid (6x2)
# File: 011_Cases/004_CaseSelectScreen.rb
#
# F7 opens this screen. Player picks a case type from a 6×2 grid.
# 3 active slots (PokéCase, MegaCase, MoveCase), 9 locked.
# Each cell shows: pixel-art case, name, price, inventory count.
#===============================================================================

module KIFCases
  class CaseSelectScreen
    GRID_COLS = 6
    GRID_ROWS = 2
    CELL_W    = 78
    CELL_H    = 100
    CELL_PAD  = 6
    CURSOR_THICK = 3

    # Ordered slot layout: first 3 are real case types, rest are locked
    SLOTS = [:poke, :mega, :move,
             :locked, :locked, :locked,
             :locked, :locked, :locked,
             :locked, :locked, :locked].freeze

    def self.open
      new.run
    end

    def initialize
      @viewport = nil
      @sprites  = {}
      @cursor   = 0   # selected cell index (0..11)
    end

    def run
      KIFCases.mark_open
      KIFCaseInventory.request_sync rescue nil

      _setup_viewport
      _create_bg
      _create_header
      _create_grid
      _create_cursor
      _create_footer

      loop do
        Graphics.update
        Input.update

        break if KIFCases.close_requested?
        break if defined?(Input::F7) && Input.trigger?(Input::F7)
        break if Input.trigger?(Input::BACK)
        break if (Input.trigger?(Input::MOUSERIGHT) rescue false)

        _handle_input
        _handle_mouse
      end

      KIFCases.mark_closed
      _dispose_all
    end

    private

    # ── Input ────────────────────────────────────────────────────────────────
    def _handle_input
      old = @cursor
      if Input.trigger?(Input::RIGHT)
        @cursor += 1 if @cursor % GRID_COLS < GRID_COLS - 1
      elsif Input.trigger?(Input::LEFT)
        @cursor -= 1 if @cursor % GRID_COLS > 0
      elsif Input.trigger?(Input::DOWN)
        @cursor += GRID_COLS if @cursor < GRID_COLS
      elsif Input.trigger?(Input::UP)
        @cursor -= GRID_COLS if @cursor >= GRID_COLS
      end
      _update_cursor if @cursor != old

      if Input.trigger?(Input::C)
        slot = SLOTS[@cursor]
        if slot == :locked
          pbSEPlay("GUI sel buzzer", 80) rescue nil
        else
          pbSEPlay("GUI sel decision", 80) rescue nil
          KIFCases.mark_closed
          _dispose_all
          # Open the specific case screen
          KIFCases::CaseScreen.open(slot)
          return
        end
      end
    end

    # ── Mouse ────────────────────────────────────────────────────────────────
    def _handle_mouse
      mx = (Input.mouse_x rescue nil)
      my = (Input.mouse_y rescue nil)
      return unless mx && my && @grid_x

      # Check if mouse is over any cell
      SLOTS.each_with_index do |_slot, i|
        col = i % GRID_COLS
        row = i / GRID_COLS
        cx = @grid_x + col * (CELL_W + CELL_PAD)
        cy = @grid_y + row * (CELL_H + CELL_PAD)

        if mx >= cx && mx < cx + CELL_W && my >= cy && my < cy + CELL_H
          # Mouse is over this cell — move cursor if different
          if @cursor != i
            @cursor = i
            _update_cursor
          end

          # Left-click to select
          if (Input.trigger?(Input::MOUSELEFT) rescue false)
            slot = SLOTS[@cursor]
            if slot == :locked
              pbSEPlay("GUI sel buzzer", 80) rescue nil
            else
              pbSEPlay("GUI sel decision", 80) rescue nil
              KIFCases.mark_closed
              _dispose_all
              KIFCases::CaseScreen.open(slot)
              return
            end
          end
          break
        end
      end
    end

    # ── Viewport ─────────────────────────────────────────────────────────────
    def _setup_viewport
      @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @viewport.z = 99_990
    end

    # ── Background ───────────────────────────────────────────────────────────
    def _create_bg
      bmp = Bitmap.new(Graphics.width, Graphics.height)
      bmp.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(8, 8, 24, 235))
      @sprites[:bg] = _spr(bmp, 0, 0)
    end

    # ── Header ───────────────────────────────────────────────────────────────
    def _create_header
      w = Graphics.width
      bmp = Bitmap.new(w, 52)
      bmp.fill_rect(0, 0, w, 52, Color.new(18, 18, 48, 255))
      bmp.fill_rect(0, 50, w, 2, Color.new(200, 160, 0, 200))
      pbSetSystemFont(bmp) if defined?(pbSetSystemFont)
      bmp.font.size  = 20
      bmp.font.bold  = true
      bmp.font.color = Color.new(0, 0, 0, 150)
      bmp.draw_text(21, 11, 300, 36, "SELECT A CASE", 0)
      bmp.font.color = Color.new(255, 215, 0, 255)
      bmp.draw_text(20, 10, 300, 36, "SELECT A CASE", 0)

      # Platinum balance on right
      bal = MultiplayerPlatinum.cached_balance rescue 0
      bmp.font.size  = 15
      bmp.font.bold  = true
      bmp.font.color = Color.new(255, 215, 0, 255)
      bmp.draw_text(0, 12, w - 16, 36, "#{bal} Platinum", 2)

      @sprites[:header] = _spr(bmp, 0, 0)
    end

    # ── Grid ─────────────────────────────────────────────────────────────────
    def _create_grid
      grid_w = GRID_COLS * (CELL_W + CELL_PAD) - CELL_PAD
      grid_h = GRID_ROWS * (CELL_H + CELL_PAD) - CELL_PAD
      @grid_x = (Graphics.width - grid_w) / 2
      @grid_y = 68

      SLOTS.each_with_index do |slot, i|
        col = i % GRID_COLS
        row = i / GRID_COLS
        cx = @grid_x + col * (CELL_W + CELL_PAD)
        cy = @grid_y + row * (CELL_H + CELL_PAD)
        bmp = _render_cell(slot, i)
        @sprites["cell_#{i}".to_sym] = _spr(bmp, cx, cy)
      end
    end

    def _render_cell(slot, index)
      bmp = Bitmap.new(CELL_W, CELL_H)
      if slot == :locked
        _render_locked_cell(bmp)
      else
        _render_case_cell(bmp, slot)
      end
      bmp
    end

    def _render_locked_cell(bmp)
      bmp.fill_rect(0, 0, CELL_W, CELL_H, Color.new(30, 30, 50, 200))
      bmp.fill_rect(1, 1, CELL_W - 2, CELL_H - 2, Color.new(20, 20, 35, 220))
      pbSetSystemFont(bmp) if defined?(pbSetSystemFont)

      # Lock icon (simple padlock pixel art)
      lx = CELL_W / 2 - 8
      ly = 22
      c = Color.new(80, 80, 100, 180)
      # Shackle (arch)
      bmp.fill_rect(lx + 4,  ly,     8, 2, c)
      bmp.fill_rect(lx + 2,  ly + 2, 2, 6, c)
      bmp.fill_rect(lx + 12, ly + 2, 2, 6, c)
      # Body (rectangle)
      bmp.fill_rect(lx, ly + 8, 16, 14, c)
      # Keyhole
      kc = Color.new(20, 20, 35, 220)
      bmp.fill_rect(lx + 6, ly + 12, 4, 3, kc)
      bmp.fill_rect(lx + 7, ly + 15, 2, 3, kc)

      bmp.font.size  = 11
      bmp.font.color = Color.new(80, 80, 100, 180)
      bmp.draw_text(0, 58, CELL_W, 16, "Coming", 1)
      bmp.draw_text(0, 72, CELL_W, 16, "Soon", 1)
    end

    def _render_case_cell(bmp, case_type)
      cdef = KIFCases::CASE_DEFS[case_type]
      rgb  = cdef[:color_rgb]
      main_color = Color.new(rgb[0], rgb[1], rgb[2], 255)
      dark_color = Color.new(rgb[0] / 2, rgb[1] / 2, rgb[2] / 2, 255)
      bg_color   = Color.new(rgb[0] / 6, rgb[1] / 6, rgb[2] / 6, 240)

      # Cell background
      bmp.fill_rect(0, 0, CELL_W, CELL_H, dark_color)
      bmp.fill_rect(1, 1, CELL_W - 2, CELL_H - 2, bg_color)

      # Draw case pixel art (centered, y=6)
      _draw_case_art(bmp, CELL_W / 2 - 16, 6, case_type, main_color, dark_color)

      # Name
      pbSetSystemFont(bmp) if defined?(pbSetSystemFont)
      bmp.font.size  = 12
      bmp.font.bold  = true
      bmp.font.color = main_color
      bmp.draw_text(0, 48, CELL_W, 16, cdef[:name], 1)

      # Price
      bmp.font.size  = 10
      bmp.font.bold  = false
      bmp.font.color = Color.new(255, 215, 0, 220)
      bmp.draw_text(0, 63, CELL_W, 14, "#{cdef[:cost]} Plat", 1)

      # Inventory count
      inv = KIFCaseInventory.count(case_type) rescue 0
      bmp.font.size  = 10
      bmp.font.color = inv > 0 ? Color.new(180, 255, 180, 230) : Color.new(120, 120, 140, 180)
      bmp.draw_text(0, 78, CELL_W, 14, "Owned: #{inv}", 1)
    end

    # ── Case pixel art (32x36 briefcase with emblem) ─────────────────────────
    def _draw_case_art(bmp, ix, iy, case_type, main_col, dark_col)
      # Shadow
      sh = Color.new(0, 0, 0, 60)
      bmp.fill_rect(ix + 2, iy + 2, 32, 36, sh)

      # Handle (arch at top center)
      bmp.fill_rect(ix + 11, iy,     10, 3, dark_col)
      bmp.fill_rect(ix + 9,  iy + 3,  2, 4, dark_col)
      bmp.fill_rect(ix + 21, iy + 3,  2, 4, dark_col)

      # Body
      bmp.fill_rect(ix + 1, iy + 7, 30, 26, main_col)
      # Darker bottom half
      bmp.fill_rect(ix + 1, iy + 20, 30, 13, dark_col)
      # Latch line
      bmp.fill_rect(ix + 1, iy + 19, 30, 2, Color.new(0, 0, 0, 80))
      # Clasp
      bmp.fill_rect(ix + 13, iy + 17, 6, 6, Color.new(255, 215, 0, 220))
      bmp.fill_rect(ix + 14, iy + 18, 4, 4, Color.new(200, 160, 0, 220))

      # Emblem (type-specific icon inside the case body)
      case case_type
      when :poke
        _draw_pokeball_emblem(bmp, ix + 10, iy + 9)
      when :mega
        _draw_mega_emblem(bmp, ix + 10, iy + 9)
      when :move
        _draw_tm_emblem(bmp, ix + 10, iy + 9)
      end
    end

    # Pokéball emblem (12x10)
    def _draw_pokeball_emblem(bmp, x, y)
      w = Color.new(255, 255, 255, 220)
      r = Color.new(220, 50, 50, 220)
      k = Color.new(0, 0, 0, 180)
      # Top half (red)
      bmp.fill_rect(x + 2, y,     8, 1, r)
      bmp.fill_rect(x + 1, y + 1, 10, 1, r)
      bmp.fill_rect(x,     y + 2, 12, 2, r)
      # Center line
      bmp.fill_rect(x,     y + 4, 12, 2, k)
      # Center button
      bmp.fill_rect(x + 4, y + 3, 4, 4, w)
      bmp.fill_rect(x + 5, y + 4, 2, 2, k)
      # Bottom half (white)
      bmp.fill_rect(x,     y + 6, 12, 2, w)
      bmp.fill_rect(x + 1, y + 8, 10, 1, w)
      bmp.fill_rect(x + 2, y + 9, 8, 1, w)
    end

    # Mega evolution emblem — DNA helix (12x10)
    def _draw_mega_emblem(bmp, x, y)
      m = Color.new(255, 180, 255, 230)
      d = Color.new(180, 80, 255, 230)
      # Simplified double helix
      bmp.fill_rect(x + 1, y,     3, 2, m)
      bmp.fill_rect(x + 8, y,     3, 2, d)
      bmp.fill_rect(x + 3, y + 2, 6, 2, Color.new(220, 150, 255, 200))
      bmp.fill_rect(x + 5, y + 3, 2, 2, Color.new(255, 255, 255, 200))
      bmp.fill_rect(x + 8, y + 4, 3, 2, m)
      bmp.fill_rect(x + 1, y + 4, 3, 2, d)
      bmp.fill_rect(x + 3, y + 6, 6, 2, Color.new(220, 150, 255, 200))
      bmp.fill_rect(x + 5, y + 7, 2, 2, Color.new(255, 255, 255, 200))
      bmp.fill_rect(x + 1, y + 8, 3, 2, m)
      bmp.fill_rect(x + 8, y + 8, 3, 2, d)
    end

    # TM disc emblem (12x10)
    def _draw_tm_emblem(bmp, x, y)
      c1 = Color.new(80, 200, 80, 230)
      c2 = Color.new(40, 140, 40, 230)
      w  = Color.new(255, 255, 255, 200)
      # Disc outline
      bmp.fill_rect(x + 3, y,     6, 1, c1)
      bmp.fill_rect(x + 1, y + 1, 10, 1, c1)
      bmp.fill_rect(x,     y + 2, 12, 6, c1)
      bmp.fill_rect(x + 1, y + 8, 10, 1, c1)
      bmp.fill_rect(x + 3, y + 9, 6, 1, c1)
      # Inner darker ring
      bmp.fill_rect(x + 3, y + 2, 6, 1, c2)
      bmp.fill_rect(x + 2, y + 3, 8, 4, c2)
      bmp.fill_rect(x + 3, y + 7, 6, 1, c2)
      # Center hole
      bmp.fill_rect(x + 5, y + 4, 2, 2, w)
      # "TM" text
      pbSetSystemFont(bmp) if defined?(pbSetSystemFont)
      bmp.font.size = 7
      bmp.font.bold = true
      bmp.font.color = w
    end

    # ── Cursor ───────────────────────────────────────────────────────────────
    def _create_cursor
      bmp = Bitmap.new(CELL_W + 4, CELL_H + 4)
      c = Color.new(255, 255, 255, 240)
      t = CURSOR_THICK
      bmp.fill_rect(0, 0, bmp.width, t, c)
      bmp.fill_rect(0, bmp.height - t, bmp.width, t, c)
      bmp.fill_rect(0, 0, t, bmp.height, c)
      bmp.fill_rect(bmp.width - t, 0, t, bmp.height, c)
      @sprites[:cursor] = _spr(bmp, 0, 0)
      @sprites[:cursor].z = @viewport.z + 2
      _update_cursor
    end

    def _update_cursor
      col = @cursor % GRID_COLS
      row = @cursor / GRID_COLS
      cx = @grid_x + col * (CELL_W + CELL_PAD) - 2
      cy = @grid_y + row * (CELL_H + CELL_PAD) - 2
      @sprites[:cursor].x = cx
      @sprites[:cursor].y = cy
      pbSEPlay("GUI sel cursor", 60) rescue nil

      # Update footer with selected case info
      _update_footer
    end

    # ── Footer (info about selected case) ────────────────────────────────────
    def _create_footer
      @sprites[:footer] = _spr(Bitmap.new(Graphics.width, 60), 0, Graphics.height - 60)
      _update_footer
    end

    def _update_footer
      return unless @sprites[:footer]
      old = @sprites[:footer].bitmap
      old.clear if old && !old.disposed?

      bmp = old && !old.disposed? ? old : Bitmap.new(Graphics.width, 60)
      bmp.fill_rect(0, 0, Graphics.width, 60, Color.new(12, 12, 36, 230))
      bmp.fill_rect(0, 0, Graphics.width, 1, Color.new(100, 100, 160, 120))
      pbSetSystemFont(bmp) if defined?(pbSetSystemFont)

      slot = SLOTS[@cursor]
      if slot == :locked
        bmp.font.size  = 14
        bmp.font.color = Color.new(80, 80, 100, 180)
        bmp.draw_text(0, 8, Graphics.width, 20, "This case is not yet available.", 1)
        bmp.font.size  = 12
        bmp.font.color = Color.new(80, 80, 100, 140)
        bmp.draw_text(0, 32, Graphics.width, 20, "[X / Esc] Back", 1)
      else
        cdef = KIFCases::CASE_DEFS[slot]
        rgb  = cdef[:color_rgb]
        inv  = KIFCaseInventory.count(slot) rescue 0
        pool_sz = KIFCases.pool_size_for(slot) rescue 0

        bmp.font.size  = 14
        bmp.font.bold  = true
        bmp.font.color = Color.new(rgb[0], rgb[1], rgb[2], 255)
        bmp.draw_text(20, 5, 300, 20, cdef[:name], 0)

        bmp.font.size  = 12
        bmp.font.bold  = false
        bmp.font.color = Color.new(180, 180, 200, 220)
        bmp.draw_text(20, 24, 400, 18, "#{cdef[:description]}  (#{pool_sz} items)  —  #{cdef[:cost]} Platinum each", 0)

        bmp.font.color = inv > 0 ? Color.new(180, 255, 180, 230) : Color.new(140, 140, 160, 180)
        bmp.draw_text(20, 42, 300, 16, "In inventory: #{inv}", 0)

        bmp.font.size  = 12
        bmp.font.color = Color.new(200, 200, 220, 200)
        bmp.draw_text(0, 24, Graphics.width - 16, 18, "[Z / Enter] Select    [X / Esc] Back", 2)
      end

      @sprites[:footer].bitmap = bmp
    end

    # ── Helpers ──────────────────────────────────────────────────────────────
    def _spr(bmp, x, y)
      spr = Sprite.new(@viewport)
      spr.bitmap = bmp
      spr.x = x; spr.y = y
      spr
    end

    def _dispose_all
      @sprites.each_value do |s|
        next unless s
        s.bitmap.dispose if s.bitmap && !s.bitmap.disposed?
        s.dispose rescue nil
      end
      @sprites.clear
      @viewport.dispose if @viewport && !@viewport.disposed? rescue nil
    end
  end
end
