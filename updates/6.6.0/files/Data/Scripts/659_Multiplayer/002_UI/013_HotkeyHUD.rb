# ===========================================
# File: 013_HotkeyHUD.rb
# Purpose: Top-left shortcut hint overlay for multiplayer features.
#          Shows pixel-art icons when connected to the server.
#          Collapsed by default — icons only, no labels.
#          Deploy arrow on the right expands to show key labels.
#          Mouse hover over arrow or icons deploys.
#          Left-click an icon triggers its action.
# ===========================================

if defined?(Scene_Map)

  module MultiplayerUI
    class HotkeyHUD
      UPDATE_TICKS = 10   # state check every 10 frames (~6x/sec at 60 fps)

      ICON_SIZE = 22      # icon canvas (square)
      LABEL_X   = 27      # key label start x (icon + gap)
      LABEL_W   = 46      # key label width
      BTN_H     = ICON_SIZE
      BTN_W_COLLAPSED = ICON_SIZE + 4  # just icon + small pad
      BTN_W_EXPANDED  = LABEL_X + LABEL_W  # icon + label
      BTN_GAP   = 6       # vertical gap between buttons
      PAD_X     = 8       # distance from left edge of screen
      PAD_Y     = 8       # distance from top  edge of screen

      # Background panel padding around icons
      BG_PAD    = 4
      ARROW_W   = 14      # arrow column width on right edge of bg

      # Deploy animation speed (0..1 progress per frame)
      DEPLOY_SPEED = 0.12

      # Opacity
      DIM_A      = 140
      HOVER_A    = 210
      BRIGHT_A   = 245

      # Background colors
      C_BG       = [25, 25, 32, 180]
      C_BG_HOVER = [35, 35, 45, 210]
      C_BORDER   = [60, 60, 70, 160]
      C_ARROW    = [160, 160, 175]

      BUTTONS = [
        { key: :chat,    label: "T/F10" },
        { key: :gts,     label: "F6"    },
        { key: :players, label: "F3"    },
        { key: :squad,   label: "F4"    },   # conditional (only when in squad)
        { key: :cases,   label: "F7"    },
        { key: :profile, label: "F8"    },
      ]

      def initialize
        @viewport   = Viewport.new(0, 0, Graphics.width, Graphics.height)
        @viewport.z = 99_350
        @ticks      = 0
        @last_state = nil
        @visible    = false

        # Background panel sprite (behind icons)
        @bg_spr = Sprite.new(@viewport)
        @bg_spr.x = PAD_X - BG_PAD
        @bg_spr.y = PAD_Y - BG_PAD
        @bg_spr.z = 99
        @bg_spr.visible = false

        # Main icon+label sprite
        @spr   = Sprite.new(@viewport)
        @spr.x = PAD_X
        @spr.y = PAD_Y
        @spr.z = 100
        @spr.visible = false

        @deployed = false
        @deploy_progress = 0.0   # 0 = collapsed, 1 = expanded
        @hover_btn = nil         # index of hovered button
        @mouse_over_area = false # mouse over the whole HUD region
        @active_buttons = []     # current filtered button list
        @force_redraw = true
      rescue => e
      end

      def dispose
        begin
          if @bg_spr && !@bg_spr.disposed?
            @bg_spr.bitmap.dispose if @bg_spr.bitmap && !@bg_spr.bitmap.disposed?
            @bg_spr.dispose
          end
        rescue; end
        begin
          if @spr && !@spr.disposed?
            @spr.bitmap.dispose if @spr.bitmap && !@spr.bitmap.disposed?
            @spr.dispose
          end
        rescue; end
        begin
          @viewport.dispose if @viewport && !@viewport.disposed?
        rescue; end
        @bg_spr = nil; @spr = nil; @viewport = nil
      end

      def update
        return unless @spr && !@spr.disposed?
        @ticks += 1

        # ── Mouse handling (every frame for responsiveness) ──
        _handle_mouse

        # ── Deploy animation ──
        target = (@deployed || @mouse_over_area) ? 1.0 : 0.0
        if @deploy_progress != target
          if @deploy_progress < target
            @deploy_progress = [@deploy_progress + DEPLOY_SPEED, target].min
          else
            @deploy_progress = [@deploy_progress - DEPLOY_SPEED, target].max
          end
          @force_redraw = true
        end

        # ── State check (throttled) ──
        return if (@ticks % UPDATE_TICKS) != 0 && !@force_redraw

        begin
          connected = defined?(MultiplayerClient) &&
                      MultiplayerClient.instance_variable_get(:@connected)
          in_menu   = ($game_temp && $game_temp.in_menu   rescue false)
          in_battle = ($game_temp && $game_temp.in_battle rescue false)

          unless connected && !in_menu && !in_battle
            _set_visible(false); return
          end

          chat_on      = !!(defined?(ChatState) && ChatState.visible rescue false)
          in_squad     = !!(MultiplayerClient.in_squad? rescue false)
          profile_open = !!(defined?(MultiplayerUI::ProfilePanel) && MultiplayerUI::ProfilePanel.open? rescue false)

          state = [chat_on, in_squad, profile_open, @deploy_progress, @hover_btn]
          if @last_state != state || @force_redraw
            @last_state = state
            _redraw(chat_on, in_squad, profile_open)
            @force_redraw = false
          end
          _set_visible(true)
        rescue => e
          _set_visible(false)
        end
      end

      private

      def _set_visible(v)
        return if @visible == v
        @visible = v
        @bg_spr.visible = v rescue nil
        @spr.visible = v rescue nil
      end

      # ── Mouse input ─────────────────────────────────────────
      def _handle_mouse
        return unless @visible && @spr && !@spr.disposed?

        mx = (Input.mouse_x rescue nil)
        my = (Input.mouse_y rescue nil)
        return unless mx && my

        clicked = (Input.trigger?(Input::MOUSELEFT) rescue false)

        buttons = @active_buttons
        n = buttons.length
        return if n == 0

        # Background panel dimensions
        content_w = BTN_W_COLLAPSED + ((BTN_W_EXPANDED - BTN_W_COLLAPSED) * @deploy_progress).to_i
        total_h = n * BTN_H + (n - 1) * BTN_GAP
        bg_x = PAD_X - BG_PAD
        bg_y = PAD_Y - BG_PAD
        bg_w = content_w + BG_PAD * 2 + ARROW_W
        bg_h = total_h + BG_PAD * 2

        # Check mouse over the whole background panel
        over_panel = mx >= bg_x && mx < bg_x + bg_w &&
                     my >= bg_y && my < bg_y + bg_h

        @mouse_over_area = over_panel

        # Determine hovered button
        old_hover = @hover_btn
        @hover_btn = nil
        if over_panel
          buttons.each_with_index do |btn, i|
            iy = PAD_Y + i * (BTN_H + BTN_GAP)
            if my >= iy && my < iy + BTN_H
              @hover_btn = i
              break
            end
          end
        end
        @force_redraw = true if @hover_btn != old_hover

        # Left-click on a button → trigger action
        if clicked && @hover_btn
          _trigger_action(buttons[@hover_btn][:key])
        end
      end

      # ── Trigger the action for a button ─────────────────────
      def _trigger_action(key)
        case key
        when :chat
          ChatState.toggle_deploy if defined?(ChatState)
        when :gts
          GTSUI.open if defined?(GTSUI)
        when :players
          if defined?(MultiplayerUI)
            if MultiplayerUI.instance_variable_get(:@playerlist_open)
              MultiplayerUI.instance_variable_set(:@playerlist_close_requested, true)
            else
              MultiplayerUI.openPlayerList rescue nil
            end
          end
        when :squad
          if defined?(MultiplayerUI) && defined?(MultiplayerClient) && (MultiplayerClient.in_squad? rescue false)
            if MultiplayerUI.instance_variable_get(:@squadwindow_open)
              MultiplayerUI.instance_variable_set(:@squadwindow_close_requested, true)
            else
              MultiplayerUI.openSquadWindow rescue nil
            end
          end
        when :cases
          if defined?(KIFCases)
            if KIFCases.screen_open?
              KIFCases.request_close rescue nil
            else
              KIFCases::CaseSelectScreen.open rescue nil
            end
          end
        when :profile
          if defined?(MultiplayerUI::ProfilePanel)
            if MultiplayerUI::ProfilePanel.open?
              MultiplayerUI::ProfilePanel.close
            else
              uuid = MultiplayerClient.instance_variable_get(:@platinum_uuid) rescue nil
              MultiplayerUI::ProfilePanel.open(uuid: uuid) if uuid
            end
          end
        end
      end

      # ── Main redraw ─────────────────────────────────────────
      def _redraw(chat_on, in_squad, profile_open = false)
        buttons = BUTTONS.reject { |b| b[:key] == :squad && !in_squad }
        @active_buttons = buttons
        n = buttons.size
        return if n == 0

        # Current content width interpolated
        content_w = BTN_W_COLLAPSED + ((BTN_W_EXPANDED - BTN_W_COLLAPSED) * @deploy_progress).to_i
        total_h = n * BTN_H + (n - 1) * BTN_GAP

        # ── Background panel ─────────────────────────────────
        bg_w = content_w + BG_PAD * 2 + ARROW_W
        bg_h = total_h + BG_PAD * 2

        if @bg_spr.bitmap.nil? || @bg_spr.bitmap.disposed? ||
           @bg_spr.bitmap.width != bg_w || @bg_spr.bitmap.height != bg_h
          @bg_spr.bitmap.dispose if @bg_spr.bitmap && !@bg_spr.bitmap.disposed?
          @bg_spr.bitmap = Bitmap.new(bg_w, bg_h)
        else
          @bg_spr.bitmap.clear
        end

        bgb = @bg_spr.bitmap
        bg_col = @mouse_over_area ? _c(C_BG_HOVER) : _c(C_BG)
        border_col = _c(C_BORDER)

        # Rounded-ish fill
        bgb.fill_rect(2, 0, bg_w - 4, bg_h, bg_col)
        bgb.fill_rect(0, 2, bg_w, bg_h - 4, bg_col)
        bgb.fill_rect(1, 1, bg_w - 2, bg_h - 2, bg_col)
        # Border edges
        bgb.fill_rect(2, 0, bg_w - 4, 1, border_col)
        bgb.fill_rect(2, bg_h - 1, bg_w - 4, 1, border_col)
        bgb.fill_rect(0, 2, 1, bg_h - 4, border_col)
        bgb.fill_rect(bg_w - 1, 2, 1, bg_h - 4, border_col)

        # Arrow chevron on right edge of background
        arrow_x = bg_w - ARROW_W + 2
        arrow_cy = bg_h / 2
        arr_col = _c(C_ARROW)

        if @deploy_progress > 0.5
          # < (left = collapse)
          4.times do |i|
            w = (i < 2) ? (i + 1) : (4 - i)
            bgb.fill_rect(arrow_x + 4 - w, arrow_cy - 3 + i, w + 1, 1, arr_col)
          end
        else
          # > (right = expand)
          4.times do |i|
            w = (i < 2) ? (i + 1) : (4 - i)
            bgb.fill_rect(arrow_x + 2, arrow_cy - 3 + i, w + 1, 1, arr_col)
          end
        end

        # ── Icon + label sprite ───────────────────────────────
        if @spr.bitmap.nil? || @spr.bitmap.disposed? ||
           @spr.bitmap.width != content_w || @spr.bitmap.height != total_h
          @spr.bitmap.dispose if @spr.bitmap && !@spr.bitmap.disposed?
          @spr.bitmap = Bitmap.new(content_w, total_h)
        else
          @spr.bitmap.clear
        end

        bmp = @spr.bitmap
        pbSetSystemFont(bmp) if defined?(pbSetSystemFont)

        buttons.each_with_index do |btn, i|
          iy     = i * (BTN_H + BTN_GAP)
          active = (btn[:key] == :chat && chat_on) || (btn[:key] == :profile && profile_open)
          hovered = (i == @hover_btn)

          alpha = if hovered
            BRIGHT_A
          elsif active
            HOVER_A
          else
            DIM_A
          end

          # Hover background highlight
          if hovered
            bmp.fill_rect(0, iy, content_w, BTN_H, Color.new(70, 130, 200, 60))
          end

          # Draw the icon for this button
          case btn[:key]
          when :chat    then _draw_chat(bmp,    0, iy, alpha)
          when :gts     then _draw_gts_text(bmp, 0, iy, alpha)
          when :players then _draw_person(bmp,  0, iy, alpha)
          when :squad   then _draw_shield(bmp,    0, iy, alpha)
          when :cases   then _draw_briefcase(bmp, 0, iy, alpha)
          when :profile then _draw_id_card(bmp,   0, iy, alpha)
          end

          # Key label — only visible when deploying
          if @deploy_progress > 0.05
            label_alpha = (alpha * @deploy_progress).to_i
            lc = active ? Color.new(255, 240, 100, label_alpha) : Color.new(220, 220, 220, label_alpha)
            bmp.font.size  = 14
            bmp.font.bold  = false
            # Drop shadow
            bmp.font.color = Color.new(0, 0, 0, (180 * @deploy_progress).to_i)
            bmp.draw_text(LABEL_X + 1, iy + 3, LABEL_W, BTN_H - 2, btn[:label], 0)
            # Main text
            bmp.font.color = lc
            bmp.draw_text(LABEL_X,     iy + 2, LABEL_W, BTN_H - 2, btn[:label], 0)
          end
        end
      end

      def _c(arr)
        Color.new(arr[0], arr[1], arr[2], arr[3] || 255)
      end

      # ── Pixel-art icon drawing helpers (22x22 canvas each) ──────────────────

      # Chat: speech bubble with three dots inside
      def _draw_chat(bmp, ix, iy, alpha)
        c  = Color.new(80, 140, 220, alpha)
        sh = Color.new(20,  50, 120, [alpha - 60, 0].max)
        dt = Color.new(255, 255, 255, alpha)

        # Shadow (offset +1/+1)
        _bubble(bmp, ix + 1, iy + 1, sh)
        # Fill
        _bubble(bmp, ix,     iy,     c)

        # Three chat dots
        bmp.fill_rect(ix + 5,  iy + 7, 3, 3, dt)
        bmp.fill_rect(ix + 10, iy + 7, 3, 3, dt)
        bmp.fill_rect(ix + 15, iy + 7, 3, 3, dt)
      end

      def _bubble(bmp, ix, iy, c)
        bmp.fill_rect(ix + 3, iy,      16, 1,  c)   # top
        bmp.fill_rect(ix + 1, iy + 1,  20, 11, c)   # body
        bmp.fill_rect(ix + 3, iy + 12, 20, 1,  c)   # bottom
        # Tail (bottom-left pointer)
        bmp.fill_rect(ix + 1, iy + 13, 7,  1,  c)
        bmp.fill_rect(ix + 1, iy + 14, 5,  1,  c)
        bmp.fill_rect(ix + 1, iy + 15, 3,  1,  c)
        bmp.fill_rect(ix + 1, iy + 16, 1,  1,  c)
      end

      # GTS: hand-drawn bold pixel letters
      def _draw_gts_text(bmp, ix, iy, alpha)
        c  = Color.new(60, 185, 90, alpha)
        sh = Color.new(15,  70, 30, [alpha - 70, 0].max)
        yo = iy + 4

        _px_G(bmp, ix + 1, yo + 1, sh)
        _px_T(bmp, ix + 9, yo + 1, sh)
        _px_S(bmp, ix + 17, yo + 1, sh)
        _px_G(bmp, ix,     yo, c)
        _px_T(bmp, ix + 8, yo, c)
        _px_S(bmp, ix + 16, yo, c)
      end

      def _px_G(bmp, x, y, c)
        bmp.fill_rect(x + 1, y,      4, 2, c)
        bmp.fill_rect(x,     y + 2,  2, 4, c)
        bmp.fill_rect(x,     y + 6,  5, 2, c)
        bmp.fill_rect(x,     y + 8,  2, 4, c)
        bmp.fill_rect(x + 4, y + 8,  2, 4, c)
        bmp.fill_rect(x + 1, y + 12, 4, 2, c)
      end

      def _px_T(bmp, x, y, c)
        bmp.fill_rect(x,     y,     6,  2, c)
        bmp.fill_rect(x + 2, y + 2, 2, 12, c)
      end

      def _px_S(bmp, x, y, c)
        bmp.fill_rect(x + 1, y,      4, 2, c)
        bmp.fill_rect(x,     y + 2,  2, 4, c)
        bmp.fill_rect(x + 1, y + 6,  4, 2, c)
        bmp.fill_rect(x + 4, y + 8,  2, 4, c)
        bmp.fill_rect(x + 1, y + 12, 4, 2, c)
      end

      # Person: head circle + body trapezoid
      def _draw_person(bmp, ix, iy, alpha)
        c  = Color.new(215, 140,  55, alpha)
        sh = Color.new( 90,  55,  10, [alpha - 60, 0].max)
        _person_fill(bmp, ix + 1, iy + 1, sh)
        _person_fill(bmp, ix, iy, c)
      end

      def _person_fill(bmp, ix, iy, c)
        bmp.fill_rect(ix + 7, iy,     8, 1, c)
        bmp.fill_rect(ix + 5, iy + 1, 12, 6, c)
        bmp.fill_rect(ix + 7, iy + 7, 8, 1, c)
        bmp.fill_rect(ix + 5, iy + 9,  12, 1, c)
        bmp.fill_rect(ix + 3, iy + 10, 16, 7, c)
        bmp.fill_rect(ix + 3, iy + 17, 6, 5, c)
        bmp.fill_rect(ix + 13, iy + 17, 6, 5, c)
      end

      # Shield with a small cross emblem inside
      def _draw_shield(bmp, ix, iy, alpha)
        c  = Color.new(200,  55,  55, alpha)
        sh = Color.new( 90,  15,  15, [alpha - 60, 0].max)
        em = Color.new(255, 255, 255, alpha)
        _shield_fill(bmp, ix + 1, iy + 1, sh)
        _shield_fill(bmp, ix, iy, c)
        bmp.fill_rect(ix + 10, iy + 4, 2, 12, em)
        bmp.fill_rect(ix + 6,  iy + 7, 10, 2, em)
      end

      def _shield_fill(bmp, ix, iy, c)
        bmp.fill_rect(ix + 2, iy,      18, 1, c)
        bmp.fill_rect(ix + 1, iy + 1,  20, 11, c)
        bmp.fill_rect(ix + 2, iy + 12, 18, 3, c)
        bmp.fill_rect(ix + 4, iy + 15, 14, 3, c)
        bmp.fill_rect(ix + 6, iy + 18, 10, 2, c)
        bmp.fill_rect(ix + 8, iy + 20,  6, 1, c)
        bmp.fill_rect(ix + 10, iy + 21, 2, 1, c)
      end

      # Briefcase icon for Cases (F7)
      def _draw_briefcase(bmp, ix, iy, alpha)
        c  = Color.new(50, 170, 170, alpha)
        sh = Color.new(10,  70,  70, [alpha - 60, 0].max)
        _briefcase_fill(bmp, ix + 1, iy + 1, sh)
        _briefcase_fill(bmp, ix,     iy,     c)
      end

      def _briefcase_fill(bmp, ix, iy, c)
        bmp.fill_rect(ix + 8, iy,     6, 1, c)
        bmp.fill_rect(ix + 7, iy + 1, 1, 2, c)
        bmp.fill_rect(ix + 14, iy + 1, 1, 2, c)
        bmp.fill_rect(ix + 1, iy + 3,  20, 16, c)
        bmp.fill_rect(ix + 1, iy + 10, 20, 2, Color.new(0, 0, 0, [c.alpha - 40, 0].max))
      end

      # ID card icon for Profile (F8)
      def _draw_id_card(bmp, ix, iy, alpha)
        c  = Color.new(160,  80, 220, alpha)
        sh = Color.new( 60,  20,  90, [alpha - 60, 0].max)
        em = Color.new(255, 255, 255, alpha)
        _id_card_fill(bmp, ix + 1, iy + 1, sh, sh)
        _id_card_fill(bmp, ix,     iy,     c,  em)
      end

      def _id_card_fill(bmp, ix, iy, c, em)
        bmp.fill_rect(ix + 1, iy + 2,  20, 18, c)
        bmp.fill_rect(ix + 2, iy + 1,  18,  1, c)
        bmp.fill_rect(ix + 2, iy + 20, 18,  1, c)
        bmp.fill_rect(ix + 3, iy + 4,  5, 1, em)
        bmp.fill_rect(ix + 2, iy + 5,  7, 5, em)
        bmp.fill_rect(ix + 3, iy + 10, 5, 1, em)
        bmp.fill_rect(ix + 11, iy + 6,  8, 2, em)
        bmp.fill_rect(ix + 11, iy + 10, 6, 1, em)
        bmp.fill_rect(ix + 11, iy + 13, 6, 1, em)
        bmp.fill_rect(ix + 11, iy + 16, 4, 1, em)
      end
    end
  end

  # ── Hook into Scene_Map ──────────────────────────────────────────────────────
  class Scene_Map
    def self._kif_hkhud_has?(sym)
      instance_methods(false).map { |m| m.to_sym }.include?(sym)
    end

    if _kif_hkhud_has?(:start)
      alias kif_hkhud_start start unless method_defined?(:kif_hkhud_start)
      def start
        kif_hkhud_start
        begin
          @kif_hk_hud ||= MultiplayerUI::HotkeyHUD.new
        rescue => e
        end
      end
    end

    if _kif_hkhud_has?(:terminate)
      alias kif_hkhud_terminate terminate unless method_defined?(:kif_hkhud_terminate)
      def terminate
        begin
          @kif_hk_hud.dispose if @kif_hk_hud
          @kif_hk_hud = nil
        rescue; end
        kif_hkhud_terminate
      end
    end

    if _kif_hkhud_has?(:update)
      alias kif_hkhud_update update unless method_defined?(:kif_hkhud_update)
      def update
        begin
          @kif_hk_hud ||= MultiplayerUI::HotkeyHUD.new
          @kif_hk_hud.update if @kif_hk_hud
        rescue => e
        end
        kif_hkhud_update
      end
    end
  end
else
end
