# ===========================================
# Chat System - UI Rendering (v2)
# Sleek dark theme, deploy/retract sidebar,
# mouse-aware, animated, unread dots, PM sound.
# ===========================================

class ChatWindow
  # ── Layout constants ──────────────────────────────────────
  PANEL_W       = 280
  PANEL_H       = 200
  HANDLE_W      = 14
  HANDLE_H      = 50
  TAB_H         = 22
  MSG_PAD       = 6
  MSG_W         = PANEL_W - MSG_PAD * 2 - 10   # 258 (leave room for scrollbar)
  MSG_H         = PANEL_H - TAB_H - 2 - 22 - 4 # 152
  MSG_Y         = TAB_H + 2
  SCROLL_W      = 4
  SCROLL_X      = PANEL_W - MSG_PAD - SCROLL_W  # 270
  INPUT_H       = 22
  INPUT_Y       = PANEL_H - INPUT_H
  INPUT_W       = PANEL_W - MSG_PAD * 2          # 268

  DEPLOY_SPEED  = 0.08   # per frame (~0.2s at 60fps)

  # ── Colors ────────────────────────────────────────────────
  C_PANEL_BG    = [30,  30,  35,  220]
  C_TAB_BG      = [40,  40,  48,  240]
  C_TAB_ACTIVE  = [70, 130, 200,  255]
  C_TAB_INACTIVE= [55,  55,  62,  240]
  C_TAB_HOVER   = [65,  65,  75,  240]
  C_MSG_TEXT    = [210, 210, 215]
  C_INPUT_BG    = [45,  45,  52,  230]
  C_INPUT_FOCUS = [70, 130, 200,  255]
  C_UNREAD_DOT  = [255,  80,  80]
  C_HANDLE_BG   = [55,  55,  62,  200]
  C_HANDLE_ARR  = [160, 160, 170]
  C_SCROLL_TRACK= [50,  50,  58]
  C_SCROLL_THUMB= [100, 100, 110]
  C_PLACEHOLDER = [90,  90, 100]
  C_BORDER      = [60,  60,  68]

  def initialize
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999

    @base_y = Graphics.height - PANEL_H - 60  # above Coop HUD
    @handle_y = @base_y + (PANEL_H - HANDLE_H) / 2

    # ── Sprites ──────────────────────────────────────────
    @handle_sprite = Sprite.new(@viewport)
    @handle_sprite.bitmap = Bitmap.new(HANDLE_W, HANDLE_H)
    @handle_sprite.y = @handle_y
    @handle_sprite.z = 1

    @bg_sprite = Sprite.new(@viewport)
    @bg_sprite.bitmap = Bitmap.new(PANEL_W, PANEL_H)
    @bg_sprite.y = @base_y
    @bg_sprite.z = 2
    @bg_sprite.visible = false

    @tabs_sprite = Sprite.new(@viewport)
    @tabs_sprite.bitmap = Bitmap.new(PANEL_W, TAB_H)
    @tabs_sprite.y = @base_y
    @tabs_sprite.z = 3
    @tabs_sprite.visible = false

    @messages_sprite = Sprite.new(@viewport)
    @messages_sprite.bitmap = Bitmap.new(MSG_W, MSG_H)
    @messages_sprite.y = @base_y + MSG_Y
    @messages_sprite.z = 4
    @messages_sprite.visible = false

    @scrollbar_sprite = Sprite.new(@viewport)
    @scrollbar_sprite.bitmap = Bitmap.new(SCROLL_W + 2, MSG_H)
    @scrollbar_sprite.y = @base_y + MSG_Y
    @scrollbar_sprite.z = 5
    @scrollbar_sprite.visible = false

    @input_sprite = Sprite.new(@viewport)
    @input_sprite.bitmap = Bitmap.new(INPUT_W, INPUT_H)
    @input_sprite.y = @base_y + INPUT_Y
    @input_sprite.z = 6
    @input_sprite.visible = false

    # Context menu sprite (right-click on username)
    @ctx_sprite = Sprite.new(@viewport)
    @ctx_sprite.bitmap = Bitmap.new(130, 120)
    @ctx_sprite.z = 50
    @ctx_sprite.visible = false

    @input_text    = ""
    @input_mode    = false
    @scroll_offset = 0
    @hover_tab     = nil        # tab index mouse is over
    @mouse_over_panel = false   # is mouse over the full panel area
    @target_opacity   = 140
    @current_opacity  = 0
    @last_content_update = 0.0
    @tabs_dirty    = true
    @messages_dirty = true
    @input_dirty   = true
    @last_handle_deployed = nil  # track handle redraw need
    @last_tab_count = 0
    @msg_sid_map   = []         # [{y:, h:, sid:, name:}, ...] hit regions
    @ctx_open      = false      # context menu open?
    @ctx_sid       = nil        # SID of right-clicked player
    @ctx_name      = nil        # name of right-clicked player
    @ctx_hover     = nil        # hovered menu item index
    @ctx_items     = []         # menu item labels

    _draw_bg
    _reposition_sprites
    _draw_handle
  end

  # ── Main update (called every Graphics.update from Scene_Map) ──
  def update
    return unless defined?(ChatState)

    # Hide chat when not on the overworld (menus, battles, etc.)
    on_overworld = $scene && $scene.is_a?(Scene_Map) &&
                   !($game_temp && $game_temp.in_menu rescue false) &&
                   !($game_temp && $game_temp.in_battle rescue false)
    if @viewport && !@viewport.disposed?
      @viewport.visible = on_overworld
    end
    return unless on_overworld

    # ── PM notification sound ──────────────────────────────
    if ChatState.pm_sound_pending
      ChatState.pm_sound_pending = false
      pbSEPlay("GUI sel cursor", 60, 120) rescue nil
    end

    # ── Animation ──────────────────────────────────────────
    target = ChatState.deployed ? 1.0 : 0.0
    if ChatState.deploy_progress != target
      if ChatState.deploy_progress < target
        ChatState.deploy_progress = [ChatState.deploy_progress + DEPLOY_SPEED, target].min
      else
        ChatState.deploy_progress = [ChatState.deploy_progress - DEPLOY_SPEED, target].max
      end
      _reposition_sprites
      @tabs_dirty = true
      @messages_dirty = true
      @input_dirty = true
    end

    # ── Opacity ────────────────────────────────────────────
    @target_opacity = if @input_mode
      240
    elsif @mouse_over_panel && ChatState.deploy_progress > 0.9
      200
    else
      140
    end

    if @current_opacity != @target_opacity
      if @current_opacity < @target_opacity
        @current_opacity = [@current_opacity + 10, @target_opacity].min
      else
        @current_opacity = [@current_opacity - 10, @target_opacity].max
      end
      op = (@current_opacity * ChatState.deploy_progress).to_i.clamp(0, 255)
      @bg_sprite.opacity       = op
      @tabs_sprite.opacity     = op
      @messages_sprite.opacity = op
      @scrollbar_sprite.opacity = op
      @input_sprite.opacity    = op
    end

    # ── Handle redraw (only when direction changes) ────────
    if @last_handle_deployed != ChatState.deployed
      _draw_handle
      @last_handle_deployed = ChatState.deployed
    end

    # Handle opacity (always visible, brightens on hover)
    handle_target = @mouse_over_handle ? 240 : 180
    @handle_sprite.opacity = @handle_sprite.opacity || 180
    if @handle_sprite.opacity < handle_target
      @handle_sprite.opacity = [@handle_sprite.opacity + 12, handle_target].min
    elsif @handle_sprite.opacity > handle_target
      @handle_sprite.opacity = [@handle_sprite.opacity - 12, handle_target].max
    end

    # ── Content redraws (throttled) ────────────────────────
    panel_vis = ChatState.deploy_progress > 0.0
    return unless panel_vis

    now = Time.now.to_f

    # Animated titles need continuous redraws — check before throttle gate
    if !@messages_dirty && (now - @last_content_update >= 0.1) && _has_animated_titles?
      @messages_dirty = true
    end

    return if !@tabs_dirty && !@messages_dirty && !@input_dirty && (now - @last_content_update < 0.1)

    # Check if tab list changed
    tab_list = ChatTabs.tab_list rescue []
    if tab_list.length != @last_tab_count
      @last_tab_count = tab_list.length
      @tabs_dirty = true
    end

    draw_tabs    if @tabs_dirty
    draw_messages if @messages_dirty
    draw_input   if @input_dirty
    draw_scrollbar

    @tabs_dirty = false
    @messages_dirty = false
    @input_dirty = false
    @last_content_update = now
  end

  # ── Sprite positioning (called during animation) ─────────
  def _reposition_sprites
    progress = ChatState.deploy_progress
    panel_x = (-PANEL_W * (1.0 - progress)).to_i

    @bg_sprite.x        = panel_x
    @tabs_sprite.x      = panel_x
    @messages_sprite.x  = panel_x + MSG_PAD
    @scrollbar_sprite.x = panel_x + SCROLL_X
    @input_sprite.x     = panel_x + MSG_PAD
    @handle_sprite.x    = panel_x + PANEL_W

    panel_vis = progress > 0.0
    @bg_sprite.visible        = panel_vis
    @tabs_sprite.visible      = panel_vis
    @messages_sprite.visible  = panel_vis
    @scrollbar_sprite.visible = panel_vis
    @input_sprite.visible     = panel_vis
    @handle_sprite.visible    = true  # always
  end

  # ── Handle drawing ───────────────────────────────────────
  def _draw_handle
    bmp = @handle_sprite.bitmap
    bmp.clear

    # Background
    bmp.fill_rect(0, 0, HANDLE_W, HANDLE_H, _c(C_HANDLE_BG))
    # Top/bottom/right border
    bmp.fill_rect(0, 0, HANDLE_W, 1, _c(C_BORDER))
    bmp.fill_rect(0, HANDLE_H - 1, HANDLE_W, 1, _c(C_BORDER))
    bmp.fill_rect(HANDLE_W - 1, 0, 1, HANDLE_H, _c(C_BORDER))

    # Arrow (>> or <<)
    arrow_col = _c(C_HANDLE_ARR)
    cx = HANDLE_W / 2
    cy = HANDLE_H / 2
    deployed = ChatState.deployed rescue false

    if deployed
      # << (left-pointing)
      5.times do |i|
        w = 3 - (i - 2).abs   # 1,2,3,2,1
        x = cx - w + 1
        bmp.fill_rect(x, cy - 2 + i, w, 1, arrow_col)
      end
    else
      # >> (right-pointing)
      5.times do |i|
        w = 3 - (i - 2).abs   # 1,2,3,2,1
        x = cx - 1
        bmp.fill_rect(x, cy - 2 + i, w, 1, arrow_col)
      end
    end
  end

  # ── Tab drawing ──────────────────────────────────────────
  def draw_tabs
    return unless defined?(ChatTabs)
    bmp = @tabs_sprite.bitmap
    bmp.clear

    tabs = ChatTabs.tab_list
    return if tabs.empty?

    active_idx = ChatState.active_tab_index
    active_idx = 0 if active_idx >= tabs.length
    tab_w = [(PANEL_W / tabs.length).to_i, 50].max

    tabs.each_with_index do |tab_name, i|
      x = i * tab_w
      is_active = (i == active_idx)
      is_hover  = (i == @hover_tab && !is_active)

      # Background
      bg = if is_active
        _c(C_TAB_ACTIVE)
      elsif is_hover
        _c(C_TAB_HOVER)
      else
        _c(C_TAB_INACTIVE)
      end
      bmp.fill_rect(x, 0, tab_w - 1, TAB_H, bg)

      # Active bottom highlight
      if is_active
        bmp.fill_rect(x, TAB_H - 2, tab_w - 1, 2, _c([100, 170, 255]))
      end

      # Text
      bmp.font.size  = 13
      bmp.font.bold  = is_active
      bmp.font.color = is_active ? Color.new(255, 255, 255) : Color.new(170, 170, 180)

      # Truncate tab name
      display = tab_name.length > 8 ? tab_name[0..6] + ".." : tab_name
      bmp.draw_text(x + 2, 3, tab_w - 4, TAB_H - 4, display, 1)

      # Unread dot
      unread = ChatState.unread[tab_name] || 0
      if unread > 0 && !is_active
        dot_x = x + tab_w - 9
        dot_y = 4
        bmp.fill_rect(dot_x, dot_y, 5, 5, _c(C_UNREAD_DOT))
        bmp.fill_rect(dot_x + 1, dot_y - 1, 3, 1, _c(C_UNREAD_DOT))
        bmp.fill_rect(dot_x + 1, dot_y + 5, 3, 1, _c(C_UNREAD_DOT))
      end
    end
  end

  # ── Message drawing ──────────────────────────────────────
  def draw_messages
    return unless defined?(ChatTabs) && defined?(ChatMessages)
    bmp = @messages_sprite.bitmap
    bmp.clear

    # Background fill
    bmp.fill_rect(0, 0, MSG_W, MSG_H, _c(C_PANEL_BG))

    tab = ChatTabs.current_tab_name
    messages = ChatMessages.get_messages(tab)
    messages = messages.last(50)

    line_height = 14
    visible_lines = (MSG_H / line_height).to_i

    if messages.empty?
      bmp.font.size  = 12
      bmp.font.color = _c(C_PLACEHOLDER)
      bmp.draw_text(0, MSG_H / 2 - 7, MSG_W, 14, "No messages yet...", 1)
      return
    end

    # Build all wrapped lines
    all_lines = []
    messages.each do |msg|
      header = "#{msg[:sid]}/#{msg[:name]} : "
      wrapped = wrap_text(header + msg[:text], MSG_W - 4)
      wrapped.each_with_index do |line, li|
        all_lines << { line: line, is_owner: msg[:is_owner], is_first: li == 0,
                       sid: msg[:sid], name: msg[:name] }
      end
    end

    total = all_lines.length
    start_idx = [total - visible_lines - @scroll_offset, 0].max
    end_idx   = [start_idx + visible_lines, total].min

    @msg_sid_map = []
    y = 0
    all_lines[start_idx...end_idx].each do |ld|
      break if y >= MSG_H

      bmp.font.size = 11
      bmp.font.bold = false

      # Track SID hit region for right-click (only first line of each message)
      if ld[:is_first] && ld[:sid].to_s != "SYSTEM"
        @msg_sid_map << { y: y, h: line_height, sid: ld[:sid].to_s, name: ld[:name].to_s }
      end

      if ld[:is_owner]
        bmp.font.color = Color.new(255, 200, 0)
        bmp.draw_text(2, y, MSG_W - 4, line_height, ld[:line])
      elsif ld[:is_first]
        sid_part = "#{ld[:sid]}/"
        name     = ld[:name].to_s
        after    = ld[:line][(sid_part.length + name.length)..-1] || ""
        td = (MultiplayerClient.title_for(ld[:sid]) rescue nil)

        x = 2
        # SID in dim
        bmp.font.color = Color.new(160, 160, 160)
        bmp.draw_text(x, y, MSG_W - 4, line_height, sid_part)
        sw = bmp.text_size(sid_part).width
        x += sw

        # Name in title color (gilded = animated gold plate + black text)
        nw = bmp.text_size(name).width
        if td && td["gilded"]
          px = x - 2
          pw = nw + 4
          py = y + 1
          ph = line_height - 2
          gt = Time.now.to_f
          _draw_gilded_plate(bmp, px, py, pw, ph, gt)
          bmp.font.color = Color.new(15, 10, 0, 255)
        else
          bmp.font.color = td ? _chat_title_color(td) : Color.new(210, 210, 215)
        end
        bmp.draw_text(x, y, MSG_W - 4 - sw, line_height, name)
        x += nw

        # Rest of message
        bmp.font.color = Color.new(210, 210, 215)
        bmp.draw_text(x, y, MSG_W - 4 - sw - nw, line_height, after)
      else
        bmp.font.color = Color.new(210, 210, 215)
        bmp.draw_text(2, y, MSG_W - 4, line_height, ld[:line])
      end

      y += line_height
    end

    # Scroll indicator
    if @scroll_offset > 0
      bmp.font.color = Color.new(70, 130, 200)
      bmp.font.size  = 10
      bmp.draw_text(2, MSG_H - 12, MSG_W - 4, 12, "^ #{@scroll_offset} lines up", 0)
    end
  end

  # ── Scrollbar drawing ────────────────────────────────────
  def draw_scrollbar
    bmp = @scrollbar_sprite.bitmap
    bmp.clear

    tab = ChatTabs.current_tab_name rescue nil
    return unless tab
    messages = ChatMessages.get_messages(tab)
    messages = messages.last(50)

    line_height = 14
    visible_lines = (MSG_H / line_height).to_i

    total_lines = 0
    messages.each do |msg|
      header = "#{msg[:sid]}/#{msg[:name]} : "
      total_lines += wrap_text(header + msg[:text], MSG_W - 4).length
    end

    return if total_lines <= visible_lines

    # Track
    bmp.fill_rect(0, 0, SCROLL_W, MSG_H, _c(C_SCROLL_TRACK))

    # Thumb
    frac   = visible_lines.to_f / total_lines
    thumb_h = [MSG_H * frac, 12].max.to_i
    max_scroll = [total_lines - visible_lines, 1].max
    scroll_frac = @scroll_offset.to_f / max_scroll
    # scroll_offset 0 = bottom (newest), max = top (oldest)
    # thumb at bottom when offset=0, top when offset=max
    thumb_y = ((MSG_H - thumb_h) * (1.0 - scroll_frac)).to_i
    bmp.fill_rect(0, thumb_y, SCROLL_W, thumb_h, _c(C_SCROLL_THUMB))
  end

  # ── Input drawing ────────────────────────────────────────
  def draw_input
    bmp = @input_sprite.bitmap
    bmp.clear

    # Background
    bmp.fill_rect(0, 0, INPUT_W, INPUT_H, _c(C_INPUT_BG))

    if @input_mode
      # Focused border
      _draw_border(bmp, 0, 0, INPUT_W, INPUT_H, _c(C_INPUT_FOCUS), 1)

      bmp.font.size  = 12
      bmp.font.bold  = false
      bmp.font.color = Color.new(255, 255, 255)

      # Scroll for long text
      max_text_w = INPUT_W - 8
      char_w = 7
      vis_chars = (max_text_w / char_w).to_i
      display = @input_text
      if @input_text.length > vis_chars
        display = @input_text[(@input_text.length - vis_chars)..-1]
      end

      bmp.draw_text(4, 4, max_text_w, 14, display)

      # Blinking cursor
      if (Time.now.to_f * 2).to_i % 2 == 0
        tw = bmp.text_size(display).width
        bmp.fill_rect(4 + tw, 5, 2, 12, Color.new(255, 255, 255))
      end
    else
      # Placeholder
      bmp.font.size  = 12
      bmp.font.bold  = false
      bmp.font.color = _c(C_PLACEHOLDER)
      bmp.draw_text(4, 4, INPUT_W - 8, 14, "Click or press T to chat...")
    end
  end

  # ── Background drawing (called from _reposition) ─────────
  def _draw_bg
    bmp = @bg_sprite.bitmap
    bmp.clear
    bmp.fill_rect(0, 0, PANEL_W, PANEL_H, _c(C_PANEL_BG))
    _draw_border(bmp, 0, 0, PANEL_W, PANEL_H, _c(C_BORDER), 1)
  end

  # ── Context menu ─────────────────────────────────────────
  CTX_W       = 130
  CTX_ITEM_H  = 20
  CTX_PAD     = 4
  C_CTX_BG    = [35, 35, 42, 245]
  C_CTX_HOVER = [60, 100, 180, 255]
  C_CTX_TEXT  = [210, 210, 220]
  C_CTX_BORDER= [80, 80, 95]

  CTX_ACTIONS = ["View Profile", "Send PM", "Invite to Squad", "Battle Request", "Request Trade", "Inspect Party"]

  def open_context_menu(sid, name, screen_x, screen_y)
    my_sid = (MultiplayerClient.instance_variable_get(:@session_id) rescue nil)
    return if sid == my_sid  # can't right-click yourself

    @ctx_sid   = sid
    @ctx_name  = name
    @ctx_items = CTX_ACTIONS.dup
    @ctx_hover = nil
    @ctx_open  = true

    ctx_h = CTX_PAD * 2 + 16 + @ctx_items.length * CTX_ITEM_H

    # Position: try to show at click location, clamp to screen
    sw = Graphics.width
    sh = Graphics.height
    cx = [screen_x, sw - CTX_W - 2].min
    cy = [screen_y, sh - ctx_h - 2].min
    cx = [cx, 2].max
    cy = [cy, 2].max

    @ctx_sprite.x = cx
    @ctx_sprite.y = cy

    if @ctx_sprite.bitmap.nil? || @ctx_sprite.bitmap.disposed? || @ctx_sprite.bitmap.height < ctx_h
      @ctx_sprite.bitmap.dispose rescue nil
      @ctx_sprite.bitmap = Bitmap.new(CTX_W, ctx_h)
    end

    _draw_context_menu
    @ctx_sprite.visible = true
  end

  def close_context_menu
    @ctx_open = false
    @ctx_sprite.visible = false
    @ctx_sid  = nil
    @ctx_name = nil
    @ctx_hover = nil
  end

  def _draw_context_menu
    return unless @ctx_open
    bmp = @ctx_sprite.bitmap
    ctx_h = CTX_PAD * 2 + 16 + @ctx_items.length * CTX_ITEM_H
    bmp.clear

    # Background + border
    bmp.fill_rect(0, 0, CTX_W, ctx_h, _c(C_CTX_BG))
    _draw_border(bmp, 0, 0, CTX_W, ctx_h, _c(C_CTX_BORDER), 1)

    # Header (player name)
    bmp.font.size  = 12
    bmp.font.bold  = true
    bmp.font.color = _c(C_TAB_ACTIVE)
    header = @ctx_name.to_s
    header = header[0..14] + ".." if header.length > 16
    bmp.draw_text(CTX_PAD, CTX_PAD, CTX_W - CTX_PAD * 2, 14, header)
    bmp.fill_rect(CTX_PAD, CTX_PAD + 15, CTX_W - CTX_PAD * 2, 1, _c(C_CTX_BORDER))

    # Items
    bmp.font.bold = false
    bmp.font.size = 12
    @ctx_items.each_with_index do |label, i|
      iy = CTX_PAD + 16 + i * CTX_ITEM_H

      if i == @ctx_hover
        bmp.fill_rect(1, iy, CTX_W - 2, CTX_ITEM_H, _c(C_CTX_HOVER))
        bmp.font.color = Color.new(255, 255, 255)
      else
        bmp.font.color = _c(C_CTX_TEXT)
      end

      bmp.draw_text(CTX_PAD + 2, iy + 2, CTX_W - CTX_PAD * 2 - 4, CTX_ITEM_H - 4, label)
    end
  end

  def ctx_open?;    @ctx_open; end
  def ctx_sid;      @ctx_sid; end
  def ctx_name;     @ctx_name; end
  def ctx_items;    @ctx_items; end
  def msg_sid_map;  @msg_sid_map; end

  def ctx_hover=(idx)
    if @ctx_hover != idx
      @ctx_hover = idx
      _draw_context_menu
    end
  end
  def ctx_hover; @ctx_hover; end

  # ── Text wrapping ────────────────────────────────────────
  def wrap_text(text, max_width)
    return [text] if text.nil? || text.empty?
    lines = []
    current = ""
    text.split(" ").each do |word|
      test = current.empty? ? word : "#{current} #{word}"
      if test.length * 6 > max_width
        lines << current unless current.empty?
        current = word
      else
        current = test
      end
    end
    lines << current unless current.empty?
    lines
  end

  # ── Check if any visible message sender has an animated title ──
  def _has_animated_titles?
    return false unless defined?(MultiplayerClient) && defined?(ChatMessages) && defined?(ChatState)
    tab = (ChatTabs.current_tab_name rescue nil)
    return false unless tab
    messages = ChatMessages.get_messages(tab) rescue nil
    return false unless messages && !messages.empty?

    # Only check recent messages (visible portion)
    messages.last(20).each do |msg|
      next if msg[:sid].to_s == "SYSTEM"
      td = (MultiplayerClient.title_for(msg[:sid]) rescue nil)
      next unless td.is_a?(Hash)
      eff = td["effect"].to_s
      return true if eff == "gradient" || eff == "tricolor"
      return true if td["gilded"]
    end
    false
  rescue
    false
  end

  # ── Gilded gold bar with pulsing glow (opaque) ──
  def _draw_gilded_plate(bmp, x, y, w, h, phase)
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

  # ── Title color for chat names ───────────────────────────
  def _chat_title_color(td, alpha = 255)
    return Color.new(210, 210, 215, alpha) unless td.is_a?(Hash)
    c1 = td["color1"] || [255, 255, 255]
    c2 = td["color2"] || c1
    case td["effect"].to_s
    when "solid", "outline"
      Color.new(c1[0].to_i, c1[1].to_i, c1[2].to_i, alpha)
    when "gradient"
      phase = Time.now.to_f * (td["speed"] || 0.3).to_f
      t = (Math.sin(phase * Math::PI * 2) + 1.0) / 2.0
      r = (c1[0].to_i + (c2[0].to_i - c1[0].to_i) * t).to_i.clamp(0, 255)
      g = (c1[1].to_i + (c2[1].to_i - c1[1].to_i) * t).to_i.clamp(0, 255)
      b = (c1[2].to_i + (c2[2].to_i - c1[2].to_i) * t).to_i.clamp(0, 255)
      Color.new(r, g, b, alpha)
    when "tricolor"
      c3 = td["color3"] || c2
      phase = (Time.now.to_f * (td["speed"] || 0.25).to_f * 3.0) % 3.0
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
      Color.new(210, 210, 215, alpha)
    end
  rescue
    Color.new(210, 210, 215, alpha)
  end

  # ── Accessors for ChatInput ──────────────────────────────
  def set_input_text(text); @input_text = text; @input_dirty = true; end
  def get_input_text;       @input_text; end
  def clear_input;          @input_text = ""; @input_dirty = true; end
  def input_mode;           @input_mode; end

  def input_mode=(val)
    @input_mode = val
    @input_dirty = true
    @scroll_offset = 0 if val  # reset scroll when typing
  end

  def scroll_up(lines = 3)
    tab = ChatTabs.current_tab_name rescue nil
    return unless tab
    messages = ChatMessages.get_messages(tab).last(50)

    total_lines = 0
    messages.each do |msg|
      header = "#{msg[:sid]}/#{msg[:name]} : "
      total_lines += wrap_text(header + msg[:text], MSG_W - 4).length
    end

    visible = (MSG_H / 14).to_i
    max_scroll = [total_lines - visible, 0].max
    @scroll_offset = [@scroll_offset + lines, max_scroll].min
    @messages_dirty = true
  end

  def scroll_down(lines = 3)
    @scroll_offset = [@scroll_offset - lines, 0].max
    @messages_dirty = true
  end

  def reset_scroll
    @scroll_offset = 0
    @messages_dirty = true
  end

  # ── Mouse state (set by ChatInput) ──────────────────────
  def hover_tab=(idx)
    if @hover_tab != idx
      @hover_tab = idx
      @tabs_dirty = true
    end
  end
  def hover_tab; @hover_tab; end

  def mouse_over_panel=(v); @mouse_over_panel = v; end
  def mouse_over_panel;     @mouse_over_panel; end

  attr_accessor :mouse_over_handle

  # ── Dirty flag triggers ─────────────────────────────────
  def mark_tabs_dirty;     @tabs_dirty = true; end
  def mark_messages_dirty; @messages_dirty = true; end
  def mark_input_dirty;    @input_dirty = true; end

  # ── Geometry for hit testing (used by ChatInput) ────────
  def panel_x;  @bg_sprite.x; end
  def panel_y;  @base_y; end
  def handle_x; @handle_sprite.x; end
  def handle_y; @handle_y; end

  # ── Helpers ─────────────────────────────────────────────
  def _c(arr)
    Color.new(arr[0], arr[1], arr[2], arr[3] || 255)
  end

  def _draw_border(bmp, x, y, w, h, color, t)
    bmp.fill_rect(x, y, w, t, color)
    bmp.fill_rect(x, y + h - t, w, t, color)
    bmp.fill_rect(x, y, t, h, color)
    bmp.fill_rect(x + w - t, y, t, h, color)
  end

  # ── Dispose ─────────────────────────────────────────────
  def dispose
    [@handle_sprite, @bg_sprite, @tabs_sprite,
     @messages_sprite, @scrollbar_sprite, @input_sprite, @ctx_sprite].each do |s|
      next unless s
      s.bitmap.dispose rescue nil
      s.dispose rescue nil
    end
    @viewport.dispose rescue nil
  end
end

# Hook into Scene_Map update
class Scene_Map
  unless defined?(chat_scene_update_original)
    alias chat_scene_update_original update
  end

  def update
    chat_scene_update_original
    $chat_window.update if $chat_window
  end
end

# Initialize/cleanup on connect/disconnect
module MultiplayerClient
  class << self
    unless defined?(chat_connect_hook_original)
      alias chat_connect_hook_original connect
    end

    def connect(server_ip)
      result = chat_connect_hook_original(server_ip)
      if @connected
        begin
          $chat_window = ChatWindow.new
          $chat_initialized = true
        rescue => e
          # silently fail
        end
      end
      result
    end

    unless defined?(chat_disconnect_hook_original)
      alias chat_disconnect_hook_original disconnect
    end

    def disconnect
      chat_disconnect_hook_original
      if $chat_window
        begin
          $chat_window.dispose
          $chat_window = nil
          $chat_initialized = false
          ChatState.reset if defined?(ChatState)
          ChatTabs.reset if defined?(ChatTabs)
          ChatMessages.reset if defined?(ChatMessages)
          ChatBlockList.reset if defined?(ChatBlockList)
        rescue => e
          # silently fail
        end
      end
    end
  end
end
