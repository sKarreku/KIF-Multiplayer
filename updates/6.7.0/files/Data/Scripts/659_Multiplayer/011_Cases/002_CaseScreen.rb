#===============================================================================
# KIF Cases — UI Scene + Overworld HUD
# File: 011_Cases/002_CaseScreen.rb
#
# Supports three case types: :poke (PokéCase), :mega (MegaCase), :move (MoveCase)
# Actions: [Z] Buy & Open, [A] Open from inventory, [N] Buy to inventory
#===============================================================================

module KIFCases
  TILE_SIZE   = 64
  TILE_STEP   = 64
  STRIP_H     = 80
  WINNER_IDX  = 80
  TOTAL_TILES = 115
  ANIM_FRAMES = 420  # 7 seconds at 60 fps
  IDLE_SPEED  = 1.5   # pixels per frame for idle scroll

  class CaseScreen
    def self.open(case_type = :poke)
      new(case_type).run
    end

    def initialize(case_type = :poke)
      @case_type  = case_type
      @cdef       = KIFCases::CASE_DEFS[case_type] || KIFCases::CASE_DEFS[:poke]
      @viewport   = nil
      @strip_vp   = nil
      @sprites    = {}
      @strip_sprs = []
      @idle_sprs  = []
      @animating  = false
      @winner_sym  = nil
      @winner_tier = nil
    end

    def run
      KIFCases.mark_open
      _ensure_pool
      KIFCaseInventory.request_sync rescue nil

      _setup_viewport
      _create_bg
      _create_header
      _create_strip_container
      _create_arrow
      _create_info_text
      _draw_action_bar
      _refresh_balance_display
      _init_idle_scroll

      loop do
        Graphics.update
        Input.update

        break if KIFCases.close_requested?
        break if defined?(Input::F7) && Input.trigger?(Input::F7)
        break if Input.trigger?(Input::BACK)
        break if (Input.trigger?(Input::MOUSERIGHT) rescue false)

        unless @animating
          _tick_idle_scroll
          mouse_action = _check_action_bar_mouse
          if Input.trigger?(Input::C) || mouse_action == :buy_open   # [Z] Buy & Open
            begin
              _try_buy_and_open
            rescue => e
              @animating = false
              _show_msg("Error: #{e.message}")
            end
          elsif Input.trigger?(Input::A) || mouse_action == :open    # [A] Open from inventory
            begin
              _try_open_from_inventory
            rescue => e
              @animating = false
              _show_msg("Error: #{e.message}")
            end
          elsif _input_n_trigger? || mouse_action == :buy            # [N] Buy to inventory
            begin
              _try_buy_to_inventory
            rescue => e
              _show_msg("Error: #{e.message}")
            end
          end
        end
      end

      KIFCases.mark_closed
      _dispose_all
    end

    private

    # ── Helpers for case type ────────────────────────────────────────────────
    def _case_cost
      @cdef[:cost]
    end

    def _case_name
      @cdef[:name]
    end

    def _case_color(alpha = 255)
      rgb = @cdef[:color_rgb]
      Color.new(rgb[0], rgb[1], rgb[2], alpha)
    end

    def _ensure_pool
      case @case_type
      when :poke then KIFCases.build_pool
      when :mega then KIFCases.build_mega_pool
      when :move then KIFCases.build_move_pool
      end
    end

    # ── Mouse click on action bar buttons ──────────────────────────────────
    # Action bar layout (y = Graphics.height - 30, h = 30):
    #   [Z] Buy & Open:  x=0..189
    #   [A] Open:         x=192..349
    #   [N] Buy:          x=352..(w-82)
    #   [X] Back:         x=(w-78)..w  (handled by right-click / BACK)
    def _check_action_bar_mouse
      return nil unless (Input.trigger?(Input::MOUSELEFT) rescue false)
      mx = (Input.mouse_x rescue nil)
      my = (Input.mouse_y rescue nil)
      return nil unless mx && my

      bar_y = Graphics.height - 30
      return nil unless my >= bar_y && my < Graphics.height

      w = Graphics.width
      if mx < 190
        :buy_open
      elsif mx >= 192 && mx < 350
        :open
      elsif mx >= 352 && mx < w - 82
        :buy
      else
        nil
      end
    end

    def _input_n_trigger?
      # N key via Win32API GetAsyncKeyState (VK_N = 0x4E)
      @_gas ||= begin
        Win32API.new('user32', 'GetAsyncKeyState', ['i'], 'i')
      rescue
        nil
      end
      return false unless @_gas
      (@_gas.call(0x4E) & 0x01) != 0
    rescue
      false
    end

    # ── Viewport setup ───────────────────────────────────────────────────────
    def _setup_viewport
      @viewport   = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @viewport.z = 99_990
      sw = Graphics.width
      sh = Graphics.height
      sy = sh / 2 - STRIP_H / 2 - 10
      @strip_vp   = Viewport.new(0, sy, sw, STRIP_H)
      @strip_vp.z = 99_992
      @strip_y    = sy
    end

    # ── Background ───────────────────────────────────────────────────────────
    def _create_bg
      bmp = Bitmap.new(Graphics.width, Graphics.height)
      bmp.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(8, 8, 24, 228))
      @sprites[:bg] = _spr(bmp, 0, 0)
    end

    # ── Header bar ───────────────────────────────────────────────────────────
    def _create_header
      w = Graphics.width
      bmp = Bitmap.new(w, 56)
      bmp.fill_rect(0, 0, w, 56, Color.new(18, 18, 48, 255))
      bmp.fill_rect(0, 54, w, 2, _case_color(200))
      pbSetSystemFont(bmp) if defined?(pbSetSystemFont)
      _draw_gem(bmp, 12, 14, 255)
      bmp.font.size  = 22
      bmp.font.bold  = true
      bmp.font.color = Color.new(0, 0, 0, 150)
      bmp.draw_text(45, 13, 280, 36, _case_name.upcase, 0)
      bmp.font.color = _case_color
      bmp.draw_text(44, 12, 280, 36, _case_name.upcase, 0)
      @sprites[:header] = _spr(bmp, 0, 0)
      @sprites[:plat]   = _spr(Bitmap.new(200, 56), Graphics.width - 205, 0)
    end

    def _refresh_balance_display
      return unless @sprites[:plat]
      bal = MultiplayerPlatinum.cached_balance rescue 0
      bmp = Bitmap.new(200, 56)
      pbSetSystemFont(bmp) if defined?(pbSetSystemFont)
      _draw_gem(bmp, 5, 18, 255)
      bmp.font.size  = 16
      bmp.font.bold  = true
      can = bal >= _case_cost
      bmp.font.color = can ? Color.new(255, 215, 0, 255) : Color.new(220, 80, 80, 255)
      bmp.draw_text(28, 12, 170, 36, "#{bal} Platinum", 0)
      old = @sprites[:plat].bitmap
      old.dispose if old && !old.disposed?
      @sprites[:plat].bitmap = bmp
    end

    # ── Strip container ──────────────────────────────────────────────────────
    def _create_strip_container
      bmp = Bitmap.new(Graphics.width, STRIP_H)
      bmp.fill_rect(0, 0, Graphics.width, STRIP_H, Color.new(5, 5, 15, 200))
      bmp.fill_rect(0, 0, Graphics.width, 2,       Color.new(180, 180, 255, 80))
      bmp.fill_rect(0, STRIP_H - 2, Graphics.width, 2, Color.new(180, 180, 255, 80))
      @sprites[:strip_bg] = _spr(bmp, 0, @strip_y)
    end

    # ── Arrow ────────────────────────────────────────────────────────────────
    def _create_arrow
      bmp = Bitmap.new(24, 14)
      c   = Color.new(220, 30, 30, 255)
      7.times { |row| bmp.fill_rect(row * 2, row * 2, 24 - row * 4, 2, c) }
      @sprites[:arrow] = _spr(bmp, Graphics.width / 2 - 12, @strip_y - 16)
      line_bmp = Bitmap.new(4, STRIP_H)
      line_bmp.fill_rect(0, 0, 4, STRIP_H, Color.new(220, 30, 30, 160))
      @sprites[:pointer_line] = _spr(line_bmp, Graphics.width / 2 - 2, @strip_y)
    end

    # ── Info text + rarity legend ────────────────────────────────────────────
    def _create_info_text
      pool_total = KIFCases.pool_size_for(@case_type)
      inv_count  = KIFCaseInventory.count(@case_type) rescue 0

      bmp = Bitmap.new(Graphics.width - 40, 50)
      pbSetSystemFont(bmp) if defined?(pbSetSystemFont)
      bmp.font.size  = 14
      bmp.font.bold  = false
      bmp.font.color = Color.new(160, 160, 200, 210)
      bmp.draw_text(0, 0, bmp.width, 24, "#{@cdef[:description]}  (#{pool_total} items)", 1)
      bmp.font.color = Color.new(200, 200, 160, 180)
      bmp.draw_text(0, 26, bmp.width, 24,
        "Cost: #{_case_cost} Plat  |  Owned: #{inv_count}  |  [Z] Buy&Open  [A] Open  [N] Buy  [X] Back", 1)
      iy = @strip_y + STRIP_H + 20
      @sprites[:info] = _spr(bmp, 20, iy)

      # Rarity legend only for PokéCase
      _create_legend(iy + 55) if @case_type == :poke
    end

    def _create_legend(base_y)
      n       = KIFCases::RARITY_TIERS.size
      pad     = 10
      slot_w  = (Graphics.width - pad * 2) / n
      box_sz  = 10
      bmp_h   = box_sz + 13 + 12
      bmp     = Bitmap.new(Graphics.width - pad * 2, bmp_h)
      pbSetSystemFont(bmp) if defined?(pbSetSystemFont)
      bmp.font.bold = false

      KIFCases::RARITY_TIERS.each_with_index do |tier, i|
        x   = i * slot_w
        rgb = tier[:color_rgb]
        pct = "#{tier[:weight]}%"
        box_x = x + (slot_w - box_sz) / 2
        bmp.fill_rect(box_x,     0,     box_sz, box_sz, Color.new(rgb[0], rgb[1], rgb[2], 230))
        bmp.fill_rect(box_x - 1, -1,    box_sz + 2, 1,  Color.new(0, 0, 0, 100))
        bmp.fill_rect(box_x - 1, box_sz, box_sz + 2, 1, Color.new(0, 0, 0, 100))
        bmp.font.size  = 11
        bmp.font.color = Color.new(200, 200, 225, 210)
        bmp.draw_text(x, box_sz + 1, slot_w, 13, tier[:name], 1)
        bmp.font.size  = 10
        bmp.font.color = Color.new(140, 140, 170, 170)
        bmp.draw_text(x, box_sz + 14, slot_w, 12, pct, 1)
      end
      @sprites[:legend] = _spr(bmp, pad, base_y)
    end

    # ── Action bar ───────────────────────────────────────────────────────────
    def _draw_action_bar
      w   = Graphics.width
      bmp = Bitmap.new(w, 30)
      bmp.fill_rect(0, 0, w, 30, Color.new(12, 12, 36, 220))
      bmp.fill_rect(0, 0, w, 1,  Color.new(100, 100, 160, 120))
      pbSetSystemFont(bmp) if defined?(pbSetSystemFont)
      bmp.font.size = 12; bmp.font.bold = false

      bal = MultiplayerPlatinum.cached_balance rescue 0
      inv = KIFCaseInventory.count(@case_type) rescue 0
      can_buy = bal >= _case_cost

      # [Z] Buy & Open
      col_buy = can_buy ? Color.new(255, 215, 0, 230) : Color.new(220, 80, 80, 230)
      bmp.font.color = Color.new(0, 0, 0, 100)
      bmp.draw_text(9, 7, 180, 20, "[Z] Buy & Open (#{_case_cost})", 0)
      bmp.font.color = col_buy
      bmp.draw_text(8, 6, 180, 20, "[Z] Buy & Open (#{_case_cost})", 0)

      bmp.fill_rect(190, 5, 2, 20, Color.new(120, 120, 160, 100))

      # [A] Open from inventory
      col_open = inv > 0 ? Color.new(120, 220, 255, 230) : Color.new(80, 80, 100, 150)
      bmp.font.color = Color.new(0, 0, 0, 100)
      bmp.draw_text(199, 7, 150, 20, "[A] Open (#{inv} owned)", 0)
      bmp.font.color = col_open
      bmp.draw_text(198, 6, 150, 20, "[A] Open (#{inv} owned)", 0)

      bmp.fill_rect(350, 5, 2, 20, Color.new(120, 120, 160, 100))

      # [N] Buy to inventory
      bmp.font.color = Color.new(0, 0, 0, 100)
      bmp.draw_text(359, 7, 130, 20, "[N] Buy (#{_case_cost})", 0)
      bmp.font.color = can_buy ? Color.new(180, 255, 180, 230) : Color.new(80, 80, 100, 150)
      bmp.draw_text(358, 6, 130, 20, "[N] Buy (#{_case_cost})", 0)

      bmp.fill_rect(w - 80, 5, 2, 20, Color.new(120, 120, 160, 100))

      # [X] Back
      bmp.font.color = Color.new(0, 0, 0, 100)
      bmp.draw_text(w - 71, 7, 70, 20, "[X] Back", 0)
      bmp.font.color = Color.new(200, 200, 220, 220)
      bmp.draw_text(w - 72, 6, 70, 20, "[X] Back", 0)

      old = @sprites[:action_bar]&.bitmap
      old.dispose if old && !old.disposed?
      spr = @sprites[:action_bar] || _spr(nil, 0, Graphics.height - 30)
      spr.bitmap = bmp
      @sprites[:action_bar] = spr
    end

    # ── Idle scroll ──────────────────────────────────────────────────────────
    def _init_idle_scroll
      _clear_idle_sprites
      @idle_sprs = []
      x = 0.0
      while x < Graphics.width + TILE_SIZE
        _idle_add_tile(x)
        x += TILE_SIZE
      end
    end

    def _idle_add_tile(x)
      bmp = _random_tile_for_type
      spr = Sprite.new(@strip_vp)
      spr.bitmap = bmp
      spr.y = (STRIP_H - TILE_SIZE) / 2
      spr.x = x.to_i
      @idle_sprs << { spr: spr, x: x.to_f }
    end

    def _tick_idle_scroll
      return if @idle_sprs.empty?
      @idle_sprs.each do |t|
        t[:x] -= IDLE_SPEED
        t[:spr].x = t[:x].to_i
      end
      while @idle_sprs.first && @idle_sprs.first[:x] + TILE_SIZE < 0
        t = @idle_sprs.shift
        t[:spr].bitmap.dispose rescue nil
        t[:spr].dispose        rescue nil
      end
      rightmost = @idle_sprs.last ? @idle_sprs.last[:x] + TILE_SIZE : 0.0
      while rightmost < Graphics.width + TILE_SIZE
        _idle_add_tile(rightmost)
        rightmost += TILE_SIZE
      end
    end

    def _clear_idle_sprites
      return unless @idle_sprs
      @idle_sprs.each do |t|
        t[:spr].bitmap.dispose rescue nil
        t[:spr].dispose        rescue nil
      end
      @idle_sprs.clear
    end

    # ── Random tile for the current case type ────────────────────────────────
    def _random_tile_for_type
      case @case_type
      when :poke
        pool = KIFCases.build_pool
        tier = _rand_tier
        tier_pool = pool[tier]
        sp = tier_pool.empty? ? nil : tier_pool[rand(tier_pool.size)]
        _make_poke_tile(sp, tier)
      when :mega
        pool = KIFCases.build_mega_pool
        sp = pool.empty? ? nil : pool[rand(pool.size)]
        KIFCases.make_mega_tile(sp, TILE_SIZE)
      when :move
        pool = KIFCases.build_move_pool
        sp = pool.empty? ? nil : pool[rand(pool.size)]
        KIFCases.make_move_tile(sp, TILE_SIZE)
      end
    end

    def _make_result_tile(result_sym, tier_or_nil = nil)
      case @case_type
      when :poke then _make_poke_tile(result_sym, tier_or_nil || 0)
      when :mega then KIFCases.make_mega_tile(result_sym, TILE_SIZE)
      when :move then KIFCases.make_move_tile(result_sym, TILE_SIZE)
      end
    end

    # ── Case opening flows ───────────────────────────────────────────────────

    # [Z] Buy & Open — atomic server transaction
    def _try_buy_and_open
      bal = MultiplayerPlatinum.cached_balance rescue 0
      unless bal >= _case_cost
        _show_msg("Not enough Platinum!\nYou need #{_case_cost} to open a case.")
        return
      end

      @animating = true
      $PokemonGlobal.case_result = nil
      KIFCaseInventory.buy_and_open(@case_type)

      result = _wait_for_result
      _handle_result(result)
    end

    # [A] Open from inventory
    def _try_open_from_inventory
      inv = KIFCaseInventory.count(@case_type) rescue 0
      unless inv > 0
        _show_msg("You don't own any #{_case_name}s!\nBuy one first with [S] or [Z].")
        return
      end

      @animating = true
      $PokemonGlobal.case_result = nil
      KIFCaseInventory.open_from_inventory(@case_type)

      result = _wait_for_result
      _handle_result(result)
    end

    # [N] Buy to inventory (no animation)
    def _try_buy_to_inventory
      bal = MultiplayerPlatinum.cached_balance rescue 0
      unless bal >= _case_cost
        _show_msg("Not enough Platinum!\nYou need #{_case_cost} to buy a case.")
        return
      end

      success = KIFCaseInventory.buy(@case_type)
      if success
        inv = KIFCaseInventory.count(@case_type) rescue 0
        _show_msg("Purchased 1 #{_case_name}!\nYou now own #{inv}.")
      else
        _show_msg("Purchase failed.\nPlease try again.")
      end
      _refresh_balance_display
      _draw_action_bar
      _refresh_info_text
    end

    def _wait_for_result
      deadline = Time.now + 5.0
      while Time.now < deadline
        Graphics.update
        Input.update
        $multiplayer.update if $multiplayer
        _tick_idle_scroll
        if $PokemonGlobal.case_result
          result = $PokemonGlobal.case_result
          $PokemonGlobal.case_result = nil
          return result
        end
      end
      nil
    end

    def _handle_result(result)
      if result.nil?
        _show_msg("Server did not respond.\nPlease try again.")
        @animating = false
        _init_idle_scroll
        return
      end

      if result[:error]
        msg = case result[:error]
              when "INSUFFICIENT"    then "Not enough Platinum on the server."
              when "NO_INVENTORY"    then "You don't own any #{_case_name}s."
              when "NOT_REGISTERED"  then "Platinum account not found.\nReconnect and try again."
              when "COOLDOWN"        then "Please wait before opening another case."
              else "Server error: #{result[:error]}"
              end
        _show_msg(msg)
        _refresh_balance_display
        _draw_action_bar
        _refresh_info_text
        @animating = false
        _init_idle_scroll
        return
      end

      # Resolve the result
      if @case_type == :poke
        tier     = result[:tier].to_i
        position = result[:position].to_i
        winner   = KIFCases.resolve_result(:poke, tier, position)
        @winner_tier = tier
      else
        position = result[:position].to_i
        winner   = KIFCases.resolve_result(@case_type, position)
        @winner_tier = nil
      end

      if winner.nil?
        _show_msg("Error: could not determine reward.\nContact the server admin.")
        @animating = false
        _init_idle_scroll
        return
      end

      @winner_sym = winner
      _refresh_balance_display
      _draw_action_bar
      _refresh_info_text

      _run_roulette(result)
      _show_winner_panel
      _award_and_confirm

      @animating = false
      _init_idle_scroll
    end

    def _refresh_info_text
      # Rebuild info text sprite
      return unless @sprites[:info]
      old = @sprites[:info].bitmap
      old.dispose if old && !old.disposed?
      pool_total = KIFCases.pool_size_for(@case_type)
      inv_count  = KIFCaseInventory.count(@case_type) rescue 0
      bmp = Bitmap.new(Graphics.width - 40, 50)
      pbSetSystemFont(bmp) if defined?(pbSetSystemFont)
      bmp.font.size  = 14
      bmp.font.bold  = false
      bmp.font.color = Color.new(160, 160, 200, 210)
      bmp.draw_text(0, 0, bmp.width, 24, "#{@cdef[:description]}  (#{pool_total} items)", 1)
      bmp.font.color = Color.new(200, 200, 160, 180)
      bmp.draw_text(0, 26, bmp.width, 24,
        "Cost: #{_case_cost} Plat  |  Owned: #{inv_count}  |  [Z] Buy&Open  [A] Open  [N] Buy  [X] Back", 1)
      @sprites[:info].bitmap = bmp
    end

    # ── Roulette animation ───────────────────────────────────────────────────
    def _run_roulette(result)
      # Take ownership of idle sprites
      idle_data  = @idle_sprs.map { |t| { spr: t[:spr], x: t[:x].to_f } }
      @idle_sprs = []
      n_idle     = idle_data.size

      # Build roulette tiles
      roulette_tiles = _build_tile_list_for_type(result)

      right_x = idle_data.last ? idle_data.last[:x] + TILE_STEP : Graphics.width.to_f
      roulette_data = []
      roulette_tiles.each_with_index do |t, i|
        bmp = t[:bitmap]
        spr = Sprite.new(@strip_vp)
        spr.bitmap = bmp
        spr.y = (STRIP_H - TILE_SIZE) / 2
        x = right_x + i * TILE_STEP
        spr.x = x.to_i
        roulette_data << { spr: spr, x: x.to_f }
      end

      all_data     = idle_data + roulette_data
      @strip_sprs  = all_data.map { |d| d[:spr] }
      actual_winner_idx = n_idle + WINNER_IDX
      sub_offset = rand(-22..22)

      start_offset = idle_data.first ? idle_data.first[:x] : 0.0
      ptr_x        = Graphics.width / 2
      final_offset = (ptr_x - TILE_SIZE / 2.0) - actual_winner_idx * TILE_STEP + sub_offset

      prev_tile_under = ((ptr_x - start_offset) / TILE_STEP).floor
      t2_ease = 0.57

      ANIM_FRAMES.times do |frame|
        Graphics.update
        Input.update
        t   = frame.to_f / (ANIM_FRAMES - 1)
        off = start_offset + (final_offset - start_offset) * _roulette_ease(t)
        all_data.each_with_index { |d, i| d[:spr].x = (off + i * TILE_STEP).to_i }

        curr_tile = ((ptr_x - off) / TILE_STEP).floor
        if curr_tile != prev_tile_under
          prev_tile_under = curr_tile
          pitch = if t >= t2_ease
                    (90 + ((t - t2_ease) / (1.0 - t2_ease) * 40)).to_i.clamp(90, 130)
                  else
                    90
                  end
          pbSEPlay("GUI sel cursor", 70, pitch) rescue nil
        end
      end
      all_data.each_with_index { |d, i| d[:spr].x = (final_offset + i * TILE_STEP).to_i }

      # White flash
      24.times do |i|
        level = i < 12 ? (i / 11.0 * 220).to_i : ((23 - i) / 11.0 * 220).to_i
        @strip_vp.tone = Tone.new(level, level, level, 0) rescue nil
        Graphics.update
      end
      @strip_vp.tone = Tone.new(0, 0, 0, 0) rescue nil

      # White border on winner
      winner_spr = @strip_sprs[actual_winner_idx]
      if winner_spr&.bitmap && !winner_spr.bitmap.disposed?
        wc  = Color.new(255, 255, 255, 230)
        bmp = winner_spr.bitmap
        bmp.fill_rect(0, 0, TILE_SIZE, 3, wc)
        bmp.fill_rect(0, TILE_SIZE - 3, TILE_SIZE, 3, wc)
        bmp.fill_rect(0, 0, 3, TILE_SIZE, wc)
        bmp.fill_rect(TILE_SIZE - 3, 0, 3, TILE_SIZE, wc)
      end

      # Zoom pulse
      if winner_spr && !winner_spr.disposed?
        cx = (final_offset + actual_winner_idx * TILE_STEP).to_i + TILE_SIZE / 2
        cy = (STRIP_H - TILE_SIZE) / 2 + TILE_SIZE / 2
        winner_spr.ox = TILE_SIZE / 2
        winner_spr.oy = TILE_SIZE / 2
        winner_spr.x  = cx
        winner_spr.y  = cy

        zoom_seq = []
        20.times { |i| zoom_seq << 1.0 + 0.45 * Math.sin(i * Math::PI / 19.0) }
        16.times { |i| zoom_seq << 1.0 + 0.25 * Math.sin(i * Math::PI / 15.0) }
        12.times { |i| zoom_seq << 1.0 + 0.12 * Math.sin(i * Math::PI / 11.0) }
        20.times { zoom_seq << 1.0 }

        zoom_seq.each do |z|
          winner_spr.zoom_x = z
          winner_spr.zoom_y = z
          Graphics.update
          Input.update
        end
        winner_spr.zoom_x = 1.0
        winner_spr.zoom_y = 1.0
      end

      30.times { Graphics.update; Input.update }
      _clear_strip_sprites
    end

    def _roulette_ease(t)
      t1 = 0.02
      t2 = 0.57
      v  = 2.0 / (t2 - t1 + 1.0)
      d1 = v * t1 / 2.0
      d2 = d1 + v * (t2 - t1)
      if t <= t1
        (v / (2.0 * t1)) * t * t
      elsif t <= t2
        d1 + v * (t - t1)
      else
        s = (t - t2) / (1.0 - t2)
        d2 + (1.0 - d2) * (1.0 - (1.0 - s) ** 2)
      end
    end

    def _build_tile_list_for_type(result)
      TOTAL_TILES.times.map do |i|
        if i == WINNER_IDX
          { bitmap: _make_result_tile(@winner_sym, @winner_tier) }
        else
          { bitmap: _random_tile_for_type }
        end
      end
    end

    # PokéCase tile (existing Pokémon icon tile)
    def _make_poke_tile(species_sym, tier_index)
      bmp          = Bitmap.new(TILE_SIZE, TILE_SIZE)
      border_color = KIFCases.rarity_color(tier_index, 255)
      inner_color  = Color.new(228, 228, 240, 255)
      bmp.fill_rect(0, 0, TILE_SIZE, TILE_SIZE, border_color)
      bmp.fill_rect(3, 3, TILE_SIZE - 6, TILE_SIZE - 6, inner_color)
      if species_sym
        icon_file = GameData::Species.icon_filename_from_species(species_sym) rescue nil
        if icon_file
          begin
            abmp = AnimatedBitmap.new(icon_file)
            icon = abmp.deanimate
            if icon && !icon.disposed?
              fw = icon.width / 2
              fh = icon.height
              ix = (TILE_SIZE - fw) / 2
              iy = (TILE_SIZE - fh) / 2
              bmp.blt(ix, iy, icon, Rect.new(0, 0, fw, fh))
              icon.dispose
            end
            abmp.dispose rescue nil
          rescue; end
        end
      end
      bmp
    end

    def _rand_tier
      total = KIFCases::RARITY_TIERS.sum { |t| t[:weight] }
      roll  = rand(total)
      KIFCases::RARITY_TIERS.each_with_index do |t, i|
        roll -= t[:weight]
        return i if roll < 0
      end
      0
    end

    # ── Winner panel ─────────────────────────────────────────────────────────
    def _show_winner_panel
      return unless @winner_sym
      display_name = KIFCases.result_display_name(@case_type, @winner_sym)
      accent_col   = @winner_tier ? KIFCases.rarity_color(@winner_tier, 255) : _case_color
      rarity_label = @winner_tier ? "[ #{KIFCases.rarity_name(@winner_tier).upcase} ]" : "[ #{_case_name.upcase} ]"

      result_vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
      result_vp.z = 100_000

      dim_bmp = Bitmap.new(Graphics.width, Graphics.height)
      dim_bmp.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 190))
      dim_spr = Sprite.new(result_vp); dim_spr.bitmap = dim_bmp

      pw = 400; ph = 290
      px = (Graphics.width  - pw) / 2
      py = (Graphics.height - ph) / 2
      panel_bmp = Bitmap.new(pw, ph)
      panel_bmp.fill_rect(0, 0, pw, ph, Color.new(16, 16, 48, 248))
      panel_bmp.fill_rect(0, 0, pw, 6,  accent_col)
      panel_bmp.fill_rect(0, ph - 2, pw, 2, accent_col)
      panel_bmp.fill_rect(0, 0, 2, ph, accent_col)
      panel_bmp.fill_rect(pw - 2, 0, 2, ph, accent_col)
      pbSetSystemFont(panel_bmp) if defined?(pbSetSystemFont)
      panel_bmp.font.size = 22; panel_bmp.font.bold = true
      panel_bmp.font.color = Color.new(0, 0, 0, 140)
      panel_bmp.draw_text(1, 17, pw, 36, "YOU OBTAINED!", 1)
      panel_bmp.font.color = Color.new(255, 230, 80, 255)
      panel_bmp.draw_text(0, 16, pw, 36, "YOU OBTAINED!", 1)
      panel_bmp.font.size = 15; panel_bmp.font.bold = false
      panel_bmp.font.color = Color.new(0, 0, 0, 130)
      panel_bmp.draw_text(1, 53, pw, 24, rarity_label, 1)
      panel_bmp.font.color = accent_col
      panel_bmp.draw_text(0, 52, pw, 24, rarity_label, 1)
      panel_bmp.font.size = 20; panel_bmp.font.bold = true
      panel_bmp.font.color = Color.new(0, 0, 0, 150)
      panel_bmp.draw_text(1, 229, pw, 36, display_name, 1)
      panel_bmp.font.color = Color.new(255, 255, 255, 255)
      panel_bmp.draw_text(0, 228, pw, 36, display_name, 1)
      panel_bmp.font.size = 13; panel_bmp.font.bold = false
      panel_bmp.font.color = Color.new(130, 130, 170, 200)
      panel_bmp.draw_text(0, 266, pw, 20, "Press Z or Enter to continue", 1)

      panel_spr = Sprite.new(result_vp); panel_spr.bitmap = panel_bmp
      panel_spr.x = px; panel_spr.y = py

      icon_spr = Sprite.new(result_vp)
      _show_winner_icon(icon_spr, px, py, pw)

      [dim_spr, panel_spr, icon_spr].each { |s| s.opacity = 0 }
      playCry(@winner_sym) rescue nil if @case_type == :poke
      30.times do |i|
        a = (i * 255 / 30).to_i
        [dim_spr, panel_spr, icon_spr].each { |s| s.opacity = a }
        Graphics.update
      end
      [dim_spr, panel_spr, icon_spr].each { |s| s.opacity = 255 }

      loop do
        Graphics.update
        Input.update
        break if Input.trigger?(Input::C) || Input.trigger?(Input::BACK)
        break if (Input.trigger?(Input::MOUSELEFT) rescue false)
        break if (Input.trigger?(Input::MOUSERIGHT) rescue false)
      end

      15.times do |i|
        a = 255 - (i * 255 / 15).to_i
        [dim_spr, panel_spr, icon_spr].each { |s| s.opacity = a }
        Graphics.update
      end
      result_vp.dispose
    end

    def _show_winner_icon(icon_spr, px, py, pw)
      target = 160
      case @case_type
      when :poke
        begin
          abmp = GameData::Species.front_sprite_bitmap(@winner_sym)
          raw  = abmp&.bitmap
          if raw && !raw.disposed?
            icon_spr.bitmap = raw
            biggest = [raw.width, raw.height].max
            scale   = biggest > 0 ? target.to_f / biggest : 1.0
            icon_spr.zoom_x = scale
            icon_spr.zoom_y = scale
            icon_spr.x = px + (pw - (raw.width  * scale).to_i) / 2
            icon_spr.y = py + 70
          end
        rescue; end
      when :mega
        begin
          icon_file = "Graphics/Items/#{@winner_sym}"
          abmp = AnimatedBitmap.new(icon_file)
          raw = abmp.deanimate
          if raw && !raw.disposed?
            icon_spr.bitmap = raw
            biggest = [raw.width, raw.height].max
            scale = biggest > 0 ? [target.to_f / biggest, 3.0].min : 1.0
            icon_spr.zoom_x = scale
            icon_spr.zoom_y = scale
            icon_spr.x = px + (pw - (raw.width * scale).to_i) / 2
            icon_spr.y = py + 80
          end
          abmp.dispose rescue nil
        rescue; end
      when :move
        begin
          item_data = GameData::Item.get(@winner_sym)
          if item_data&.move
            move_data = GameData::Move.get(item_data.move)
            type_name = move_data.type.to_s
            icon_file = "Graphics/Items/machine_#{type_name}"
            abmp = AnimatedBitmap.new(icon_file)
            raw = abmp.deanimate
            if raw && !raw.disposed?
              icon_spr.bitmap = raw
              biggest = [raw.width, raw.height].max
              scale = biggest > 0 ? [target.to_f / biggest, 3.0].min : 1.0
              icon_spr.zoom_x = scale
              icon_spr.zoom_y = scale
              icon_spr.x = px + (pw - (raw.width * scale).to_i) / 2
              icon_spr.y = py + 80
            end
            abmp.dispose rescue nil
          end
        rescue; end
      end
    end

    # ── Award ────────────────────────────────────────────────────────────────
    def _award_and_confirm
      return unless @winner_sym

      case @case_type
      when :poke
        pkmn = KIFCases.award_pokemon(@winner_sym)
        return unless pkmn
        species_name = GameData::Species.get(@winner_sym).name rescue @winner_sym.to_s
        dest = $Trainer.party.include?(pkmn) ? "party" : "PC box"
        _show_msg("#{$Trainer.name} obtained #{species_name}!\nAdded to your #{dest}.")
      when :mega
        # First MegaCase ever opened? Give a free Mega accessory if player has none
        _maybe_give_free_mega_accessory
        result = KIFCases.award_item(@winner_sym)
        if result
          display_name = KIFCases.result_display_name(@case_type, @winner_sym)
          _show_msg("#{$Trainer.name} obtained #{display_name}!\nAdded to your bag.")
        else
          _show_msg("Could not add item to bag.\nYour bag may be full.")
        end
      when :move
        result = KIFCases.award_item(@winner_sym)
        if result
          display_name = KIFCases.result_display_name(@case_type, @winner_sym)
          _show_msg("#{$Trainer.name} obtained #{display_name}!\nAdded to your bag.")
        else
          _show_msg("Could not add item to bag.\nYour bag may be full.")
        end
      end

      @winner_sym  = nil
      @winner_tier = nil
    end

    # Give a free random Mega Ring/Bracelet/Cuff/Charm on first MegaCase open,
    # but only if the player doesn't already own one.
    MEGA_ACCESSORIES = %i[MEGARING MEGABRACELET MEGACUFF MEGACHARM].freeze

    def _maybe_give_free_mega_accessory
      return unless defined?($PokemonBag) && $PokemonBag

      # Check if player already has any mega accessory in their bag
      has_mega = MEGA_ACCESSORIES.any? do |acc|
        ($PokemonBag.pbQuantity(acc) rescue 0) > 0
      end
      return if has_mega

      # Give a random one
      gift = MEGA_ACCESSORIES.sample
      $PokemonBag.pbStoreItem(gift, 1)
      gift_name = GameData::Item.get(gift).name rescue gift.to_s
      _show_msg("As a first-time bonus, you also received\na #{gift_name}!\nYou can now Mega Evolve in battle.")
    end

    # ── Message overlay ──────────────────────────────────────────────────────
    def _show_msg(text)
      msg_vp  = Viewport.new(0, 0, Graphics.width, Graphics.height)
      msg_vp.z = 101_000
      lines = text.to_s.split("\n")
      bh    = [lines.size * 26 + 36, 80].max
      bw    = 500
      bmp   = Bitmap.new(bw, bh)
      bmp.fill_rect(0, 0, bw, bh,  Color.new(14, 14, 40, 235))
      bmp.fill_rect(0, 0, bw, 2,   Color.new(180, 180, 255, 200))
      bmp.fill_rect(0, bh - 2, bw, 2, Color.new(180, 180, 255, 200))
      pbSetSystemFont(bmp) if defined?(pbSetSystemFont)
      bmp.font.size  = 15
      bmp.font.color = Color.new(210, 210, 255, 255)
      lines.each_with_index { |l, i| bmp.draw_text(14, 12 + i * 26, bw - 28, 26, l, 0) }
      bmp.font.size  = 12
      bmp.font.color = Color.new(130, 130, 170, 190)
      bmp.draw_text(0, bh - 20, bw, 18, "Press Z, Enter or X to close", 1)
      spr = Sprite.new(msg_vp)
      spr.bitmap = bmp
      spr.x = (Graphics.width  - bw) / 2
      spr.y = (Graphics.height - bh) / 2
      loop do
        Graphics.update
        Input.update
        break if Input.trigger?(Input::C) || Input.trigger?(Input::BACK)
        break if (Input.trigger?(Input::MOUSELEFT) rescue false)
        break if (Input.trigger?(Input::MOUSERIGHT) rescue false)
      end
      msg_vp.dispose
    end

    # ── Sprite helpers ───────────────────────────────────────────────────────
    def _spr(bmp, x, y, vp = nil)
      spr = Sprite.new(vp || @viewport)
      spr.bitmap = bmp
      spr.x = x; spr.y = y
      spr
    end

    def _clear_strip_sprites
      @strip_sprs.each do |s|
        s.bitmap.dispose if s.bitmap && !s.bitmap.disposed?
        s.dispose rescue nil
      end
      @strip_sprs.clear
    end

    def _dispose_all
      _clear_strip_sprites
      _clear_idle_sprites
      @sprites.each_value do |s|
        next unless s
        s.bitmap.dispose if s.bitmap && !s.bitmap.disposed?
        s.dispose rescue nil
      end
      @sprites.clear
      @strip_vp.dispose if @strip_vp && !@strip_vp.disposed? rescue nil
      @viewport.dispose  if @viewport  && !@viewport.disposed?  rescue nil
    end

    # ── Gem pixel art ────────────────────────────────────────────────────────
    def _draw_gem(bmp, ix, iy, alpha)
      c  = Color.new(255, 215,   0, alpha)
      sh = Color.new(180, 100,   0, [alpha - 70, 0].max)
      _gem_fill(bmp, ix + 1, iy + 1, sh)
      _gem_fill(bmp, ix,     iy,     c)
    end

    def _gem_fill(bmp, ix, iy, c)
      bmp.fill_rect(ix + 6,  iy,      10, 2, c)
      bmp.fill_rect(ix + 3,  iy +  2, 16, 3, c)
      bmp.fill_rect(ix + 1,  iy +  5, 20, 5, c)
      bmp.fill_rect(ix + 3,  iy + 10, 16, 3, c)
      bmp.fill_rect(ix + 6,  iy + 13, 10, 3, c)
      bmp.fill_rect(ix + 8,  iy + 16,  6, 2, c)
      bmp.fill_rect(ix + 9,  iy + 18,  4, 2, c)
      bmp.fill_rect(ix + 10, iy + 20,  2, 1, c)
    end
  end

  # ============================================================================
  # CaseHUD — top-left indicator (disabled, F7 icon rendered by HotkeyHUD)
  # ============================================================================
  class CaseHUD
    UPDATE_TICKS = 20
    HUD_X = 8; HUD_Y = 122; HUD_W = 73; HUD_H = 22; DIM_A = 160

    def initialize
      @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @viewport.z = 99_340
      @ticks = 0; @last_state = nil; @visible = false
      @spr = Sprite.new(@viewport)
      @spr.x = HUD_X; @spr.y = HUD_Y; @spr.z = 100; @spr.visible = false
    rescue; end

    def dispose
      @spr.bitmap.dispose if @spr&.bitmap && !@spr.bitmap.disposed? rescue nil
      @spr.dispose        if @spr && !@spr.disposed?                 rescue nil
      @viewport.dispose   if @viewport && !@viewport.disposed?       rescue nil
      @spr = nil; @viewport = nil
    end

    def update
      _set_visible(false)
    end

    private

    def _set_visible(v)
      return if @visible == v
      @visible = v; @spr.visible = v rescue nil
    end

    def _redraw
      if @spr.bitmap.nil? || @spr.bitmap.disposed? ||
         @spr.bitmap.width != HUD_W || @spr.bitmap.height != HUD_H
        @spr.bitmap.dispose if @spr.bitmap && !@spr.bitmap.disposed?
        @spr.bitmap = Bitmap.new(HUD_W, HUD_H)
      else
        @spr.bitmap.clear
      end
      bmp = @spr.bitmap
      pbSetSystemFont(bmp) if defined?(pbSetSystemFont)
      _draw_hud_briefcase(bmp, 0, 0, DIM_A)
      bmp.font.size = 14; bmp.font.bold = false
      bmp.font.color = Color.new(0, 0, 0, 150)
      bmp.draw_text(28, 4, 44, HUD_H - 4, "F7", 0)
      bmp.font.color = Color.new(50, 170, 170, DIM_A)
      bmp.draw_text(27, 3, 44, HUD_H - 4, "F7", 0)
    end

    def _draw_hud_briefcase(bmp, ix, iy, alpha)
      c  = Color.new(50, 170, 170, alpha)
      sh = Color.new(10,  70,  70, [alpha - 60, 0].max)
      _hud_briefcase_fill(bmp, ix + 1, iy + 1, sh)
      _hud_briefcase_fill(bmp, ix,     iy,     c)
    end

    def _hud_briefcase_fill(bmp, ix, iy, c)
      bmp.fill_rect(ix + 8, iy,      6, 1, c)
      bmp.fill_rect(ix + 7, iy + 1,  1, 2, c)
      bmp.fill_rect(ix + 14, iy + 1, 1, 2, c)
      bmp.fill_rect(ix + 1, iy + 3,  20, 16, c)
      bmp.fill_rect(ix + 1, iy + 10, 20, 2, Color.new(0, 0, 0, [c.alpha - 40, 0].max))
    end
  end
end

# ── Hook CaseHUD into Scene_Map ─────────────────────────────────────────────
if defined?(Scene_Map)
  class Scene_Map
    def self._kif_casehud_has?(sym)
      instance_methods(false).map(&:to_sym).include?(sym)
    end

    if _kif_casehud_has?(:start)
      alias kif_casehud_start start unless method_defined?(:kif_casehud_start)
      def start
        kif_casehud_start
        @kif_case_hud ||= KIFCases::CaseHUD.new rescue nil
      end
    end

    if _kif_casehud_has?(:terminate)
      alias kif_casehud_terminate terminate unless method_defined?(:kif_casehud_terminate)
      def terminate
        @kif_case_hud.dispose if @kif_case_hud rescue nil
        @kif_case_hud = nil
        kif_casehud_terminate
      end
    end

    if _kif_casehud_has?(:update)
      alias kif_casehud_update update unless method_defined?(:kif_casehud_update)
      def update
        @kif_case_hud ||= KIFCases::CaseHUD.new rescue nil
        @kif_case_hud.update if @kif_case_hud rescue nil
        kif_casehud_update
      end
    end
  end
end
