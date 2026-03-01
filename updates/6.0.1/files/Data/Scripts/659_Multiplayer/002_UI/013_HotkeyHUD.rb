# ===========================================
# File: 013_HotkeyHUD.rb
# Purpose: Top-left shortcut hint overlay for multiplayer features.
#          Shows F-key / T hints when connected to the server.
#          Cheap: bitmap only redrawn when connection/squad/chat state changes.
# Layout (top-left, no background rectangles):
#   [chat bubble]  T/F10
#   [globe]        F6
#   [person]       F3
#   [shield]       F4   ← only shown when in a squad
# ===========================================

if defined?(Scene_Map)

  module MultiplayerUI
    class HotkeyHUD
      UPDATE_TICKS = 20   # state check every 20 frames (~3x/sec at 60 fps)

      ICON_SIZE = 22      # icon canvas (square)
      LABEL_X   = 27      # key label start x (icon + gap)
      LABEL_W   = 46      # key label width
      BTN_H     = ICON_SIZE
      BTN_W     = LABEL_X + LABEL_W
      BTN_GAP   = 6       # vertical gap between buttons
      PAD_X     = 8       # distance from left edge of screen
      PAD_Y     = 8       # distance from top  edge of screen

      # Normal / active opacity for icons and text
      DIM_A    = 160
      BRIGHT_A = 245

      BUTTONS = [
        { key: :chat,    label: "T/F10" },
        { key: :gts,     label: "F6"    },
        { key: :players, label: "F3"    },
        { key: :squad,   label: "F4"    },
      ]

      def initialize
        @viewport   = Viewport.new(0, 0, Graphics.width, Graphics.height)
        @viewport.z = 99_350
        @ticks      = 0
        @last_state = nil
        @visible    = false

        @spr   = Sprite.new(@viewport)
        @spr.x = PAD_X
        @spr.y = PAD_Y
        @spr.z = 100
        @spr.visible = false
        ##MultiplayerDebug.info("HK-HUD", "HotkeyHUD initialized.") if defined?(MultiplayerDebug)
      rescue => e
        ##MultiplayerDebug.error("HK-HUD", "Init error: #{e.message}") if defined?(MultiplayerDebug)
      end

      def dispose
        begin
          if @spr && !@spr.disposed?
            @spr.bitmap.dispose if @spr.bitmap && !@spr.bitmap.disposed?
            @spr.dispose
          end
        rescue; end
        begin
          @viewport.dispose if @viewport && !@viewport.disposed?
        rescue; end
        @spr = nil; @viewport = nil
      end

      def update
        return unless @spr && !@spr.disposed?
        @ticks += 1
        return if (@ticks % UPDATE_TICKS) != 0

        begin
          connected = defined?(MultiplayerClient) &&
                      MultiplayerClient.instance_variable_get(:@connected)
          in_menu   = ($game_temp && $game_temp.in_menu   rescue false)
          in_battle = ($game_temp && $game_temp.in_battle rescue false)

          unless connected && !in_menu && !in_battle
            _set_visible(false); return
          end

          chat_on  = !!(defined?(ChatState) && ChatState.visible rescue false)
          in_squad = !!(MultiplayerClient.in_squad? rescue false)

          state = [chat_on, in_squad]
          if @last_state != state
            @last_state = state
            _redraw(chat_on, in_squad)
          end
          _set_visible(true)
        rescue => e
          ##MultiplayerDebug.error("HK-HUD", "Update error: #{e.message}") if defined?(MultiplayerDebug)
          _set_visible(false)
        end
      end

      private

      def _set_visible(v)
        return if @visible == v
        @visible = v
        @spr.visible = v rescue nil
      end

      def _redraw(chat_on, in_squad)
        buttons = BUTTONS.reject { |b| b[:key] == :squad && !in_squad }
        n = buttons.size
        return if n == 0

        total_h = n * BTN_H + (n - 1) * BTN_GAP

        if @spr.bitmap.nil? || @spr.bitmap.disposed? ||
           @spr.bitmap.width != BTN_W || @spr.bitmap.height != total_h
          @spr.bitmap.dispose if @spr.bitmap && !@spr.bitmap.disposed?
          @spr.bitmap = Bitmap.new(BTN_W, total_h)
        else
          @spr.bitmap.clear
        end

        bmp = @spr.bitmap
        pbSetSystemFont(bmp) if defined?(pbSetSystemFont)

        buttons.each_with_index do |btn, i|
          iy     = i * (BTN_H + BTN_GAP)
          active = (btn[:key] == :chat && chat_on)
          alpha  = active ? BRIGHT_A : DIM_A

          # Draw the icon for this button
          case btn[:key]
          when :chat    then _draw_chat(bmp,    0, iy, alpha)
          when :gts     then _draw_gts_text(bmp, 0, iy, alpha)
          when :players then _draw_person(bmp,  0, iy, alpha)
          when :squad   then _draw_shield(bmp,  0, iy, alpha)
          end

          # Key label — drop shadow then main color
          lc = active ? Color.new(255, 240, 100, alpha) : Color.new(220, 220, 220, alpha)
          bmp.font.size  = 14
          bmp.font.bold  = false
          bmp.font.color = Color.new(0, 0, 0, 180)
          bmp.draw_text(LABEL_X + 1, iy + 3, LABEL_W, BTN_H - 2, btn[:label], 0)
          bmp.font.color = lc
          bmp.draw_text(LABEL_X,     iy + 2, LABEL_W, BTN_H - 2, btn[:label], 0)
        end
      end

      # ── Pixel-art icon drawing helpers (22×22 canvas each) ──────────────────

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

      # GTS: hand-drawn bold pixel letters (6×14 px each, 2px strokes)
      # Letters laid out: G at x+0, T at x+8, S at x+16 → total 22px wide
      # Vertically centered: y offset = (22-14)/2 = 4px from top
      def _draw_gts_text(bmp, ix, iy, alpha)
        c  = Color.new(60, 185, 90, alpha)
        sh = Color.new(15,  70, 30, [alpha - 70, 0].max)
        yo = iy + 4   # vertical center offset

        # Shadow (+1, +1) — bitmap is 73px wide so no OOB risk
        _px_G(bmp, ix + 1, yo + 1, sh)
        _px_T(bmp, ix + 9, yo + 1, sh)
        _px_S(bmp, ix + 17, yo + 1, sh)
        # Color
        _px_G(bmp, ix,     yo, c)
        _px_T(bmp, ix + 8, yo, c)
        _px_S(bmp, ix + 16, yo, c)
      end

      # G — 6px wide, 14px tall, 2px strokes
      # .XXXX.
      # XX....  (rows 2-5)
      # XXXXX.  midbar
      # XX..XX  (rows 8-11)
      # .XXXX.
      def _px_G(bmp, x, y, c)
        bmp.fill_rect(x + 1, y,      4, 2, c)   # top cap
        bmp.fill_rect(x,     y + 2,  2, 4, c)   # left side (upper)
        bmp.fill_rect(x,     y + 6,  5, 2, c)   # midbar (left + across)
        bmp.fill_rect(x,     y + 8,  2, 4, c)   # left side (lower)
        bmp.fill_rect(x + 4, y + 8,  2, 4, c)   # right rail (lower half only)
        bmp.fill_rect(x + 1, y + 12, 4, 2, c)   # bottom cap
      end

      # T — 6px wide, 14px tall, 2px strokes
      # XXXXXX  top bar
      # ..XX..  stem
      def _px_T(bmp, x, y, c)
        bmp.fill_rect(x,     y,     6,  2, c)   # top bar (full width)
        bmp.fill_rect(x + 2, y + 2, 2, 12, c)   # center stem
      end

      # S — 6px wide, 14px tall, 2px strokes
      # .XXXX.
      # XX....  top-left curve
      # .XXXX.  middle bar
      # ....XX  bottom-right curve
      # .XXXX.
      def _px_S(bmp, x, y, c)
        bmp.fill_rect(x + 1, y,      4, 2, c)   # top cap
        bmp.fill_rect(x,     y + 2,  2, 4, c)   # top-left curve
        bmp.fill_rect(x + 1, y + 6,  4, 2, c)   # middle bar
        bmp.fill_rect(x + 4, y + 8,  2, 4, c)   # bottom-right curve
        bmp.fill_rect(x + 1, y + 12, 4, 2, c)   # bottom cap
      end

      # Person: head circle + body trapezoid
      def _draw_person(bmp, ix, iy, alpha)
        c  = Color.new(215, 140,  55, alpha)
        sh = Color.new( 90,  55,  10, [alpha - 60, 0].max)

        # Shadow
        _person_fill(bmp, ix + 1, iy + 1, sh)
        # Fill
        _person_fill(bmp, ix, iy, c)
      end

      def _person_fill(bmp, ix, iy, c)
        # Head
        bmp.fill_rect(ix + 7, iy,     8, 1, c)
        bmp.fill_rect(ix + 5, iy + 1, 12, 6, c)
        bmp.fill_rect(ix + 7, iy + 7, 8, 1, c)
        # Body (wide trapezoid)
        bmp.fill_rect(ix + 5, iy + 9,  12, 1, c)
        bmp.fill_rect(ix + 3, iy + 10, 16, 7, c)
        # Legs
        bmp.fill_rect(ix + 3, iy + 17, 6, 5, c)
        bmp.fill_rect(ix + 13, iy + 17, 6, 5, c)
      end

      # Shield with a small cross/sword emblem inside
      def _draw_shield(bmp, ix, iy, alpha)
        c  = Color.new(200,  55,  55, alpha)
        sh = Color.new( 90,  15,  15, [alpha - 60, 0].max)
        em = Color.new(255, 255, 255, alpha)   # emblem

        # Shadow
        _shield_fill(bmp, ix + 1, iy + 1, sh)
        # Fill
        _shield_fill(bmp, ix, iy, c)

        # Cross emblem inside shield
        bmp.fill_rect(ix + 10, iy + 4, 2, 12, em)  # vertical bar
        bmp.fill_rect(ix + 6,  iy + 7, 10, 2, em)  # horizontal bar
      end

      def _shield_fill(bmp, ix, iy, c)
        bmp.fill_rect(ix + 2, iy,      18, 1, c)   # top
        bmp.fill_rect(ix + 1, iy + 1,  20, 11, c)  # upper shield
        bmp.fill_rect(ix + 2, iy + 12, 18, 3, c)   # taper 1
        bmp.fill_rect(ix + 4, iy + 15, 14, 3, c)   # taper 2
        bmp.fill_rect(ix + 6, iy + 18, 10, 2, c)   # taper 3
        bmp.fill_rect(ix + 8, iy + 20,  6, 1, c)   # tip row
        bmp.fill_rect(ix + 10, iy + 21, 2, 1, c)   # tip point
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
          ##MultiplayerDebug.error("HK-HUD", "start init error: #{e.message}") if defined?(MultiplayerDebug)
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
          ##MultiplayerDebug.error("HK-HUD", "update error: #{e.message}") if defined?(MultiplayerDebug)
        end
        kif_hkhud_update
      end
    end
  end

  ##MultiplayerDebug.info("HK-HUD", "HotkeyHUD hooked into Scene_Map.") if defined?(MultiplayerDebug)
else
  ##MultiplayerDebug.warn("HK-HUD", "Scene_Map not defined — HotkeyHUD disabled.") if defined?(MultiplayerDebug)
end
