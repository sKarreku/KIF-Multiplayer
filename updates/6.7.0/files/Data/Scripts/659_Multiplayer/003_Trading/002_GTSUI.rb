# ===========================================
# File: 002_GTSUI.rb
# Purpose: Global Trading System (GTS) UI
# Notes:
#   - Single unified screen: items + Pokemon in one filterable list
#   - Two-panel layout (left = browsable list, right = detail inspector)
#   - Mouse support, live search, kind filters, dark theme
#   - Custom overlay selectors for listing items/pokemon (no pbMessage)
#   - Click on listing = submenu (Buy/Inspect or Cancel)
#   - Reuses TradeUI helpers for bag/party, autosave & sprites
#   - F6 shortcut to open; ESC/BACK to close
#   - Requires 003_Client.rb with GTS client calls
# ===========================================

module GTSUI
  # ---- Colors ----
  BG_COLOR       = Color.new(20, 18, 30, 255)
  PANEL_BG       = Color.new(35, 32, 50)
  PANEL_BORDER   = Color.new(80, 70, 110)
  ROW_NORMAL     = Color.new(255, 255, 255, 8)
  ROW_SELECTED   = Color.new(255, 255, 255, 30)
  ROW_MINE       = Color.new(100, 80, 160, 20)
  WHITE          = Color.new(255, 255, 255)
  GRAY           = Color.new(180, 180, 180)
  DIM            = Color.new(120, 120, 140)
  SHADOW         = Color.new(40, 35, 55)
  GREEN          = Color.new(100, 220, 120)
  RED            = Color.new(220, 80, 80)
  YELLOW         = Color.new(240, 220, 80)
  ORANGE         = Color.new(240, 160, 60)
  FOOTER_BG      = Color.new(28, 25, 42)
  FOOTER_SEL     = Color.new(100, 80, 160)
  SEARCH_BG      = Color.new(50, 45, 70)
  PRICE_BOX_BG   = Color.new(50, 44, 72)
  PRICE_BOX_BD   = Color.new(90, 78, 130)
  ITEM_ACCENT    = Color.new(80, 140, 80)
  POKE_ACCENT    = Color.new(80, 70, 140)
  MINE_ACCENT    = Color.new(200, 180, 60)
  PLAT_COLOR     = Color.new(220, 200, 255)
  SECTION_LINE   = Color.new(65, 58, 90)
  MOVE_CELL_BG   = Color.new(42, 38, 60)
  MOVE_CELL_BD   = Color.new(70, 62, 100)
  OVL_BG         = Color.new(30, 26, 45)
  OVL_BD         = Color.new(100, 85, 150)
  OVL_SEL        = Color.new(80, 65, 130)

  # ---- Layout ----
  SCREEN_W     = 512
  SCREEN_H     = 384
  TITLE_H      = 28
  FOOTER_H     = 28
  LEFT_W       = 190
  RIGHT_W      = SCREEN_W - LEFT_W - 16   # 306
  SEARCH_H     = 22
  FILTER_H     = 20
  ROW_H        = 36
  CONTENT_Y    = TITLE_H + 4
  CONTENT_H    = SCREEN_H - TITLE_H - FOOTER_H - 8
  LIST_Y       = SEARCH_H + FILTER_H + 4
  LIST_H       = CONTENT_H - LIST_Y

  FOOTER_BUTTONS = ["List Item", "List Pokemon", "Refresh", "Close"]
  KIND_FILTERS   = [:all, :items, :pokemon]
  KIND_LABELS    = ["All", "Items", "Pokemon"]

  # ---- Small helpers (delegate to TradeUI where possible) ----
  def self.pbChooseNumber(caption, max, default_val=0)
    if defined?(TradeUI) && TradeUI.respond_to?(:small_number_popup)
      return TradeUI.small_number_popup(caption, max, default_val)
    end
    default_val.to_i
  end

  def self.pbChooseMoney(caption, max, default_val=0)
    if defined?(TradeUI) && TradeUI.respond_to?(:small_number_popup)
      return TradeUI.small_number_popup(caption, max, default_val)
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
    return MultiplayerPlatinum.cached_balance if defined?(MultiplayerPlatinum)
    0
  end

  def self.has_money?(amt)
    return MultiplayerPlatinum.can_afford?(amt) if defined?(MultiplayerPlatinum)
    false
  end

  def self.add_money(delta); true; end

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

  def self.commify(n)
    s = n.to_i.to_s
    s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  def self._try_free_text(prompt, default_str, maxlen)
    text = nil
    begin
      text = pbMessageFreeText(prompt, default_str, false, maxlen) if defined?(pbMessageFreeText)
    rescue; end
    if text.nil? && defined?(pbMessageFreeText)
      begin; text = pbMessageFreeText(prompt, default_str, false); rescue; end
    end
    if text.nil?
      begin; text = pbEnterText(prompt, maxlen) if defined?(pbEnterText); rescue; end
    end
    text
  end

  def self.pbAskPrice(caption, max=999_999, default_val=1000)
    GTSUI.pbChooseMoney(caption, max, default_val)
  end

  # ============================================================================
  # Scene_GTS
  # ============================================================================
  class Scene_GTS
    @@platinum_icon_cycle = 1

    def initialize
      @vp = nil; @bg = nil; @title_spr = nil; @left_spr = nil
      @right_spr = nil; @footer_spr = nil; @running = false

      @listings = []; @filtered = []; @sel_index = 0; @scroll = 0
      @search_text = ""; @search_active = false; @cursor_frame = 0
      @kind_filter = :all; @focus = :list; @footer_index = 0
      @rev = 0; @last_refresh_at = 0
      @pending_list_action = nil; @local_poke_cache = {}
      @list_icons = []; @detail_icons = []
      @toast_queue = []; @toast_spr = nil; @toast_timer = 0
      @uid = nil; @typebitmap = nil; @plat_icon = nil
      @move_rects = []; @move_ids = []; @move_tooltip = nil
      @hovered_move = nil
    end

    def main
      Graphics.freeze
      setup
      Graphics.transition(8)
      loop do
        Graphics.update; Input.update
        break unless @running
        if @search_active
          @cursor_frame += 1
          draw_left if @cursor_frame % 20 == 0
        end
        pump_gts_events
        process_toasts
        handle_input
        update_move_tooltip
      end
      Graphics.freeze
      teardown
      Graphics.transition(8)
    end

    # ========================================================================
    # Setup / Teardown
    # ========================================================================
    GTS_BGM = "GTSBrowsingMusic"
    GTS_BGM_FADE_OUT = 1.0   # seconds to fade out old music
    GTS_BGM_FADE_IN_VOL = 80 # volume for GTS music

    def setup
      @running = true
      @uid = my_uid

      # Save current BGM and crossfade to GTS music
      @saved_bgm = $game_system.getPlayingBGM rescue nil
      pbBGMFade(GTS_BGM_FADE_OUT)
      # Wait for fade to complete, then start GTS music
      (GTS_BGM_FADE_OUT * 40).to_i.times { Graphics.update }
      pbBGMPlay(GTS_BGM, GTS_BGM_FADE_IN_VOL)

      # Load type bitmap
      begin
        @typebitmap = AnimatedBitmap.new(_INTL("Graphics/Pictures/types"))
      rescue
        @typebitmap = nil
      end

      # Load platinum icon (cycling)
      load_plat_icon

      @vp = Viewport.new(0, 0, SCREEN_W, SCREEN_H)
      @vp.z = 100_000

      @bg = Sprite.new(@vp)
      @bg.bitmap = Bitmap.new(SCREEN_W, SCREEN_H)
      @bg.bitmap.fill_rect(0, 0, SCREEN_W, SCREEN_H, BG_COLOR)

      @title_spr = Sprite.new(@vp)
      @title_spr.bitmap = Bitmap.new(SCREEN_W, TITLE_H)
      @title_spr.z = 10

      @left_spr = Sprite.new(@vp)
      @left_spr.bitmap = Bitmap.new(LEFT_W, CONTENT_H)
      @left_spr.x = 4; @left_spr.y = CONTENT_Y; @left_spr.z = 10

      @right_spr = Sprite.new(@vp)
      @right_spr.bitmap = Bitmap.new(RIGHT_W, CONTENT_H)
      @right_spr.x = LEFT_W + 12; @right_spr.y = CONTENT_Y; @right_spr.z = 10

      @footer_spr = Sprite.new(@vp)
      @footer_spr.bitmap = Bitmap.new(SCREEN_W, FOOTER_H)
      @footer_spr.y = SCREEN_H - FOOTER_H; @footer_spr.z = 10

      @toast_spr = Sprite.new(@vp)
      @toast_spr.bitmap = Bitmap.new(SCREEN_W, 22)
      @toast_spr.y = TITLE_H; @toast_spr.z = 900; @toast_spr.visible = false

      @move_tooltip = Sprite.new(@vp)
      @move_tooltip.bitmap = Bitmap.new(220, 110)
      @move_tooltip.z = 500; @move_tooltip.visible = false

      begin; MultiplayerClient.gts_snapshot(0); rescue; end
      @last_refresh_at = Graphics.frame_count

      draw_title; draw_left; draw_right; draw_footer
    end

    def teardown
      clear_row_icons; clear_detail_icons
      @typebitmap.dispose if @typebitmap && !@typebitmap.disposed? rescue nil
      begin; @move_tooltip.bitmap.dispose; @move_tooltip.dispose; rescue; end if @move_tooltip
      [@toast_spr, @footer_spr, @right_spr, @left_spr, @title_spr, @bg].compact.each do |s|
        begin; s.bitmap.dispose if s.bitmap && !s.bitmap.disposed?; s.dispose; rescue; end
      end
      @vp.dispose if @vp; @vp = nil

      # Fade out GTS music and restore previous BGM
      pbBGMFade(GTS_BGM_FADE_OUT)
      (GTS_BGM_FADE_OUT * 40).to_i.times { Graphics.update }
      pbBGMPlay(@saved_bgm) if @saved_bgm
    end

    def load_plat_icon
      @plat_icon = nil
      begin
        icon_name = "platinum_icon#{@@platinum_icon_cycle == 1 ? '' : @@platinum_icon_cycle}"
        if pbResolveBitmap("Graphics/Pictures/Trainer Card/#{icon_name}")
          @plat_icon = RPG::Cache.load_bitmap("Graphics/Pictures/Trainer Card/", icon_name)
        elsif pbResolveBitmap("Graphics/Pictures/#{icon_name}")
          @plat_icon = RPG::Cache.load_bitmap("Graphics/Pictures/", icon_name)
        end
        @@platinum_icon_cycle = (@@platinum_icon_cycle % 3) + 1
      rescue; end
    end

    # Draw the cycling plat icon onto a bitmap at given position (14x14)
    def draw_plat_icon(bmp, x, y, size = 14)
      if @plat_icon
        src = Rect.new(0, 0, @plat_icon.width, @plat_icon.height)
        dest = Rect.new(x, y, size, size)
        bmp.stretch_blt(dest, @plat_icon, src)
        return true
      end
      false
    end

    # Draw type icon from the types spritesheet (64x28 per icon, scaled to 48x21)
    TYPE_ICON_W = 64
    TYPE_ICON_H = 28
    TYPE_DRAW_W = TYPE_ICON_W
    TYPE_DRAW_H = TYPE_ICON_H

    def draw_type_icon(bmp, type_sym, x, y)
      return unless @typebitmap && defined?(GameData::Type)
      begin
        type_data = GameData::Type.get(type_sym)
        type_num = type_data.id_number rescue 0
        src_rect = Rect.new(0, type_num * TYPE_ICON_H, TYPE_ICON_W, TYPE_ICON_H)
        bmp.blt(x, y, @typebitmap.bitmap, src_rect)
        # Clear the 2x2 corner blocks (source sheet has stray white corners)
        clear = Color.new(0, 0, 0, 0)
        bmp.fill_rect(x, y, 2, 2, clear)
        bmp.fill_rect(x + TYPE_ICON_W - 2, y, 2, 2, clear)
        bmp.fill_rect(x, y + TYPE_ICON_H - 2, 2, 2, clear)
        bmp.fill_rect(x + TYPE_ICON_W - 2, y + TYPE_ICON_H - 2, 2, 2, clear)
      rescue; end
    end

    # ========================================================================
    # Data helpers
    # ========================================================================
    def my_uid
      return MultiplayerClient.platinum_uuid if MultiplayerClient.respond_to?(:platinum_uuid)
      @uid
    end

    def is_mine?(entry)
      uid = my_uid; return false unless uid
      entry["seller"].to_s == uid.to_s
    end

    def listing_name(entry)
      if entry["kind"].to_s == "item"
        GTSUI.item_name(entry["item_id"])
      else
        pj = entry["pokemon_json"] || {}
        name = pj["name"].to_s
        if name.empty? && defined?(GameData::Species) && pj["species"]
          begin; name = GameData::Species.get(GTSUI.resolve_species_id(pj["species"])).name; rescue; name = "Pokemon"; end
        end
        name = "Pokemon" if name.empty?
        name
      end
    end

    def apply_filter
      list = @listings
      case @kind_filter
      when :items   then list = list.select { |l| l["kind"].to_s == "item" }
      when :pokemon then list = list.select { |l| l["kind"].to_s == "pokemon" }
      end
      unless @search_text.empty?
        q = @search_text.downcase
        list = list.select do |l|
          listing_name(l).downcase.include?(q) ||
          (l["seller_name"] || l["seller"] || "").to_s.downcase.include?(q)
        end
      end
      # Sort: stamped shinies first, then unstamped shinies, then everything else
      list = list.sort_by do |l|
        pj = (l["kind"].to_s == "pokemon") ? (l["pokemon_json"] || {}) : {}
        is_shiny = shiny_label_from(pj) != "No"
        stamped = !!(pj["shiny_odds_stamped"] || pj[:shiny_odds_stamped])
        is_shiny ? (stamped ? 0 : 1) : 2
      end
      @filtered = list
      @sel_index = @sel_index.clamp(0, [(@filtered.length - 1), 0].max)
      ensure_visible
    end

    def rows_per_page; (LIST_H / ROW_H).floor; end

    def ensure_visible
      rpp = rows_per_page; return if @filtered.empty?
      @scroll = @sel_index if @sel_index < @scroll
      @scroll = @sel_index - rpp + 1 if @sel_index >= @scroll + rpp
      @scroll = @scroll.clamp(0, [@filtered.length - rpp, 0].max)
    end

    def selected_listing
      return nil if @filtered.empty?; @filtered[@sel_index]
    end

    # ========================================================================
    # Drawing — Title
    # ========================================================================
    def draw_title
      b = @title_spr.bitmap; b.clear
      b.fill_rect(0, 0, SCREEN_W, TITLE_H, FOOTER_BG)

      pbSetSystemFont(b)
      b.font.size = 20
      pbDrawShadowText(b, 8, 0, 220, TITLE_H, "Global Trading System", WHITE, SHADOW)

      # Platinum balance with icon
      b.font.size = 14
      bal = GTSUI.money
      bal_text = GTSUI.commify(bal)
      tw = b.text_size(bal_text).width
      icon_sz = 14
      total_w = icon_sz + 4 + tw
      bx = SCREEN_W - total_w - 10
      if draw_plat_icon(b, bx, (TITLE_H - icon_sz) / 2, icon_sz)
        pbDrawShadowText(b, bx + icon_sz + 4, 0, tw + 4, TITLE_H, bal_text, PLAT_COLOR, SHADOW)
      else
        pbDrawShadowText(b, SCREEN_W - tw - 24, 0, tw + 4, TITLE_H, "#{bal_text} Pt", PLAT_COLOR, SHADOW)
      end

    end

    # ========================================================================
    # Drawing — Left Panel
    # ========================================================================
    def draw_left
      b = @left_spr.bitmap; b.clear
      draw_rounded_rect(b, 0, 0, LEFT_W, CONTENT_H, PANEL_BG)
      draw_border(b, 0, 0, LEFT_W, CONTENT_H, PANEL_BORDER)

      # Search bar
      search_bg = @search_active ? Color.new(70, 60, 100) : SEARCH_BG
      draw_rounded_rect(b, 4, 4, LEFT_W - 8, SEARCH_H, search_bg)
      draw_border(b, 4, 4, LEFT_W - 8, SEARCH_H, @search_active ? Color.new(140, 120, 200) : PANEL_BORDER) if @search_active
      pbSetSmallFont(b)
      if @search_active
        cursor = (@cursor_frame / 20) % 2 == 0 ? "|" : ""
        pbDrawShadowText(b, 10, 2, LEFT_W - 20, SEARCH_H, @search_text + cursor, WHITE, SHADOW)
      elsif @search_text.empty?
        pbDrawShadowText(b, 10, 2, LEFT_W - 20, SEARCH_H, "Search...", DIM, SHADOW)
      else
        pbDrawShadowText(b, 10, 2, LEFT_W - 20, SEARCH_H, @search_text, WHITE, SHADOW)
      end

      # Filter bar
      filter_y = SEARCH_H + 2
      btn_w = (LEFT_W - 12) / 3
      b.font.size = 14
      KIND_FILTERS.each_with_index do |filt, i|
        bx = 6 + i * btn_w
        if @kind_filter == filt
          draw_rounded_rect(b, bx, filter_y, btn_w - 2, FILTER_H - 2, FOOTER_SEL)
          pbDrawShadowText(b, bx, filter_y - 2, btn_w - 2, FILTER_H, KIND_LABELS[i], WHITE, SHADOW, 2)
        else
          pbDrawShadowText(b, bx, filter_y - 2, btn_w - 2, FILTER_H, KIND_LABELS[i], DIM, SHADOW, 2)
        end
      end

      clear_row_icons
      rpp = rows_per_page
      visible = @filtered[@scroll, rpp] || []

      if @filtered.empty?
        b.font.size = 14
        pbDrawShadowText(b, 0, CONTENT_H / 2 - 8, LEFT_W, 16, "No listings", DIM, SHADOW, 2)
        return
      end

      visible.each_with_index do |entry, i|
        real_index = @scroll + i
        y = LIST_Y + i * ROW_H
        draw_list_row(b, entry, y, i, (real_index == @sel_index && @focus == :list), is_mine?(entry))
      end

      pbSetSmallFont(b)
      pbDrawShadowText(b, LEFT_W / 2, LIST_Y - 10, -1, 12, "^", GRAY, SHADOW, 2) if @scroll > 0
      pbDrawShadowText(b, LEFT_W / 2, LIST_Y + rpp * ROW_H - 2, -1, 12, "v", GRAY, SHADOW, 2) if @scroll + rpp < @filtered.length
    end

    def draw_list_row(b, entry, y, vis_idx, selected, mine)
      w = LEFT_W
      is_item = entry["kind"].to_s == "item"

      bg = selected ? ROW_SELECTED : (mine ? ROW_MINE : ROW_NORMAL)
      b.fill_rect(4, y, w - 8, ROW_H - 2, bg)

      # Accent bar
      accent = mine ? MINE_ACCENT : (is_item ? ITEM_ACCENT : POKE_ACCENT)
      b.fill_rect(4, y, 3, ROW_H - 2, accent)

      # Icon
      icon_cx = @left_spr.x + 24
      icon_cy = @left_spr.y + y + (ROW_H / 2)
      begin
        if is_item
          ic = ItemIconSprite.new(0, 0, nil, @vp)
          ic.setOffset(PictureOrigin::Center)
          ic.item = GTSUI.item_sym(entry["item_id"])
          ic.x = icon_cx; ic.y = icon_cy
          ic.zoom_x = 0.55; ic.zoom_y = 0.55; ic.z = 20
          @list_icons << ic
        else
          pj = entry["pokemon_json"] || {}
          tmp = build_temp_pokemon_from_json(pj) rescue nil
          is_fusion = (tmp && tmp.respond_to?(:isFusion?) && tmp.isFusion?) rescue false
          if is_fusion && tmp
            # Fusions: use PokemonIconSprite which calls createFusionIcon
            ic = PokemonIconSprite.new(tmp, @vp)
            ic.icon_offset_x = 0; ic.icon_offset_y = 0
            fw = (ic.src_rect.width * 0.5).to_i
            fh = (ic.src_rect.height * 0.5).to_i
            ic.x = icon_cx - fw / 2; ic.y = icon_cy - fh / 2
            ic.zoom_x = 0.5; ic.zoom_y = 0.5; ic.z = 20
            @list_icons << ic
          else
            # Regular pokemon: use PokemonSpeciesIconSprite
            species = GTSUI.resolve_species_id(pj["species"]) rescue nil
            if species
              ic = PokemonSpeciesIconSprite.new(species, @vp)
              ic.setOffset(PictureOrigin::Center)
              g = (pj["gender"].to_i rescue 0)
              f = (pj["form"].to_i rescue 0)
              s = !!(pj["shiny"] || pj["head_shiny"] || pj["body_shiny"] || pj["fakeshiny"])
              ic.pbSetParams(species, g, f, s)
              ic.x = icon_cx; ic.y = icon_cy
              ic.zoom_x = 0.5; ic.zoom_y = 0.5; ic.z = 20
              @list_icons << ic
            end
          end
        end
      rescue; end

      text_x = 42
      pbSetSmallFont(b)

      # Name
      name = listing_name(entry)
      max_name_w = w - text_x - 56
      name = name[0..(max_name_w / 7)] + ".." if b.text_size(name).width > max_name_w
      pbDrawShadowText(b, text_x, y - 1, w - text_x - 8, 18, name, mine ? YELLOW : WHITE, SHADOW)

      # Seller
      seller = mine ? "You" : (entry["seller_name"] || "").to_s
      b.font.size = 12
      pbDrawShadowText(b, text_x, y + 15, w - text_x - 8, 16, seller, DIM, SHADOW)

      # Price with plat icon
      price = entry["price"].to_i
      price_text = GTSUI.commify(price)
      b.font.size = 13
      ptw = b.text_size(price_text).width
      px = w - ptw - 12
      icon_drawn = draw_plat_icon(b, w - 14, y + 1, 11)
      if icon_drawn
        pbDrawShadowText(b, px - 4, y, ptw + 4, 18, price_text, PLAT_COLOR, SHADOW)
      else
        pbDrawShadowText(b, px, y, ptw + 4, 18, price_text, PLAT_COLOR, SHADOW)
      end
    end

    # ========================================================================
    # Drawing — Right Panel
    # ========================================================================
    def draw_right
      b = @right_spr.bitmap; b.clear
      clear_detail_icons
      @move_rects = []; @move_ids = []; @hovered_move = nil
      @move_tooltip.visible = false if @move_tooltip
      draw_rounded_rect(b, 0, 0, RIGHT_W, CONTENT_H, PANEL_BG)
      draw_border(b, 0, 0, RIGHT_W, CONTENT_H, PANEL_BORDER)

      entry = selected_listing
      unless entry
        pbSetSystemFont(b); b.font.size = 16
        pbDrawShadowText(b, 0, CONTENT_H / 2 - 12, RIGHT_W, 24, "Select a listing", DIM, SHADOW, 2)
        return
      end

      if entry["kind"].to_s == "item"
        draw_detail_item(b, entry)
      else
        draw_detail_pokemon(b, entry)
      end
    end

    # ---------- Item detail ----------
    def draw_detail_item(b, entry)
      x = 12; y = 10

      begin
        icon = ItemIconSprite.new(0, 0, nil, @vp)
        icon.setOffset(PictureOrigin::Center)
        icon.x = @right_spr.x + 36; icon.y = @right_spr.y + 36
        icon.item = GTSUI.item_sym(entry["item_id"]); icon.z = 20
        @detail_icons << icon
      rescue; end

      pbSetSystemFont(b); b.font.size = 18
      pbDrawShadowText(b, x + 56, y, RIGHT_W - 72, 22, GTSUI.item_name(entry["item_id"]), WHITE, SHADOW)
      y += 22

      pbSetSmallFont(b)
      pbDrawShadowText(b, x + 56, y, -1, 16, "Qty: #{entry["qty"].to_i}", GRAY, SHADOW)
      y += 24

      y = draw_price_box(b, entry, x, y)

      b.fill_rect(x, y, RIGHT_W - 24, 1, SECTION_LINE); y += 6

      desc = item_description(entry["item_id"])
      unless desc.empty?
        pbSetSmallFont(b)
        pbDrawShadowText(b, x, y, -1, 14, "Description", DIM, SHADOW); y += 16
        word_wrap(b, desc, RIGHT_W - 28).each do |line|
          break if y + 14 > CONTENT_H - 28
          pbDrawShadowText(b, x, y, RIGHT_W - 24, 14, line, GRAY, SHADOW); y += 14
        end
      end

      draw_action_hint(b, entry)
    end

    # ---------- Pokemon detail ----------
    def draw_detail_pokemon(b, entry)
      x = 12; y = 6
      pj = entry["pokemon_json"] || {}
      pkm = build_temp_pokemon_from_json(pj)

      # Full-sized Pokemon sprite (like summary screen)
      begin
        pspr = PokemonSprite.new(@vp)
        pspr.setOffset(PictureOrigin::Center)
        if pkm
          pspr.setPokemonBitmap(pkm)
        else
          species = GTSUI.resolve_species_id(pj["species"])
          s = !!(pj["shiny"] || pj["head_shiny"] || pj["body_shiny"] || pj["fakeshiny"])
          pspr.setPokemonBitmapFromId(species, false, s)
        end
        # Fixed 192x192 target box — scales any source sprite to that.
        src_w = (pspr.bitmap.width rescue 128).to_f
        scale = (192.0 / src_w)
        pspr.zoom_x = scale; pspr.zoom_y = scale
        pspr.x = @right_spr.x + 50; pspr.y = @right_spr.y + 60; pspr.z = 20
        @detail_icons << pspr
      rescue; end

      # Name + Level — to the right of the sprite
      name = pj["name"].to_s
      if name.empty? && defined?(GameData::Species) && pj["species"]
        begin; name = GameData::Species.get(GTSUI.resolve_species_id(pj["species"])).name; rescue; name = "Pokemon"; end
      end
      name = "Pokemon" if name.empty?

      info_x = x + 90
      pbSetSystemFont(b); b.font.size = 18
      pbDrawShadowText(b, info_x, y, RIGHT_W - info_x - 50, 22, name, WHITE, SHADOW)
      lvl = (pj["level"] || 1).to_i
      pbDrawShadowText(b, RIGHT_W - 56, y, 44, 22, "Lv.#{lvl}", GRAY, SHADOW)
      y += 22

      # Nature | Ability
      nature_str = get_nature_str(pkm, pj)
      ability_str = get_ability_str(pkm, pj)
      pbSetSmallFont(b)
      line = "#{nature_str}  |  #{ability_str}"
      max_line_w = RIGHT_W - info_x - 16
      if b.text_size(line).width > max_line_w
        while b.text_size("#{nature_str} | #{ability_str}..").width > max_line_w && ability_str.length > 4
          ability_str = ability_str[0...-1]
        end
        line = "#{nature_str} | #{ability_str}.."
      end
      pbDrawShadowText(b, info_x, y, max_line_w, 16, line, GRAY, SHADOW)
      y += 16

      # 2nd ability for Family Pokemon
      begin
        if pkm && pkm.respond_to?(:has_family?) && pkm.has_family? && pkm.respond_to?(:ability2)
          ab2 = pkm.ability2
          if ab2
            ab2_name = ab2.name.to_s rescue ab2.to_s
            pbDrawShadowText(b, info_x, y, max_line_w, 14, "2nd: #{ab2_name}", DIM, SHADOW)
            y += 14
          end
        end
      rescue; end
      y += 12  # gap before types

      # Type icons — beside sprite, below nature
      begin
        species_data = nil
        if pkm && pkm.respond_to?(:species_data)
          species_data = pkm.species_data
        elsif defined?(GameData::Species) && pj["species"]
          species_data = GameData::Species.get(GTSUI.resolve_species_id(pj["species"]))
        end
        if species_data
          type1 = species_data.type1 rescue nil
          type2 = species_data.type2 rescue nil
          tx = info_x
          if type1
            draw_type_icon(b, type1, tx, y)
            tx += TYPE_DRAW_W + 4
          end
          if type2 && type2 != type1
            draw_type_icon(b, type2, tx, y)
          end
        end
      rescue; end
      y = 110  # Fixed y after sprite area (extra gap so sprite doesn't overlay price)

      # Price box
      y = draw_price_box(b, entry, x, y)

      # Moves — bordered 2x2 grid
      b.fill_rect(x, y, RIGHT_W - 24, 1, SECTION_LINE); y += 4
      pbSetSmallFont(b)
      pbDrawShadowText(b, x, y, -1, 14, "Moves", DIM, SHADOW); y += 20

      move_names = get_move_names(pkm, pj)
      @move_ids = get_move_ids(pkm, pj)
      @move_rects = []
      cell_w = (RIGHT_W - 28) / 2
      cell_h = 18
      b.font.size = 13
      4.times do |i|
        cx = x + (i % 2) * (cell_w + 2)
        cy = y + (i / 2) * (cell_h + 2)
        draw_rounded_rect(b, cx, cy, cell_w, cell_h, MOVE_CELL_BG)
        draw_border(b, cx, cy, cell_w, cell_h, MOVE_CELL_BD)
        mv = move_names[i] || "-"
        pbDrawShadowText(b, cx + 4, cy, cell_w - 8, cell_h, mv, GRAY, SHADOW)
        # Store screen-space rect for tooltip hover
        @move_rects << { x: @right_spr.x + cx, y: @right_spr.y + cy, w: cell_w, h: cell_h }
      end
      y += cell_h * 2 + 6

      # Fusion info (Head / Body)
      y = draw_fusion_info(b, pkm, pj, x, y)

      # Shiny info + family (no IV/EV stats — use Inspect for those)
      draw_shiny_family_info(b, pkm, pj, x, y)

      draw_action_hint(b, entry)
    end

    # ---------- Price box ----------
    def draw_price_box(b, entry, x, y)
      price = entry["price"].to_i
      seller = is_mine?(entry) ? "You" : (entry["seller_name"] || "").to_s

      box_x = x - 4; box_w = RIGHT_W - 16; box_h = 28
      draw_rounded_rect(b, box_x, y, box_w, box_h, PRICE_BOX_BG)
      draw_border(b, box_x, y, box_w, box_h, PRICE_BOX_BD)

      pbSetSystemFont(b); b.font.size = 15
      price_text = GTSUI.commify(price)
      ptw = b.text_size(price_text).width
      icon_x = x + 4
      if draw_plat_icon(b, icon_x, y + 6, 16)
        pbDrawShadowText(b, icon_x + 20, y, ptw + 4, box_h, price_text, PLAT_COLOR, SHADOW)
      else
        pbDrawShadowText(b, icon_x, y, -1, box_h, "#{price_text} Pt", PLAT_COLOR, SHADOW)
      end

      pbSetSmallFont(b)
      stw = b.text_size("by #{seller}").width
      pbDrawShadowText(b, box_x + box_w - stw - 12, y + 5, stw + 8, 18, "by #{seller}", DIM, SHADOW)

      y + box_h + 4
    end

    # ---------- Fusion info (Head / Body) ----------
    def draw_fusion_info(b, pkm, pj, x, y)
      is_fusion = false
      head_name = nil; body_name = nil
      begin
        if pkm && pkm.respond_to?(:isFusion?) && pkm.isFusion?
          is_fusion = true
          body_id = getBasePokemonID(pkm.species, true)
          head_id = getBasePokemonID(pkm.species, false)
          head_name = GameData::Species.get(head_id).name rescue "???"
          body_name = GameData::Species.get(body_id).name rescue "???"
        end
      rescue; end
      return y unless is_fusion && head_name && body_name

      b.fill_rect(x, y, RIGHT_W - 24, 1, SECTION_LINE); y += 4
      pbSetSmallFont(b)
      pbDrawShadowText(b, x, y, -1, 14, "Head: #{head_name}  |  Body: #{body_name}", GRAY, SHADOW); y += 18
      y
    end

    # ---------- Stat table ----------
    def draw_stat_table(b, pkm, pj, x, y)
      headers = ["HP", "Atk", "Def", "SpA", "SpD", "Spe"]
      order = [:HP, :ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED]
      iv_map, ev_map = get_stat_maps(pkm, pj)

      label_w = 22
      col_w = (RIGHT_W - 24 - label_w) / 6

      pbSetSmallFont(b); b.font.size = 12
      headers.each_with_index do |h, i|
        pbDrawShadowText(b, x + label_w + i * col_w, y, col_w, 14, h, DIM, SHADOW, 2)
      end
      y += 14

      b.font.size = 13
      pbDrawShadowText(b, x, y, label_w, 14, "IV", DIM, SHADOW)
      if iv_map
        order.each_with_index do |stat, i|
          val = (iv_map[stat] || 0).to_i
          c = val >= 31 ? GREEN : (val >= 20 ? WHITE : GRAY)
          pbDrawShadowText(b, x + label_w + i * col_w, y, col_w, 14, val.to_s, c, SHADOW, 2)
        end
      end
      y += 14

      pbDrawShadowText(b, x, y, label_w, 14, "EV", DIM, SHADOW)
      if ev_map
        order.each_with_index do |stat, i|
          val = (ev_map[stat] || 0).to_i
          c = val >= 252 ? GREEN : (val > 0 ? WHITE : DIM)
          pbDrawShadowText(b, x + label_w + i * col_w, y, col_w, 14, val.to_s, c, SHADOW, 2)
        end
      end
      y + 14
    end

    # ---------- Shiny + Family info ----------
    def draw_shiny_family_info(b, pkm, pj, x, y)
      pj ||= {}
      shiny_type = shiny_label_from(pj)

      if shiny_type != "No"
        pbSetSmallFont(b)
        shiny_c = case shiny_type
                  when "Natural" then GREEN
                  when "Fake" then ORANGE
                  else YELLOW
                  end
        pbDrawShadowText(b, x, y, -1, 14, "Shiny: #{shiny_type}", shiny_c, SHADOW)
        y += 14

        y += 4  # spacing after "Shiny:" line

        # Odds from pokemon_json (same format as summary: numerator/65536)
        odds = pj["shiny_catch_odds"] || pj[:shiny_catch_odds]
        stamped = pj["shiny_odds_stamped"] || pj[:shiny_odds_stamped]
        if odds && stamped
          odds_val = odds.to_i
          ctx = pj["shiny_catch_context"] || pj[:shiny_catch_context]
          ctx_label = ctx ? " (#{ctx})" : ""
          pbDrawShadowText(b, x, y, -1, 14, "Shiny Odds: #{GTSUI.commify(odds_val)}/65536#{ctx_label}", DIM, SHADOW)
          y += 18
        end

        # Family — check actual family/subfamily fields, not has_family_data
        family_rate = pj["family_catch_rate"] || pj[:family_catch_rate]
        has_family = (!pj["family"].nil? && !pj["subfamily"].nil?) ||
                     (pkm && pkm.respond_to?(:has_family_data?) && pkm.has_family_data?)
        if family_rate && has_family
          pbDrawShadowText(b, x, y, -1, 14, "Family Odds: #{family_rate}/100", DIM, SHADOW)
          y += 14
        end
      end
    end

    # ---------- Action hint ----------
    def draw_action_hint(b, entry)
      pbSetSmallFont(b)
      hint_y = CONTENT_H - 20
      b.fill_rect(8, hint_y - 4, RIGHT_W - 16, 1, SECTION_LINE)
      if is_mine?(entry)
        pbDrawShadowText(b, 12, hint_y, RIGHT_W - 24, 14, "Click or [Z] Cancel", DIM, SHADOW, 2)
      else
        if entry["kind"].to_s == "pokemon"
          pbDrawShadowText(b, 12, hint_y, RIGHT_W - 24, 14, "Click or [Z] to act", DIM, SHADOW, 2)
        else
          pbDrawShadowText(b, 12, hint_y, RIGHT_W - 24, 14, "Click or [Z] Buy", DIM, SHADOW, 2)
        end
      end
    end

    # ---------- Footer ----------
    def draw_footer
      b = @footer_spr.bitmap; b.clear
      b.fill_rect(0, 0, SCREEN_W, FOOTER_H, FOOTER_BG)
      pbSetSmallFont(b)
      btn_w = SCREEN_W / FOOTER_BUTTONS.length
      FOOTER_BUTTONS.each_with_index do |label, i|
        bx = i * btn_w
        if @focus == :footer && @footer_index == i
          draw_rounded_rect(b, bx + 4, 4, btn_w - 8, FOOTER_H - 8, FOOTER_SEL)
          pbDrawShadowText(b, bx, 0, btn_w, FOOTER_H, label, WHITE, SHADOW, 2)
        else
          pbDrawShadowText(b, bx, 0, btn_w, FOOTER_H, label, GRAY, SHADOW, 2)
        end
      end
    end

    # ========================================================================
    # Custom Overlay — Scrollable Selector (replaces broken pbMessage)
    # ========================================================================
    def overlay_select(title, items, cancel_index = -1)
      # items = [{label: "...", icon_sym: :POTION, icon_species: nil}, ...]
      # Returns selected index, or -1 if cancelled
      dim = Sprite.new(@vp)
      dim.bitmap = Bitmap.new(SCREEN_W, SCREEN_H)
      dim.bitmap.fill_rect(0, 0, SCREEN_W, SCREEN_H, Color.new(0, 0, 0, 140))
      dim.z = 800

      box_w = 300; row_h = 26
      max_rows = [items.length, 10].min
      box_h = 24 + max_rows * row_h + 8  # title + rows + padding
      box_x = (SCREEN_W - box_w) / 2
      box_y = (SCREEN_H - box_h) / 2

      box = Sprite.new(@vp)
      box.bitmap = Bitmap.new(box_w, box_h)
      box.x = box_x; box.y = box_y; box.z = 801

      ovl_icons = []
      sel = 0; scroll = 0
      result = -1

      redraw_overlay = lambda do
        bmp = box.bitmap; bmp.clear
        draw_rounded_rect(bmp, 0, 0, box_w, box_h, OVL_BG)
        draw_border(bmp, 0, 0, box_w, box_h, OVL_BD)

        pbSetSmallFont(bmp)
        pbDrawShadowText(bmp, 8, 2, box_w - 16, 20, title, WHITE, SHADOW)

        # Dispose old icons
        ovl_icons.each { |ic| ic.dispose rescue nil }; ovl_icons.clear

        visible = items[scroll, max_rows] || []
        visible.each_with_index do |item, i|
          ry = 24 + i * row_h
          real_i = scroll + i
          if real_i == sel
            bmp.fill_rect(4, ry, box_w - 8, row_h - 2, OVL_SEL)
          end

          text_x = 8
          # Spawn icon if applicable
          if item[:icon_sym]
            begin
              ic = ItemIconSprite.new(0, 0, nil, @vp)
              ic.setOffset(PictureOrigin::Center)
              ic.item = item[:icon_sym]
              ic.x = box_x + 20; ic.y = box_y + ry + row_h / 2
              ic.zoom_x = 0.5; ic.zoom_y = 0.5; ic.z = 802
              ovl_icons << ic
              text_x = 36
            rescue; end
          elsif item[:icon_pokemon]
            begin
              ic = PokemonIconSprite.new(item[:icon_pokemon], @vp)
              ic.icon_offset_x = 0; ic.icon_offset_y = 0
              fw = (ic.src_rect.width * 0.45).to_i
              fh = (ic.src_rect.height * 0.45).to_i
              ic.x = box_x + 20 - fw / 2; ic.y = box_y + ry + row_h / 2 - fh / 2
              ic.zoom_x = 0.45; ic.zoom_y = 0.45; ic.z = 802
              ovl_icons << ic
              text_x = 36
            rescue; end
          elsif item[:icon_species]
            begin
              ic = PokemonSpeciesIconSprite.new(item[:icon_species], @vp)
              ic.setOffset(PictureOrigin::Center)
              if item[:icon_params]
                ic.pbSetParams(*item[:icon_params])
              end
              ic.x = box_x + 20; ic.y = box_y + ry + row_h / 2
              ic.zoom_x = 0.45; ic.zoom_y = 0.45; ic.z = 802
              ovl_icons << ic
              text_x = 36
            rescue; end
          end

          label_color = (item[:label] == "Cancel") ? DIM : WHITE
          pbDrawShadowText(bmp, text_x, ry - 1, box_w - text_x - 8, row_h, item[:label], label_color, SHADOW)
        end

        # Scroll arrows
        pbDrawShadowText(bmp, box_w / 2, 14, -1, 10, "^", GRAY, SHADOW, 2) if scroll > 0
        pbDrawShadowText(bmp, box_w / 2, 24 + max_rows * row_h - 4, -1, 10, "v", GRAY, SHADOW, 2) if scroll + max_rows < items.length
      end

      redraw_overlay.call

      loop do
        Graphics.update; Input.update

        changed = false
        if Input.trigger?(Input::B) || Input.trigger?(Input::MOUSERIGHT)
          result = cancel_index >= 0 ? cancel_index : -1
          break
        end

        if Input.trigger?(Input::C) || Input.trigger?(Input::MOUSELEFT)
          # Mouse click: check if inside box
          if Input.trigger?(Input::MOUSELEFT)
            mx = Input.mouse_x rescue nil; my = Input.mouse_y rescue nil
            if mx && my && mx >= box_x && mx < box_x + box_w && my >= box_y + 24 && my < box_y + box_h
              row = ((my - box_y - 24) / row_h).floor
              clicked_i = scroll + row
              if clicked_i >= 0 && clicked_i < items.length
                sel = clicked_i
                result = sel; break
              end
            elsif mx && my
              # Click outside = cancel
              result = cancel_index >= 0 ? cancel_index : -1; break
            end
          else
            result = sel; break
          end
        end

        if Input.repeat?(Input::UP)
          sel = (sel - 1) % items.length
          scroll = sel if sel < scroll
          scroll = sel - max_rows + 1 if sel >= scroll + max_rows
          scroll = scroll.clamp(0, [items.length - max_rows, 0].max)
          changed = true
        elsif Input.repeat?(Input::DOWN)
          sel = (sel + 1) % items.length
          scroll = sel if sel < scroll
          scroll = sel - max_rows + 1 if sel >= scroll + max_rows
          scroll = scroll.clamp(0, [items.length - max_rows, 0].max)
          changed = true
        end

        # Mouse hover
        begin
          mx = Input.mouse_x; my = Input.mouse_y
          if mx && my && mx >= box_x && mx < box_x + box_w && my >= box_y + 24 && my < box_y + box_h
            row = ((my - box_y - 24) / row_h).floor
            hover_i = scroll + row
            if hover_i >= 0 && hover_i < items.length && hover_i != sel
              sel = hover_i; changed = true
            end
          end
        rescue; end

        redraw_overlay.call if changed
      end

      ovl_icons.each { |ic| ic.dispose rescue nil }
      box.bitmap.dispose rescue nil; box.dispose rescue nil
      dim.bitmap.dispose rescue nil; dim.dispose rescue nil
      result
    end

    # ========================================================================
    # Network Events
    # ========================================================================
    def pump_gts_events
      return unless defined?(MultiplayerClient)
      # Drain system toasts so they don't pile up for the map
      drain_system_toasts
      dirty = false
      begin
        while MultiplayerClient.gts_events_pending?
          ev = MultiplayerClient.next_gts_event; break unless ev
          ev_type = (ev[:type] || ev["type"]).to_s
          obj     = ev[:data]  || ev["data"]  || {}
          action  = (obj["action"] || "").to_s
          payload = obj["payload"] || {}
          next if ev_type == "err"

          case action
          when "GTS_SNAPSHOT"
            apply_snapshot(payload); dirty = true
          when "GTS_LIST"
            listing = payload["listing"] || payload
            if listing && listing["id"]
              add_or_replace_listing(listing)
              if @pending_list_action && @pending_list_action[:kind] == "pokemon"
                pj = @pending_list_action[:pokemon_json]
                @local_poke_cache[listing["id"].to_s] = deep_copy_hash(pj) if pj
              end
              apply_local_after_list_ok(listing)
              @rev = [payload["rev"].to_i, @rev].max if payload["rev"]
              toast("Listed!"); dirty = true
            end
          when "GTS_CANCEL"
            listing = payload["listing"] || payload
            lid = listing["id"] || payload["id"]
            if lid
              remove_listing_by_id(lid)
              apply_local_after_cancel_ok(listing)
              @rev = [payload["rev"].to_i, @rev].max if payload["rev"]
              toast("Cancelled"); dirty = true
            end
          when "GTS_BUY"
            listing = payload["listing"] || payload
            lid = listing["id"] || payload["id"]
            if lid
              remove_listing_by_id(lid)
              apply_local_after_buy_ok(listing)
              @rev = [payload["rev"].to_i, @rev].max if payload["rev"]
              toast("Purchased!"); dirty = true
            end
          when "GTS_WALLET_SNAPSHOT", "GTS_WALLET_CLAIM"
            dirty = true
          end
        end
      rescue; end
      redraw_all if dirty
    end

    def apply_snapshot(payload)
      begin
        new_rev = (payload["rev"] || @rev).to_i
        server_listings = payload["listings"].is_a?(Array) ? payload["listings"] : []
        return if new_rev < @rev
        return if server_listings.empty? && @listings.length > 0 && @rev > 0
        @rev = new_rev
        server_ids = server_listings.map { |l| l["id"].to_s }.compact
        @listings.delete_if { |l| !server_ids.include?(l["id"].to_s) }
        server_listings.each do |listing|
          next unless listing["id"]
          idx = @listings.index { |l| l["id"].to_s == listing["id"].to_s }
          idx ? (@listings[idx] = listing) : (@listings << listing)
        end
        @sel_index = 0 if @sel_index >= @listings.length
        apply_filter; redraw_all
      rescue; end
    end

    # Drain system-level toasts while GTS is open so they don't queue for the map
    def drain_system_toasts
      return unless MultiplayerClient.respond_to?(:toast_pending?)
      while MultiplayerClient.toast_pending?
        t = MultiplayerClient.dequeue_toast rescue nil
        next unless t
        msg = (t[:text] || t["text"]).to_s
        # Route GTS error/info toasts into our scene toast
        if msg.include?("GTS:")
          is_err = msg.include?("failed") || msg.include?("Error") || msg.include?("Invalid") ||
                   msg.include?("not available") || msg.include?("locked") || msg.include?("Bad")
          toast(msg.sub("GTS: ", ""), is_err)
        end
        # Silently discard non-GTS toasts (they'd just confuse things in-scene)
      end
    end

    def add_or_replace_listing(listing)
      return unless listing && listing["id"] && !listing["id"].to_s.empty?
      idx = @listings.index { |l| l["id"].to_s == listing["id"].to_s }
      idx ? (@listings[idx] = listing) : (@listings << listing)
      apply_filter; draw_left; draw_right
    end

    def remove_listing_by_id(id)
      @listings.delete_if { |l| l["id"].to_s == id.to_s }
      apply_filter; draw_left; draw_right
    end

    # ========================================================================
    # Local inventory mutations
    # ========================================================================
    def apply_local_after_list_ok(listing)
      # Item/pokemon already removed upfront in action_list_item/action_list_pokemon
      begin; GTSUI.autosave_safely; rescue; end
      @pending_list_action = nil
    end

    def apply_local_after_cancel_ok(listing)
      begin
        if listing["kind"].to_s == "item"
          GTSUI.bag_add(GTSUI.item_sym(listing["item_id"]), [listing["qty"].to_i, 1].max)
          GTSUI.autosave_safely; return
        end
        pj = listing["pokemon_json"] || @local_poke_cache[listing["id"].to_s]
        party_cnt = (defined?($Trainer) && $Trainer.respond_to?(:party_count)) ? $Trainer.party_count : (GTSUI.party_count rescue -1)
        if party_cnt >= 6
          toast("Could not restore Pokemon — party full!", true); return
        end
        ok = pj && GTSUI.add_pokemon_from_json(pj)
        if ok
          @local_poke_cache.delete(listing["id"].to_s); GTSUI.autosave_safely
        else
          toast("Could not restore Pokemon — party full!", true)
        end
      rescue; end
    end

    def apply_local_after_buy_ok(listing)
      begin; GTSUI.autosave_safely; rescue; end
    end

    # ========================================================================
    # Input
    # ========================================================================
    def handle_input
      handle_mouse

      if @search_active
        handle_search_input; return
      end

      if Input.trigger?(Input::B) || Input.trigger?(Input::MOUSERIGHT)
        if @focus == :footer
          @focus = :list; draw_left; draw_footer
        else
          @running = false
        end
        return
      end

      if _key_trigger?(0x53) # S
        activate_search; return
      end

      if _key_trigger?(0x09) # Tab
        idx = KIND_FILTERS.index(@kind_filter) || 0
        @kind_filter = KIND_FILTERS[(idx + 1) % KIND_FILTERS.length]
        @sel_index = 0; @scroll = 0; apply_filter; redraw_all; return
      end

      @focus == :list ? handle_list_input : handle_footer_input

      if Graphics.frame_count - @last_refresh_at > (Graphics.frame_rate * 5)
        begin; MultiplayerClient.gts_snapshot(@rev); rescue; end
        @last_refresh_at = Graphics.frame_count
      end
    end

    def handle_list_input
      changed = false
      if Input.repeat?(Input::UP) && @filtered.length > 0
        @sel_index = (@sel_index - 1) % @filtered.length; ensure_visible; changed = true
      elsif Input.repeat?(Input::DOWN) && @filtered.length > 0
        @sel_index = (@sel_index + 1) % @filtered.length; ensure_visible; changed = true
      end

      if Input.trigger?(Input::LEFT) || Input.trigger?(Input::RIGHT)
        @focus = :footer; draw_left; draw_footer; return
      end

      # Z/C = act on listing (submenu for pokemon, direct buy for items)
      if Input.trigger?(Input::C) && selected_listing
        act_on_listing(selected_listing); return
      end

      draw_left; draw_right if changed
    end

    def handle_footer_input
      btn_count = FOOTER_BUTTONS.length
      if Input.trigger?(Input::LEFT)
        @footer_index = (@footer_index - 1) % btn_count; draw_footer
      elsif Input.trigger?(Input::RIGHT)
        @footer_index = (@footer_index + 1) % btn_count; draw_footer
      elsif Input.trigger?(Input::UP)
        @focus = :list; draw_left; draw_footer
      elsif Input.trigger?(Input::C)
        execute_footer_action(@footer_index)
      end
    end

    def execute_footer_action(idx)
      case idx
      when 0 then action_list_item
      when 1 then action_list_pokemon
      when 2
        begin; MultiplayerClient.gts_snapshot(@rev); rescue; end
        @last_refresh_at = Graphics.frame_count
      when 3 then @running = false
      end
    end

    # ========================================================================
    # Search
    # ========================================================================
    def activate_search
      @search_active = true; @cursor_frame = 0; @focus = :list; draw_left
    end

    def deactivate_search
      @search_active = false; @search_text = ""
      @sel_index = 0; @scroll = 0; apply_filter; redraw_all
    end

    def handle_search_input
      if Input.trigger?(Input::B) || _key_trigger?(0x0D) || Input.trigger?(Input::MOUSERIGHT)
        deactivate_search; return
      end
      old = @search_text
      @search_text = @search_text[0...-1] if _key_repeat?(0x08) && !@search_text.empty?
      @search_text = "" if _key_trigger?(0x2E)
      (0x41..0x5A).each { |vk| @search_text += (_key_pressed?(0x10) ? (vk-0x41+65).chr : (vk-0x41+97).chr) if _key_trigger?(vk) && @search_text.length < 30 }
      (0x30..0x39).each { |vk| @search_text += (vk-0x30).to_s if _key_trigger?(vk) && @search_text.length < 30 }
      @search_text += " " if _key_trigger?(0x20) && @search_text.length < 30
      @search_text += (_key_pressed?(0x10) ? "_" : "-") if _key_trigger?(0xBD) && @search_text.length < 30
      if @search_text != old
        @sel_index = 0; @scroll = 0; apply_filter; draw_title; draw_left; draw_right
      end
    end

    # ========================================================================
    # Mouse
    # ========================================================================
    def handle_mouse
      mx = Input.mouse_x rescue nil; my = Input.mouse_y rescue nil
      return unless mx && my
      clicked = Input.trigger?(Input::MOUSELEFT) rescue false
      old_sel = @sel_index; old_focus = @focus; old_footer = @footer_index
      lx = @left_spr.x; ly = @left_spr.y

      # Filter bar
      if clicked && mx >= lx && mx < lx + LEFT_W
        fy = ly + SEARCH_H + 2
        if my >= fy && my < fy + FILTER_H
          btn_w = (LEFT_W - 12) / 3
          bi = ((mx - lx - 6) / btn_w).floor.clamp(0, 2)
          @kind_filter = KIND_FILTERS[bi]
          @sel_index = 0; @scroll = 0; apply_filter; redraw_all; return
        end
      end

      # Search bar
      if clicked && mx >= lx && mx < lx + LEFT_W && my >= ly && my < ly + SEARCH_H
        activate_search unless @search_active; return
      end
      if clicked && @search_active
        unless mx >= lx && mx < lx + LEFT_W && my >= ly && my < ly + SEARCH_H
          deactivate_search
        end
      end

      # Scroll arrows — hover to scroll (generous hit zones)
      rpp = rows_per_page
      arrow_h = ROW_H
      up_y = ly + LIST_Y - arrow_h
      dn_y = ly + LIST_Y + (rpp - 1) * ROW_H
      @_scroll_timer ||= 0
      if mx >= lx && mx < lx + LEFT_W
        if my >= up_y && my < up_y + arrow_h && @scroll > 0
          @_scroll_timer += 1
          if @_scroll_timer >= 6  # slight delay before scrolling
            @scroll -= 1; @sel_index = [@sel_index, @scroll].max
            @_scroll_timer = 4
            draw_left; draw_right
          end
          return
        elsif my >= dn_y && my < dn_y + arrow_h && @scroll + rpp < @filtered.length
          @_scroll_timer += 1
          if @_scroll_timer >= 6
            @scroll += 1; @sel_index = [@sel_index, @scroll].min if @sel_index < @scroll
            @_scroll_timer = 4
            draw_left; draw_right
          end
          return
        else
          @_scroll_timer = 0
        end
      else
        @_scroll_timer = 0
      end

      # List rows
      if mx >= lx && mx < lx + LEFT_W && my >= ly + LIST_Y && my < ly + LIST_Y + LIST_H
        row = ((my - ly - LIST_Y) / ROW_H).floor
        ri = @scroll + row
        if ri >= 0 && ri < @filtered.length
          @focus = :list; @sel_index = ri
          if clicked
            act_on_listing(selected_listing) if selected_listing; return
          end
        end
      end

      # Footer
      if my >= @footer_spr.y && my < @footer_spr.y + FOOTER_H
        btn_w = SCREEN_W / FOOTER_BUTTONS.length
        bi = (mx / btn_w).floor.clamp(0, FOOTER_BUTTONS.length - 1)
        @focus = :footer; @footer_index = bi
        if clicked
          execute_footer_action(@footer_index); return
        end
      end

      if @sel_index != old_sel || @focus != old_focus || @footer_index != old_footer
        draw_left if @sel_index != old_sel || @focus != old_focus
        draw_right if @sel_index != old_sel
        draw_footer if @focus != old_focus || @footer_index != old_footer
      end
    end

    # ========================================================================
    # Actions
    # ========================================================================
    def act_on_listing(entry)
      if is_mine?(entry)
        # Own listing — cancel submenu
        items = [{label: "Cancel Listing"}, {label: "Back"}]
        choice = overlay_select("Your Listing", items, 1)
        if choice == 0
          if entry["kind"].to_s == "pokemon" && GTSUI.party_count >= 6
            toast("Can't cancel — party is full!", true); return
          end
          if entry["kind"].to_s == "item"
            sym = GTSUI.item_sym(entry["item_id"])
            unless GTSUI.bag_can_add?(sym, entry["qty"].to_i)
              toast("Can't cancel — bag is full!", true); return
            end
          end
          begin
            MultiplayerClient.gts_cancel(entry["id"].to_s)
          rescue => e
            toast("Cancel failed: #{e.message}", true)
          end
        end
        return
      end

      # Someone else's listing
      if entry["kind"].to_s == "pokemon"
        items = [{label: "Buy"}, {label: "Inspect"}, {label: "Back"}]
        choice = overlay_select(listing_name(entry), items, 2)
        case choice
        when 0 then do_buy_listing(entry)
        when 1
          show_pokemon_info(entry["pokemon_json"]); redraw_all
        end
      else
        items = [{label: "Buy"}, {label: "Back"}]
        choice = overlay_select(listing_name(entry), items, 1)
        do_buy_listing(entry) if choice == 0
      end
    end

    def do_buy_listing(entry)
      price = entry["price"].to_i
      unless GTSUI.has_money?(price)
        toast("Not enough Platinum!", true); return
      end
      items = [{label: "Yes, buy for #{GTSUI.commify(price)} Pt"}, {label: "No"}]
      choice = overlay_select("Confirm Purchase?", items, 1)
      if choice == 0
        begin
          MultiplayerClient.gts_buy(entry["id"].to_s)
        rescue => e
          toast("Buy failed: #{e.message}", true)
        end
      end
    end

    # ========================================================================
    # Overlay — Number Input (keyboard typing + mouse presets)
    # ========================================================================
    # Themed popup for entering a number. Supports:
    #   - Direct keyboard digit entry (like chat)
    #   - Backspace to delete, Delete to clear
    #   - Clickable preset buttons
    #   - Clickable Confirm / Cancel
    #   - Enter to confirm, Escape to cancel
    # Returns integer or nil if cancelled.
    def overlay_number_input(title, max, default_val = 0, presets: nil, show_plat: false)
      max = [max.to_i, 1].max
      default_val = [[default_val.to_i, 0].max, max].min

      # Default presets based on max value
      presets ||= if max <= 100
        [1, 5, 10, 25, 50, max]
      elsif max <= 1000
        [1, 10, 50, 100, 500, max]
      else
        [100, 500, 1000, 5000, 10000, 50000].select { |v| v <= max }
      end
      presets = presets.select { |v| v > 0 && v <= max }.uniq

      # Layout
      box_w = 320; box_h = 180
      box_x = (SCREEN_W - box_w) / 2
      box_y = (SCREEN_H - box_h) / 2
      input_y = 50     # input field y (relative to box)
      input_h = 32
      preset_y = 96    # preset row y
      preset_h = 22
      btn_y = box_h - 36  # confirm/cancel row y
      btn_h = 26
      btn_w = 100

      # Sprites
      dim = Sprite.new(@vp)
      dim.bitmap = Bitmap.new(SCREEN_W, SCREEN_H)
      dim.bitmap.fill_rect(0, 0, SCREEN_W, SCREEN_H, Color.new(0, 0, 0, 140))
      dim.z = 800

      box = Sprite.new(@vp)
      box.bitmap = Bitmap.new(box_w, box_h)
      box.x = box_x; box.y = box_y; box.z = 801

      text_str = default_val > 0 ? default_val.to_s : ""
      cursor_frame = 0
      result = nil
      hovered_preset = -1
      hovered_btn = -1  # 0=confirm, 1=cancel

      # Preset button rects (screen space)
      preset_rects = []
      unless presets.empty?
        pw = [(box_w - 16) / presets.length, 60].min
        total_pw = pw * presets.length
        start_px = (box_w - total_pw) / 2
        presets.each_with_index do |_v, i|
          px = start_px + i * pw
          preset_rects << { x: box_x + px, y: box_y + preset_y, w: pw - 4, h: preset_h }
        end
      end

      # Button rects (screen space)
      confirm_rect = { x: box_x + box_w / 2 - btn_w - 8, y: box_y + btn_y, w: btn_w, h: btn_h }
      cancel_rect  = { x: box_x + box_w / 2 + 8, y: box_y + btn_y, w: btn_w, h: btn_h }

      redraw = lambda do
        bmp = box.bitmap; bmp.clear
        draw_rounded_rect(bmp, 0, 0, box_w, box_h, OVL_BG)
        draw_border(bmp, 0, 0, box_w, box_h, OVL_BD)

        # Title
        pbSetSystemFont(bmp)
        bmp.font.size = 16
        pbDrawShadowText(bmp, 0, 8, box_w, 22, title.to_s, WHITE, SHADOW, 2)

        # Subtitle (max)
        bmp.font.size = 12
        pbDrawShadowText(bmp, 0, 28, box_w, 16, "Max: #{GTSUI.commify(max)}", DIM, SHADOW, 2)

        # Input field
        ix = 24; iw = box_w - 48
        draw_rounded_rect(bmp, ix, input_y, iw, input_h, SEARCH_BG)
        draw_border(bmp, ix, input_y, iw, input_h, Color.new(140, 120, 200))

        # Number text with cursor
        cursor = (cursor_frame / 20) % 2 == 0 ? "|" : ""
        display = text_str.empty? ? "" : GTSUI.commify(text_str.to_i)
        bmp.font.size = 22
        bmp.font.bold = true

        if show_plat
          # Measure text to center icon + number together
          tw = bmp.text_size(display + cursor).width
          icon_sz = 18
          total_cw = icon_sz + 6 + tw
          cx = (box_w - total_cw) / 2
          draw_plat_icon(bmp, cx, input_y + (input_h - icon_sz) / 2, icon_sz)
          pbDrawShadowText(bmp, cx + icon_sz + 6, input_y, tw + 12, input_h, display + cursor, PLAT_COLOR, SHADOW)
        else
          pbDrawShadowText(bmp, ix, input_y, iw, input_h, display + cursor, WHITE, SHADOW, 2)
        end
        bmp.font.bold = false

        # Placeholder
        if text_str.empty?
          bmp.font.size = 14
          pbDrawShadowText(bmp, ix, input_y + input_h - 16, iw, 14, "Type a number...", DIM, SHADOW, 2)
        end

        # Validation warning
        val = text_str.empty? ? 0 : text_str.to_i
        if val > max
          bmp.font.size = 12
          pbDrawShadowText(bmp, 0, input_y + input_h + 2, box_w, 14, "Exceeds maximum!", RED, SHADOW, 2)
        elsif val == 0 && !text_str.empty?
          bmp.font.size = 12
          pbDrawShadowText(bmp, 0, input_y + input_h + 2, box_w, 14, "Must be at least 1", RED, SHADOW, 2)
        end

        # Preset buttons
        bmp.font.size = 12; bmp.font.bold = false
        presets.each_with_index do |pv, i|
          r = preset_rects[i]
          rx = r[:x] - box_x; ry = r[:y] - box_y
          bg_color = (hovered_preset == i) ? OVL_SEL : MOVE_CELL_BG
          draw_rounded_rect(bmp, rx, ry, r[:w], r[:h], bg_color)
          draw_border(bmp, rx, ry, r[:w], r[:h], MOVE_CELL_BD)
          label = pv >= 1000 ? "#{pv / 1000}K" : pv.to_s
          pbDrawShadowText(bmp, rx, ry, r[:w], r[:h], label, GRAY, SHADOW, 2)
        end

        # Confirm / Cancel buttons
        confirm_bg = (hovered_btn == 0) ? Color.new(60, 120, 80) : Color.new(40, 90, 60)
        cancel_bg  = (hovered_btn == 1) ? Color.new(120, 50, 50) : Color.new(90, 40, 40)
        # Confirm
        crx = confirm_rect[:x] - box_x; cry = confirm_rect[:y] - box_y
        draw_rounded_rect(bmp, crx, cry, btn_w, btn_h, confirm_bg)
        draw_border(bmp, crx, cry, btn_w, btn_h, Color.new(100, 180, 120))
        bmp.font.size = 14
        pbDrawShadowText(bmp, crx, cry, btn_w, btn_h, "Confirm", WHITE, SHADOW, 2)
        # Cancel
        cax = cancel_rect[:x] - box_x; cay = cancel_rect[:y] - box_y
        draw_rounded_rect(bmp, cax, cay, btn_w, btn_h, cancel_bg)
        draw_border(bmp, cax, cay, btn_w, btn_h, Color.new(180, 100, 100))
        bmp.font.size = 14
        pbDrawShadowText(bmp, cax, cay, btn_w, btn_h, "Cancel", WHITE, SHADOW, 2)
      end

      redraw.call

      loop do
        Graphics.update; Input.update
        cursor_frame += 1
        changed = false

        # Escape / right-click = cancel
        if Input.trigger?(Input::B) || Input.trigger?(Input::MOUSERIGHT)
          result = nil; break
        end

        # Enter = confirm
        if _key_trigger?(0x0D)  # VK_RETURN
          val = text_str.to_i
          if val > 0 && val <= max
            result = val; break
          end
          # Flash red if invalid — just continue
          next
        end

        # Keyboard digit input (0-9)
        (0x30..0x39).each do |vk|
          if _key_trigger?(vk)
            digit = (vk - 0x30).to_s
            new_str = text_str + digit
            # Don't allow leading zeros
            new_str = new_str.to_i.to_s if new_str.length > 1
            if new_str.to_i <= max
              text_str = new_str
              changed = true
            end
          end
        end
        # Numpad (0-9)
        (0x60..0x69).each do |vk|
          if _key_trigger?(vk)
            digit = (vk - 0x60).to_s
            new_str = text_str + digit
            new_str = new_str.to_i.to_s if new_str.length > 1
            if new_str.to_i <= max
              text_str = new_str
              changed = true
            end
          end
        end

        # Backspace
        if _key_repeat?(0x08) && !text_str.empty?
          text_str = text_str[0...-1]
          changed = true
        end

        # Delete = clear
        if _key_trigger?(0x2E)
          text_str = ""
          changed = true
        end

        # Mouse hover
        old_hp = hovered_preset; old_hb = hovered_btn
        hovered_preset = -1; hovered_btn = -1
        begin
          mx = Input.mouse_x; my = Input.mouse_y
          if mx && my
            preset_rects.each_with_index do |r, i|
              if mx >= r[:x] && mx < r[:x] + r[:w] && my >= r[:y] && my < r[:y] + r[:h]
                hovered_preset = i; break
              end
            end
            if mx >= confirm_rect[:x] && mx < confirm_rect[:x] + confirm_rect[:w] &&
               my >= confirm_rect[:y] && my < confirm_rect[:y] + confirm_rect[:h]
              hovered_btn = 0
            elsif mx >= cancel_rect[:x] && mx < cancel_rect[:x] + cancel_rect[:w] &&
                  my >= cancel_rect[:y] && my < cancel_rect[:y] + cancel_rect[:h]
              hovered_btn = 1
            end
          end
        rescue; end
        changed = true if hovered_preset != old_hp || hovered_btn != old_hb

        # Mouse click
        if Input.trigger?(Input::MOUSELEFT)
          begin
            mx = Input.mouse_x; my = Input.mouse_y
            if mx && my
              # Preset click
              preset_rects.each_with_index do |r, i|
                if mx >= r[:x] && mx < r[:x] + r[:w] && my >= r[:y] && my < r[:y] + r[:h]
                  text_str = presets[i].to_s
                  changed = true; break
                end
              end
              # Confirm click
              if mx >= confirm_rect[:x] && mx < confirm_rect[:x] + confirm_rect[:w] &&
                 my >= confirm_rect[:y] && my < confirm_rect[:y] + confirm_rect[:h]
                val = text_str.to_i
                if val > 0 && val <= max
                  result = val; break
                end
              end
              # Cancel click
              if mx >= cancel_rect[:x] && mx < cancel_rect[:x] + cancel_rect[:w] &&
                 my >= cancel_rect[:y] && my < cancel_rect[:y] + cancel_rect[:h]
                result = nil; break
              end
              # Click outside box = cancel
              unless mx >= box_x && mx < box_x + box_w && my >= box_y && my < box_y + box_h
                result = nil; break
              end
            end
          rescue; end
        end

        # Redraw on change or cursor blink
        redraw.call if changed || cursor_frame % 20 == 0
      end

      box.bitmap.dispose rescue nil; box.dispose rescue nil
      dim.bitmap.dispose rescue nil; dim.dispose rescue nil
      result
    end

    # ---------- List Item (custom overlay) ----------
    def action_list_item
      list = GTSUI.bag_item_list
      if list.empty?
        toast("No items available for listing.", true); return
      end
      items = list.map { |sym, q| {label: "#{GTSUI.item_name(sym)} x#{q}", icon_sym: sym} }
      items << {label: "Cancel"}
      sel = overlay_select("Pick an Item", items, items.length - 1)
      return if sel < 0 || sel >= list.length

      sym, have = list[sel]
      max_q = [have.to_i, 999].min
      qty = overlay_number_input("Quantity", max_q, 1,
              presets: [1, 5, 10, 25, 50, [99, max_q].min].select { |v| v <= max_q }.uniq)
      return if !qty || qty <= 0
      price = overlay_number_input("Set Price (Platinum)", 999_999, 100,
                presets: [100, 500, 1000, 5000, 10000, 50000], show_plat: true)
      return if !price || price <= 0
      # Remove from bag immediately to prevent duplication
      GTSUI.bag_remove(sym, qty)
      begin
        @pending_list_action = { kind: "item", item_sym: sym, qty: qty, price: price }
        MultiplayerClient.gts_list_item(sym.to_s, qty, price)
      rescue => e
        @pending_list_action = nil
        GTSUI.bag_add(sym, qty)  # restore on failure
        toast("List failed: #{e.message}", true)
      end
    end

    # ---------- List Pokemon (custom overlay) ----------
    def action_list_pokemon
      party = GTSUI.party
      if party.length <= 1
        toast("You must keep at least one Pokemon!", true); return
      end
      items = party.each_with_index.map do |pk, i|
        species = pk.species rescue nil
        label = (pk.respond_to?(:name) && pk.respond_to?(:level)) ? "#{pk.name}  Lv.#{pk.level}" : "Slot #{i + 1}"
        is_fusion = (pk.respond_to?(:isFusion?) && pk.isFusion?) rescue false
        if is_fusion
          {label: label, icon_pokemon: pk}
        else
          params = nil
          begin
            params = [pk.species, pk.gender, pk.form, pk.shiny?]
          rescue; end
          {label: label, icon_species: species, icon_params: params}
        end
      end
      items << {label: "Cancel"}
      sel = overlay_select("Pick a Pokemon", items, items.length - 1)
      return if sel < 0 || sel >= party.length

      if party.length <= 1
        toast("You must keep at least one Pokemon!", true); return
      end
      pk = party[sel]
      pj = nil
      begin
        pj = pk.to_json
        TradeUI.ensure_complete_stat_maps!(pj) if defined?(TradeUI)
      rescue
        toast("This Pokemon cannot be serialized.", true); return
      end
      price = overlay_number_input("Set Price (Platinum)", 999_999, 1000,
                presets: [100, 500, 1000, 5000, 10000, 50000], show_plat: true)
      return if !price || price <= 0
      # Remove from party immediately to prevent duplication
      GTSUI.remove_pokemon_at(sel)
      begin
        @pending_list_action = { kind: "pokemon", party_index: sel, price: price, pokemon_json: pj }
        MultiplayerClient.gts_list_pokemon(pj, price)
      rescue => e
        @pending_list_action = nil
        GTSUI.add_pokemon_from_json(pj)  # restore on failure
        toast("List failed: #{e.message}", true)
      end
    end

    # ========================================================================
    # Pokemon helpers
    # ========================================================================
    def build_temp_pokemon_from_json(pj)
      return nil unless pj && defined?(Pokemon)
      begin
        TradeUI.ensure_complete_stat_maps!(pj) if defined?(TradeUI) && TradeUI.respond_to?(:ensure_complete_stat_maps!)
        sid = GTSUI.resolve_species_id(pj["species"])
        p = Pokemon.new(sid, [(pj["level"] || 1).to_i, 1].max)
        p.load_json(pj)
        TradeUI.force_species_id!(p) if defined?(TradeUI) && TradeUI.respond_to?(:force_species_id!)
        return p
      rescue; return nil; end
    end

    def show_pokemon_info(pj)
      p = build_temp_pokemon_from_json(pj)
      unless p
        toast("Can't show info for this Pokemon.", true); return
      end
      begin
        if defined?(PokemonSummary_Scene) && defined?(PokemonSummaryScreen)
          @vp.visible = false
          pbFadeOutIn {
            scene = PokemonSummary_Scene.new
            screen = PokemonSummaryScreen.new(scene)
            screen.pbStartScreen([p], 0)
          }
          @vp.visible = true
        else
          toast("#{p.name} Lv.#{p.level} — #{p.nature.name} / #{p.ability.name}")
        end
      rescue
        @vp.visible = true
        @vp.visible = true
        toast("Error opening summary.", true)
      end
    end

    def get_nature_str(pkm, pj)
      begin
        return pkm.nature.name.to_s if pkm && pkm.respond_to?(:nature) && pkm.nature
        raw = pj["nature"] || pj["nature_for_stats"]
        return GameData::Nature.get(raw).name.to_s if defined?(GameData::Nature) && raw
      rescue; end; "-"
    end

    def get_ability_str(pkm, pj)
      begin
        return pkm.ability.name.to_s if pkm && pkm.respond_to?(:ability) && pkm.ability
        raw = pj["ability"] || pj["ability_index"]
        return GameData::Ability.get(raw).name.to_s if defined?(GameData::Ability) && raw
      rescue; end; "-"
    end

    def get_move_names(pkm, pj)
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
      rescue; end; names
    end

    def get_move_ids(pkm, pj)
      ids = []
      begin
        if pkm && pkm.respond_to?(:moves)
          ids = pkm.moves.map { |m| (m.id rescue nil) }.compact
        else
          arr = pj["moves"]
          if arr.is_a?(Array)
            ids = arr.map { |m|
              m.is_a?(Hash) ? (m["id"] || m["move"]) : m
            }.compact
          end
        end
      rescue; end
      ids
    end

    # ========================================================================
    # Move Tooltip (hover over move cells)
    # ========================================================================
    def update_move_tooltip
      return unless @move_tooltip && @move_rects.length > 0
      mx = (Input.mouse_x rescue nil); my = (Input.mouse_y rescue nil)
      unless mx && my
        hide_move_tooltip; return
      end

      hovered = nil
      @move_rects.each_with_index do |r, i|
        if mx >= r[:x] && mx < r[:x] + r[:w] && my >= r[:y] && my < r[:y] + r[:h]
          hovered = i; break
        end
      end

      if hovered.nil? || !@move_ids[hovered]
        hide_move_tooltip; return
      end
      return if @hovered_move == hovered  # already showing
      @hovered_move = hovered
      draw_move_tooltip(hovered)
    end

    def hide_move_tooltip
      return unless @move_tooltip
      @move_tooltip.visible = false
      @hovered_move = nil
    end

    def draw_move_tooltip(idx)
      mid = @move_ids[idx]
      return hide_move_tooltip unless mid
      begin
        md = GameData::Move.get(mid)
      rescue
        hide_move_tooltip; return
      end

      tw = 220; th = 110
      b = @move_tooltip.bitmap; b.clear
      draw_rounded_rect(b, 0, 0, tw, th, OVL_BG)
      draw_border(b, 0, 0, tw, th, OVL_BD)

      pbSetSmallFont(b)
      # Move name
      b.font.size = 14
      pbDrawShadowText(b, 6, 2, tw - TYPE_DRAW_W - 14, 16, md.name.to_s, WHITE, SHADOW)
      # Type icon
      draw_type_icon(b, md.type, tw - TYPE_DRAW_W - 6, 2)

      # Category | Power | Accuracy
      cat = case md.category
            when 0 then "Physical"
            when 1 then "Special"
            else "Status"
            end
      pow = (md.base_damage.to_i > 0) ? md.base_damage.to_s : "—"
      acc = (md.accuracy.to_i > 0) ? md.accuracy.to_s : "—"
      b.font.size = 13
      pbDrawShadowText(b, 6, 22, -1, 14, "#{cat}  |  Pow: #{pow}  |  Acc: #{acc}", GRAY, SHADOW)

      # Separator
      b.fill_rect(6, 40, tw - 12, 1, SECTION_LINE)

      # Description (word-wrapped, native font size)
      desc = (md.description.to_s rescue "")
      y = 44
      b.font.size = 13
      word_wrap(b, desc, tw - 14).each do |line|
        break if y + 14 > th - 4
        pbDrawShadowText(b, 6, y, tw - 12, 14, line, DIM, SHADOW)
        y += 14
      end

      # Position tooltip near the hovered cell
      r = @move_rects[idx]
      tx = r[:x]
      ty = r[:y] + r[:h] + 4
      tx = [tx, SCREEN_W - tw - 2].min
      ty = [ty, 0].max
      # If tooltip would go below footer, place above the cell
      if ty + th > SCREEN_H - FOOTER_H - 2
        ty = r[:y] - th - 4
        ty = [ty, 0].max
      end

      @move_tooltip.x = tx; @move_tooltip.y = ty
      @move_tooltip.visible = true
    end

    def get_stat_maps(pkm, pj)
      iv = nil; ev = nil
      begin
        if pkm && pkm.respond_to?(:iv) && pkm.respond_to?(:ev)
          iv = pkm.iv; ev = pkm.ev
        else
          piv = pj["iv"]; pev = pj["ev"]
          if piv.is_a?(Hash); iv = {}; piv.each { |k, v| iv[k.to_s.upcase.to_sym] = v.to_i }; end
          if pev.is_a?(Hash); ev = {}; pev.each { |k, v| ev[k.to_s.upcase.to_sym] = v.to_i }; end
        end
      rescue; end; [iv, ev]
    end

    def shiny_label_from(pj)
      pj ||= {}
      is_shiny = !!(pj["shiny"] || pj[:shiny] || pj["head_shiny"] || pj[:head_shiny] ||
                     pj["body_shiny"] || pj[:body_shiny] || pj["natural_shiny"] || pj[:natural_shiny] ||
                     pj["fakeshiny"] || pj[:fakeshiny] || pj["debug_shiny"] || pj[:debug_shiny])
      return "No" unless is_shiny
      return "Fake" if pj["fakeshiny"] || pj[:fakeshiny]
      return "Natural" if pj["natural_shiny"] || pj[:natural_shiny]
      return "Debug" if pj["head_shiny"] || pj[:head_shiny] || pj["body_shiny"] || pj[:body_shiny] || pj["debug_shiny"] || pj[:debug_shiny]
      "Natural"
    end

    def item_description(item_id)
      begin
        return GameData::Item.get(GTSUI.item_sym(item_id)).description.to_s if defined?(GameData::Item)
      rescue; end; ""
    end

    # ========================================================================
    # Toasts
    # ========================================================================
    def toast(msg, is_error = false); @toast_queue << { text: msg, error: is_error }; end

    def process_toasts
      if @toast_timer > 0
        @toast_timer -= 1
        @toast_spr.visible = false if @toast_timer <= 0
        return
      end
      return if @toast_queue.empty?
      t = @toast_queue.shift
      b = @toast_spr.bitmap; b.clear
      b.fill_rect(0, 0, SCREEN_W, 22, t[:error] ? Color.new(120, 30, 30, 220) : Color.new(30, 80, 50, 220))
      pbSetSmallFont(b)
      pbDrawShadowText(b, 0, -1, SCREEN_W, 22, t[:text], WHITE, SHADOW, 2)
      @toast_spr.visible = true; @toast_timer = 120
    end

    # ========================================================================
    # Sprite management
    # ========================================================================
    def clear_row_icons
      @list_icons.each { |s| s.dispose rescue nil }; @list_icons.clear
    end

    def clear_detail_icons
      @detail_icons.each { |s| s.dispose rescue nil }; @detail_icons.clear
    end

    def redraw_all; draw_title; draw_left; draw_right; draw_footer; end

    # ========================================================================
    # Text / Drawing helpers
    # ========================================================================
    def word_wrap(bmp, text, max_w)
      lines = []; current = ""
      text.split(" ").each do |word|
        test = current.empty? ? word : "#{current} #{word}"
        if bmp.text_size(test).width > max_w
          lines << current unless current.empty?; current = word
        else
          current = test
        end
      end
      lines << current unless current.empty?; lines
    end

    def deep_copy_hash(h)
      return nil unless h.is_a?(Hash)
      defined?(MiniJSON) ? MiniJSON.parse(MiniJSON.dump(h)) : deep_copy_recursive(h)
    rescue; deep_copy_recursive(h); end

    def deep_copy_recursive(obj)
      case obj
      when Hash then out = {}; obj.each { |k, v| out[k] = deep_copy_recursive(v) }; out
      when Array then obj.map { |e| deep_copy_recursive(e) }
      else obj; end
    end

    def draw_rounded_rect(bmp, x, y, w, h, color)
      bmp.fill_rect(x + 2, y, w - 4, h, color)
      bmp.fill_rect(x, y + 2, w, h - 4, color)
      bmp.fill_rect(x + 1, y + 1, w - 2, h - 2, color)
    end

    def draw_border(bmp, x, y, w, h, color)
      bmp.fill_rect(x + 2, y, w - 4, 1, color)
      bmp.fill_rect(x + 2, y + h - 1, w - 4, 1, color)
      bmp.fill_rect(x, y + 2, 1, h - 4, color)
      bmp.fill_rect(x + w - 1, y + 2, 1, h - 4, color)
    end

    # ========================================================================
    # Win32API key helpers
    # ========================================================================
    def _init_gas
      @_gas ||= Win32API.new('user32', 'GetAsyncKeyState', ['i'], 'i') rescue nil
    end

    def _window_active?
      @_gfw ||= Win32API.new('user32', 'GetForegroundWindow', [], 'l') rescue nil
      @_gwtpi ||= Win32API.new('user32', 'GetWindowThreadProcessId', ['l', 'p'], 'l') rescue nil
      return true unless @_gfw && @_gwtpi
      hwnd = @_gfw.call; pid_buf = "\0" * 4; @_gwtpi.call(hwnd, pid_buf)
      pid_buf.unpack('L')[0] == Process.pid
    rescue; true; end

    def _key_trigger?(vk)
      _init_gas; return false unless @_gas && _window_active?
      (@_gas.call(vk) & 0x01) != 0
    rescue; false; end

    def _key_pressed?(vk)
      _init_gas; return false unless @_gas && _window_active?
      (@_gas.call(vk) & 0x8000) != 0
    rescue; false; end

    def _key_repeat?(vk)
      @_repeat_timers ||= {}
      if _key_pressed?(vk)
        @_repeat_timers[vk] = (@_repeat_timers[vk] || 0) + 1
        t = @_repeat_timers[vk]
        return t == 1 || (t > 12 && t % 4 == 0)
      else
        @_repeat_timers[vk] = 0; false
      end
    end

    def _mouse_scroll; 0; end
  end

  # ============================================================================
  # Public open helper
  # ============================================================================
  def self.open
    unless MultiplayerClient && MultiplayerClient.instance_variable_get(:@connected)
      pbMessage(_INTL("You are not connected to any server.")); return
    end
    Scene_GTS.new.main
  end

  def self.tick_open_shortcut
    begin
      return unless defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:players)
      return unless MultiplayerClient.session_id
      GTSUI.open if defined?(Input::F6) && Input.trigger?(Input::F6)
    rescue; end
  end

  def self.tick_gts_events_only; end
end


# ---------- Hook Scene_Map update ----------
if defined?(Scene_Map)
  class ::Scene_Map
    alias kif_gts_update update unless method_defined?(:kif_gts_update)
    def update
      kif_gts_update
      GTSUI.tick_open_shortcut
      GTSUI.tick_gts_events_only
    end
  end
end
