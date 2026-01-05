# ===========================================
# File: 012_UI_Trade.rb
# Purpose: Trade UI + Scene hooks
# ===========================================

##MultiplayerDebug.info("UI-TRADE", "Trade UI loading...")

module TradeUI
  MAX_ITEM_SLOTS = 4

  # ---------- Mini helpers ----------
  def selfpbConfirm(prompt)
    if defined?(pbConfirmMessage)
      return pbConfirmMessage(prompt)
    end
    ret = pbMessage(prompt, [_INTL("Yes"), _INTL("No")], 0)
    ret == 0
  end
  module_function :selfpbConfirm

  # Block all key items except Shiny Charm
  def self.tradeable_item?(id)
    sym = item_sym(id)
    return false if sym.nil?

    # Allow Shiny Charm specifically
    sid = sym.to_s.downcase
    return true if sid.include?("shinycharm") || sid.include?("shiny_charm")

    # Block all other key items
    if defined?(GameData::Item)
      begin
        item_data = GameData::Item.get(sym)
        return false if item_data.is_key_item?
      rescue; end
    end

    # Block debug items
    return false if sid == "debugger" || sid.include?("debug")

    true
  end

  # ===== Compact numeric input popup =====
  # LEFT/RIGHT: ±1 | UP/DOWN: ±10 | L/R: ±100 | PgUp/PgDn: ±1000
  def self.small_number_popup(caption, max, default_val)
    max = [max.to_i, 0].max
    val = [[default_val.to_i, 0].max, max].min

    vp = Viewport.new(0, 0, Graphics.width, Graphics.height); vp.z = 100_000
    box_w = 360; box_h = 140
    x = (Graphics.width - box_w) / 2
    y = (Graphics.height - box_h) / 2

    bg  = Sprite.new(vp)
    bg.bitmap = Bitmap.new(box_w, box_h)
    bmp = bg.bitmap

    draw = lambda do
      bmp.clear
      bmp.fill_rect(0, 0, box_w, box_h, Color.new(0, 0, 0, 192))
      bmp.font.size = 20; bmp.font.color = Color.new(255,255,255)
      bmp.draw_text(8, 6, box_w - 16, 24, caption.to_s, 1)
      bmp.font.size = 34
      bmp.draw_text(8, 44, box_w - 16, 36, val.to_s, 1)
      bmp.font.size = 16
      bmp.draw_text(8, box_h - 46, box_w - 16, 18, _INTL("←/→ ±1   ↑/↓ ±10   L/R ±100"), 1)
      bmp.draw_text(8, box_h - 24, box_w - 16, 18, _INTL("PgUp/PgDn ±1000   OK/BACK"), 1)
    end
    bg.x = x; bg.y = y
    draw.call

    loop do
      Graphics.update; Input.update
      delta = 0
      delta -= 1    if Input.repeat?(Input::LEFT)
      delta += 1    if Input.repeat?(Input::RIGHT)
      delta += 10   if Input.repeat?(Input::UP)
      delta -= 10   if Input.repeat?(Input::DOWN)
      delta -= 100  if defined?(Input::L) && Input.repeat?(Input::L)
      delta += 100  if defined?(Input::R) && Input.repeat?(Input::R)
      delta += 1000 if defined?(Input::PAGEUP)   && Input.repeat?(Input::PAGEUP)
      delta -= 1000 if defined?(Input::PAGEDOWN) && Input.repeat?(Input::PAGEDOWN)
      if delta != 0
        val = [[val + delta, 0].max, max].min
        draw.call
      end
      if Input.trigger?(Input::USE) || Input.trigger?(Input::ACTION)
        break
      elsif Input.trigger?(Input::BACK) || (defined?(Input::B) && Input.trigger?(Input::B))
        val = nil; break
      end
    end

    bg.bitmap.dispose if bg&.bitmap && !bg.bitmap.disposed?
    bg.dispose if bg
    vp.dispose if vp
    return val
  end

  # Items: UI cap 999
  def self.pbInputNumber(caption, max = 9_999_999, default_val = 0)
    caption ||= _INTL("Choose how many you want to trade:")
    max_for_ui   = [[max.to_i, 0].max, 999].min
    default_val  = [[default_val.to_i, 0].max, max_for_ui].min
    if defined?(pbMessageChooseNumber)
      begin; return pbMessageChooseNumber(caption, max_for_ui, default_val); rescue; end
      begin; return pbMessageChooseNumber(caption, max_for_ui); rescue; end
    end
    if defined?(pbChooseNumber)
      begin; return pbChooseNumber(caption, max_for_ui); rescue; end
      begin; return pbChooseNumber(max_for_ui); rescue; end
    end
    small_number_popup(caption, max_for_ui, default_val)
  end

  # Money: UI cap 999_999
  def self.pbInputMoney(caption, max = 999_999, default_val = 0)
    caption ||= _INTL("Choose how many you want to trade:")
    max_for_ui   = [[max.to_i, 0].max, 999_999].min
    default_val  = [[default_val.to_i, 0].max, max_for_ui].min
    small_number_popup(caption, max_for_ui, default_val)
  end

  def self.item_sym(id)
    return nil if id.nil?
    return id if id.is_a?(Symbol)
    if defined?(GameData::Item)
      begin; return GameData::Item.get(id).id; rescue; end
      begin; return GameData::Item.get(id.to_s.to_sym).id; rescue; end
    end
    id.to_s.to_sym
  end

  # ---- JSON stat map normalization ----
  def self.normalize_stat_maps!(h)
    return unless h.is_a?(Hash) && defined?(GameData::Stat)
    %w[iv ev ivMaxed].each do |key|
      src = (h[key] || {}); dst = {}
      GameData::Stat.each_main do |s|
        sym = s.id; str = sym.to_s
        v = src.key?(sym) ? src[sym] : src[str]
        dst[sym] = (key == "ivMaxed") ? !!v : (v || 0).to_i
      end
      h[key] = dst
    end
  end

  def self.item_name(id)
    sym = item_sym(id)
    return (sym || id || "?").to_s unless defined?(GameData::Item)
    begin; GameData::Item.get(sym).name; rescue; (sym || id || "?").to_s; end
  end

  def self.party
    return [] unless defined?($Trainer) && $Trainer
    $Trainer.respond_to?(:party) ? ($Trainer.party || []) : []
  end

  def self.party_count; party.compact.length; end  # Count only non-nil Pokemon

  def self.remove_pokemon_at(idx)
    return false unless defined?($Trainer) && $Trainer && $Trainer.respond_to?(:party)
    arr = $Trainer.party; return false unless arr && arr[idx]
    arr.delete_at(idx); true
  end

  REQUIRED_KEYS = %w[
    json_version species form forced_form time_form_set exp level steps_to_hatch heal_status
    gender shiny fakeshiny kuraygender shinyValue veryunique kuraycustomfile oldkuraycustomfile
    shinyR shinyG shinyB shinyKRS ability_index ability ability2_index ability2 nature
    nature_for_stats item mail cool beauty cute smart tough sheen pokerus name happiness
    poke_ball markings iv ivMaxed ev hiddenPowerType glitter obtain_method obtain_map
    obtain_level obtain_text hatched_map timeReceived timeEggHatched fused personalID hp
    totalhp first_moves owner head_shiny body_shiny head_shinyhue head_shinyr head_shinyg
    head_shinyb body_shinyhue body_shinyr body_shinyg body_shinyb kuray_no_evo ribbons
    spriteform_body spriteform_head type1kuray type2kuray typeoverwrite sprite_scale
    size_category moves
  ]

  def self.validate_pokemon_payload!(h)
    missing = []; REQUIRED_KEYS.each { |k| missing << k unless h.key?(k) }
    bad = []
    if defined?(GameData::Stat)
      stat_ids = []; begin; GameData::Stat.each_main { |s| stat_ids << s.id }; rescue; stat_ids = [:HP,:ATTACK,:DEFENSE,:SPECIAL_ATTACK,:SPECIAL_DEFENSE,:SPEED]; end
      %w[iv ev ivMaxed].each do |key|
        val = h[key]
        if !val.is_a?(Hash); bad << "#{key}:not_hash"
        else
          stat_ids.each { |sid| bad << "#{key}:missing_#{sid}" unless val.key?(sid) || val.key?(sid.to_s) }
        end
      end
    else; bad << "stat_system_unavailable"; end
    if !h["moves"].is_a?(Array); bad << "moves:not_array"
    else; h["moves"].each_with_index { |mv,i| bad << "moves[#{i}]:no_id" unless mv.is_a?(Hash) && (mv.key?("id") || mv.key?(:id)) }; end
    bad << "owner:not_hash" unless h["owner"].is_a?(Hash)
    if !missing.empty? || !bad.empty?
      ##MultiplayerDebug.error("UI-TRADE-POKERECV","Invalid Pokémon payload. Missing: #{missing.join(', ')} | Bad: #{bad.join(', ')}")
      raise "TRADE_RECEIVE_BAD_POKEMON"
    end
  end

  def self.ensure_complete_stat_maps!(poke_hash)
    return unless poke_hash.is_a?(Hash)
    return unless defined?(GameData::Stat)
    stat_ids = []; begin; GameData::Stat.each_main { |s| stat_ids << s.id }; rescue; stat_ids = [:HP,:ATTACK,:DEFENSE,:SPECIAL_ATTACK,:SPECIAL_DEFENSE,:SPEED]; end
    poke_hash["iv"] ||= {}; poke_hash["ivMaxed"] ||= {}; poke_hash["ev"] ||= {}
    stat_ids.each do |sid|
      poke_hash["iv"][sid]      = (poke_hash["iv"][sid]      || poke_hash["iv"][sid.to_s]      || 0)
      poke_hash["ivMaxed"][sid] = (poke_hash["ivMaxed"][sid] || poke_hash["ivMaxed"][sid.to_s] || false)
      poke_hash["ev"][sid]      = (poke_hash["ev"][sid]      || poke_hash["ev"][sid.to_s]      || 0)
    end
  end

  def self.resolve_species_id(val)
    return nil if val.nil?
    begin; return GameData::Species.get(val).id; rescue; end
    return val.to_i if val.is_a?(String) && val.to_i.to_s == val
    return val if val.is_a?(Integer) || val.is_a?(Symbol)
    return val.to_s.to_sym
  end

  def self.force_species_id!(pokemon_obj)
    return unless pokemon_obj
    begin
      cur = pokemon_obj.instance_variable_get(:@species)
      coerced = resolve_species_id(cur)
      pokemon_obj.instance_variable_set(:@species, coerced) unless coerced.nil?
    rescue; end
  end

  def self.add_pokemon_from_json(poke_hash)
    return false unless defined?(Pokemon)
    begin
      validate_pokemon_payload!(poke_hash)
      normalize_stat_maps!(poke_hash)
      sid   = resolve_species_id(poke_hash["species"])
      level = [(poke_hash["level"] || 1).to_i, 1].max
      p = Pokemon.new(sid, level)
      p.load_json(poke_hash)
      force_species_id!(p)
      return false if party_count >= 6
      $Trainer.party << p
      true
    rescue => e
      pbMessage(_INTL("Received Pokémon data is invalid.\nSee debug log for details."))
      ##MultiplayerDebug.error("UI-TRADE", "add_pokemon_from_json failed: #{e.class} - #{e.message}")
      false
    end
  end

  def self.money; (defined?($Trainer) && $Trainer.respond_to?(:money)) ? ($Trainer.money || 0) : 0; end
  def self.has_money?(amt); money >= amt.to_i; end
  def self.add_money(delta)
    return false unless defined?($Trainer) && $Trainer.respond_to?(:money=)
    $Trainer.money = (money + delta.to_i); true
  end

  def self.bag
    return $PokemonBag if defined?($PokemonBag) && $PokemonBag
    return $bag if defined?($bag) && $bag
    nil
  end

  # Enumerate pockets -> [sym, qty]
  def self.bag_item_list
    b = bag; return [] unless b
    out = []
    begin
      b.pockets.each do |pocket|
        next unless pocket
        pocket.each do |slot|
          next unless slot && slot[1].to_i > 0
          sym = item_sym(slot[0])
          next unless tradeable_item?(sym)
          out << [sym, slot[1].to_i]
        end
      end
    rescue => e
      ##MultiplayerDebug.warn("UI-TRADE", "bag_item_list failed: #{e.message}")
    end
    out
  end

  def self.bag_has?(sym, qty)
    b = bag; return false unless b
    begin; b.pbQuantity(sym).to_i >= qty.to_i; rescue; false; end
  end
  def self.bag_can_add?(sym, qty)
    b = bag; return false unless b
    begin; b.pbCanStore?(sym, qty.to_i); rescue; true; end
  end
  def self.bag_add(sym, qty)
    b = bag; return false unless b
    begin; b.pbStoreItem(sym, qty.to_i); rescue; false; end
  end
  def self.bag_remove(sym, qty)
    b = bag; return false unless b
    begin; b.pbDeleteItem(sym, qty.to_i); rescue; false; end
  end
  # --- Silent autosave (no prompts) ------------------------------------------
  # Prefer Game.save(safe: true). Falls back to SaveData.save if present.
  # Never calls pbEmergencySave (it shows UI).
  def self.autosave_safely
    # Preferred API (Essentials v20+ style wrappers)
    begin
      if defined?(Game) && Game.respond_to?(:save)
        Game.save(safe: true)
        ##MultiplayerDebug.info("UI-TRADE", "Autosave (Game.save safe:true) succeeded.")
        return true
      end
    rescue => e
      ##MultiplayerDebug.warn("UI-TRADE", "Autosave Game.save failed: #{e.class}: #{e.message}")
    end

    # Quiet fallback (no UI)
    begin
      if defined?(SaveData) && SaveData.respond_to?(:save)
        begin
          SaveData.save(SaveData::FILE_PATH)  # explicit path if available
        rescue
          SaveData.save                       # generic call
        end
        ##MultiplayerDebug.info("UI-TRADE", "Autosave (SaveData.save) succeeded (fallback).")
        return true
      end
    rescue => e
      ##MultiplayerDebug.warn("UI-TRADE", "Autosave SaveData.save failed: #{e.class}: #{e.message}")
    end

    ##MultiplayerDebug.warn("UI-TRADE", "Autosave unavailable on this build.")
    false
  end
  # ---------- Offer model ----------
  class Offer
    attr_accessor :platinum, :items, :pokemon_index, :pokemon_json
    def initialize
      @platinum = 0
      @items = []
      @pokemon_index = nil
      @pokemon_json  = nil
    end
    def to_hash
      {
        "platinum"     => @platinum.to_i,
        "items"        => @items.map { |h| { "id" => h[:id].to_s, "qty" => h[:qty].to_i } },
        "pokemon"      => (@pokemon_index.nil? ? nil : @pokemon_index.to_i),
        "pokemon_json" => @pokemon_json
      }
    end
    def clear
      @platinum = 0; @items.clear; @pokemon_index = nil; @pokemon_json = nil
    end
  end

  # ---------- Trade panel (full-screen handheld look) ----------
  class Window_TradePanel
    PURPLE_DARK   = Color.new(36,  14,  48)
    PURPLE_MED    = Color.new(62,  24,  92)
    PURPLE_LIGHT  = Color.new(110, 60, 150)
    PURPLE_SCREEN = Color.new(50,  28,  70, 220)
    LAVENDER      = Color.new(200, 180, 230)
    WHITE         = Color.new(255, 255, 255)
    SOFT_YELLOW   = Color.new(255, 230, 120)
    SOFT_GREEN    = Color.new(120, 255, 120)

    def initialize(vp, my_offer, their_offer, my_ready, their_ready, my_confirm, their_confirm, peer_name)
      @vp = vp
      # FULL SCREEN bitmap; sprite at (0,0) so overlay icons align exactly
      @bmp = Bitmap.new(Graphics.width, Graphics.height)
      @spr = Sprite.new(@vp)
      @spr.x = 0; @spr.y = 0; @spr.z = 99999
      @spr.bitmap = @bmp
      @peer_name = peer_name || "Partner"

      @left_item_icons  = Array.new(4) { nil }
      @right_item_icons = Array.new(4) { nil }
      @left_poke_icon   = nil
      @right_poke_icon  = nil

      refresh(my_offer, their_offer, my_ready, their_ready, my_confirm, their_confirm)
    end

    def dispose
      @spr.bitmap.dispose if @spr&.bitmap && !@spr.bitmap.disposed?
      @spr.dispose if @spr
      (@left_item_icons + @right_item_icons).compact.each { |s| s.dispose }
      @left_item_icons.clear; @right_item_icons.clear
      @left_poke_icon&.dispose; @left_poke_icon = nil
      @right_poke_icon&.dispose; @right_poke_icon = nil
    end

    def title_color(ready, confirm)
      color = if ready && confirm
        SOFT_GREEN
      elsif ready && !confirm
        SOFT_YELLOW
      else
        WHITE
      end
      ##MultiplayerDebug.info("TRADE-DBG", "title_color: ready=#{ready}, confirm=#{confirm} → #{color == SOFT_GREEN ? 'GREEN' : (color == SOFT_YELLOW ? 'YELLOW' : 'WHITE')}")
      color
    end

    def draw_handheld(x, y, w, h, title, title_col)
      b = @bmp
      b.fill_rect(x, y, w, h, PURPLE_MED)
      b.fill_rect(x+3, y+3, w-6, h-6, PURPLE_DARK)
      b.fill_rect(x+6, y+6, w-12, h-12, PURPLE_MED)

      b.fill_rect(x+8, y+8, w-16, 28, PURPLE_LIGHT)
      b.font.color = title_col; b.font.size = 20
      b.draw_text(x+8, y+8, w-16, 28, title, 1)

      sx = x + 16; sy = y + 44; sw = w - 32; sh = h - 80
      b.fill_rect(sx, sy, sw, sh, PURPLE_SCREEN)
      b.fill_rect(sx+2, sy+2, sw-4, sh-4, Color.new(35, 20, 55, 220))

      gp = 12
      cell_h = ((sh - gp*5 - 2) / 3).floor
      cell_w = ((sw - gp*3) / 2).floor

      2.times do |row|
        2.times do |col|
          cx = sx + gp + col * (cell_w + gp)
          cy = sy + gp + row * (cell_h + gp)
          draw_slot(cx, cy, cell_w, cell_h)
        end
      end

      sep_y = sy + gp*3 + cell_h*2
      @bmp.fill_rect(sx+6, sep_y, sw-12, 2, PURPLE_LIGHT)

      poke_x  = sx + gp
      poke_y  = sep_y + gp
      money_x = sx + gp*2 + cell_w
      money_y = sep_y + gp
      draw_slot(poke_x,  poke_y,  cell_w, cell_h)
      draw_slot(money_x, money_y, cell_w, cell_h)

      return {
        item_cells: [
          [sx + gp,                 sy + gp,                  cell_w, cell_h],
          [sx + gp*2 + cell_w,      sy + gp,                  cell_w, cell_h],
          [sx + gp,                 sy + gp*2 + cell_h,       cell_w, cell_h],
          [sx + gp*2 + cell_w,      sy + gp*2 + cell_h,       cell_w, cell_h]
        ],
        poke_cell:  [poke_x,  poke_y,  cell_w, cell_h],
        money_cell: [money_x, money_y, cell_w, cell_h]
      }
    end

    def draw_slot(x, y, w, h)
      b = @bmp
      b.fill_rect(x, y, w, h, Color.new(25, 12, 40, 200))
      b.fill_rect(x+2, y+2, w-4, h-4, Color.new(20, 10, 32, 220))
      b.fill_rect(x, y, w, 2, PURPLE_LIGHT)
      b.fill_rect(x, y+h-2, w, 2, PURPLE_LIGHT)
      b.fill_rect(x, y, 2, h, PURPLE_LIGHT)
      b.fill_rect(x+w-2, y, 2, h, PURPLE_LIGHT)
    end

    # Center item icon in given cell (adds panel sprite offset even though it's 0,0 now)
    def ensure_item_icon(arr, idx, rect, sym_or_nil)
      x, y, w, h = rect
      if sym_or_nil.nil?
        if arr[idx]
          arr[idx].item = nil
          arr[idx].visible = false
        end
        return
      end
      icon = arr[idx]
      if icon.nil?
        icon = ItemIconSprite.new(0, 0, nil, @vp)
        icon.z = 100_000
        icon.setOffset(PictureOrigin::Center)
        arr[idx] = icon
      end
      icon.x = @spr.x + x + w/2
      icon.y = @spr.y + y + h/2
      icon.item = sym_or_nil
      icon.visible = true
    end

    def ensure_poke_icon(current, rect, pj_hash)
      x, y, w, h = rect
      if pj_hash.nil?
        current&.dispose
        return nil
      end
      species = nil; gender = 0; form = 0; shiny = false
      begin
        species = TradeUI.resolve_species_id(pj_hash["species"])
        gender  = pj_hash["gender"].to_i rescue 0
        form    = pj_hash["form"].to_i   rescue 0
        shiny   = !!pj_hash["shiny"]
      rescue; end
      if current.nil?
        current = PokemonSpeciesIconSprite.new(species, @vp)
        current.z = 100_000
        current.setOffset(PictureOrigin::Center)
      end
      current.pbSetParams(species, gender, form, shiny)
      current.x = @spr.x + x + w/2
      current.y = @spr.y + y + h/2
      current
    end

    def draw_money_text(cell, amount)
      x, y, w, h = cell

      # Try to load platinum icon
      icon_size = 16
      icon_x = x + 2
      icon_y = y + (h - icon_size) / 2
      icon_loaded = false

      begin
        if pbResolveBitmap("Graphics/Pictures/Trainer Card/platinum_icon")
          icon_bitmap = RPG::Cache.load_bitmap("Graphics/Pictures/Trainer Card/", "platinum_icon")
          src_rect = Rect.new(0, 0, icon_bitmap.width, icon_bitmap.height)
          dest_rect = Rect.new(icon_x, icon_y, icon_size, icon_size)
          @bmp.stretch_blt(dest_rect, icon_bitmap, src_rect)
          icon_loaded = true
        elsif pbResolveBitmap("Graphics/Pictures/platinum")
          icon_bitmap = RPG::Cache.load_bitmap("Graphics/Pictures/", "platinum")
          src_rect = Rect.new(0, 0, icon_bitmap.width, icon_bitmap.height)
          dest_rect = Rect.new(icon_x, icon_y, icon_size, icon_size)
          @bmp.stretch_blt(dest_rect, icon_bitmap, src_rect)
          icon_loaded = true
        end
      rescue => e
        # Silently fail - will use fallback
      end

      # Fallback: Draw "Pt" text if icon not loaded
      icon_width = icon_size
      unless icon_loaded
        old_size = @bmp.font.size
        @bmp.font.size = 12
        @bmp.font.color = LAVENDER
        @bmp.draw_text(icon_x, icon_y, 20, 20, "Pt")
        @bmp.font.size = old_size
        icon_width = 18
      end

      # Format amount text
      amount_text = amount.to_i.to_s_formatted

      # Calculate text area (after icon)
      text_x = icon_x + icon_width + 2
      text_w = (x + w) - text_x

      # Dynamic font scaling
      old_font_size = @bmp.font.size
      @bmp.font.size = 20
      current_font_size = 20
      text_size = @bmp.text_size(amount_text)
      text_width = text_size.width

      # Scale down if too wide
      max_width = text_w - 4
      if text_width > max_width
        scale = max_width.to_f / text_width
        current_font_size = (current_font_size * scale).to_i
        current_font_size = [current_font_size, 10].max
        @bmp.font.size = current_font_size
        text_size = @bmp.text_size(amount_text)
        text_width = text_size.width
      end

      # Center text vertically
      text_height = text_size.height
      text_y = y + (h - text_height) / 2

      # Draw text
      @bmp.font.color = LAVENDER
      @bmp.draw_text(text_x, text_y, text_width + 10, text_height + 4, amount_text)

      # Restore font size
      @bmp.font.size = old_font_size
    end

    def draw_item_qty_text(cell, qty)
      x, y, w, h = cell
      @bmp.font.size = 18
      @bmp.font.color = LAVENDER
      @bmp.draw_text(x+6, y+h-26, w-12, 20, _INTL("x{1}", qty.to_i), 2)
    end

    def refresh(my_offer, their_offer, my_ready, their_ready, my_confirm, their_confirm)
      @bmp.clear
      w = @bmp.width; h = @bmp.height

      @bmp.fill_rect(0, 0, w, h, Color.new(10, 5, 16, 220))
      @bmp.font.size = 22
      @bmp.font.color = LAVENDER
      @bmp.draw_text(0, 6, w, 28, _INTL("Trading with {1}", @peer_name), 1)

      pad = 24
      device_w = (w - pad*3) / 2
      device_h = h - 64 - 16
      left_x  = pad
      right_x = pad*2 + device_w
      top_y   = 40

      left_layout  = draw_handheld(left_x,  top_y, device_w, device_h, _INTL("Your Offer"),
                                   title_color(my_ready, my_confirm))
      right_layout = draw_handheld(right_x, top_y, device_w, device_h, _INTL("Their Offer"),
                                   title_color(their_ready, their_confirm))

      # LEFT
      my_items = (my_offer["items"] || [])
      4.times do |i|
        cell = left_layout[:item_cells][i]
        item = my_items[i]
        if item
          sym = TradeUI.item_sym(item["id"])
          ensure_item_icon(@left_item_icons, i, cell, sym)
          draw_item_qty_text(cell, item["qty"])
        else
          ensure_item_icon(@left_item_icons, i, cell, nil)
        end
      end
      @left_poke_icon = ensure_poke_icon(@left_poke_icon, left_layout[:poke_cell], my_offer["pokemon_json"])
      draw_money_text(left_layout[:money_cell], my_offer["platinum"].to_i)

      # RIGHT
      th_items = (their_offer["items"] || [])
      4.times do |i|
        cell = right_layout[:item_cells][i]
        item = th_items[i]
        if item
          sym = TradeUI.item_sym(item["id"])
          ensure_item_icon(@right_item_icons, i, cell, sym)
          draw_item_qty_text(cell, item["qty"])
        else
          ensure_item_icon(@right_item_icons, i, cell, nil)
        end
      end
      @right_poke_icon = ensure_poke_icon(@right_poke_icon, right_layout[:poke_cell], their_offer["pokemon_json"])
      draw_money_text(right_layout[:money_cell], their_offer["platinum"].to_i)
    end
  end

  # ---------- Trade Scene ----------
  class Scene_Trade
    def initialize(trade_id, peer_name, my_platinum_max = 0)
      @trade_id  = trade_id
      @peer_name = peer_name || "Partner"
      @vp = @bg = @panel = nil
      @my_offer = Offer.new
      @their_offer = {"platinum"=>0,"items"=>[],"pokemon"=>nil,"pokemon_json"=>nil}
      @my_platinum_max = my_platinum_max  # Server-provided max platinum for input validation
      @my_ready = @their_ready = @my_confirm = @their_confirm = false
      @running = false
    end

    def main
      setup_view
      loop do
        Graphics.update; Input.update
        feed_events
        handle_input
        break unless @running
      end
    ensure
      teardown_view
    end

    def setup_view
      @vp = Viewport.new(0,0,Graphics.width,Graphics.height); @vp.z = 99998
      @bg = Sprite.new(@vp); @bg.bitmap = Bitmap.new(Graphics.width, Graphics.height)
      @bg.bitmap.fill_rect(0,0,Graphics.width,Graphics.height, Color.new(0,0,0,160))
      refresh_panel
      @running = true
    end
    def teardown_view
      @panel&.dispose; @panel = nil
      if @bg
        @bg.bitmap.dispose if @bg.bitmap && !@bg.bitmap.disposed?
        @bg.dispose
      end
      @vp&.dispose; @vp = nil
    end

    def refresh_panel
      my_hash = @my_offer.to_hash
      their_hash = @their_offer.dup
      if @panel
        @panel.refresh(my_hash, their_hash, @my_ready, @their_ready, @my_confirm, @their_confirm)
      else
        @panel = Window_TradePanel.new(@vp, my_hash, their_hash, @my_ready, @their_ready, @my_confirm, @their_confirm, @peer_name)
      end
    end

    def feed_events
      # Check for disconnection - close trade window if disconnected
      unless MultiplayerClient.instance_variable_get(:@connected)
        ##MultiplayerDebug.warn("UI-TRADE", "Disconnected during trade - aborting")
        @running = false
        return
      end

      while MultiplayerClient.trade_events_pending?
        ev = MultiplayerClient.next_trade_event
        next unless ev && ev[:type]
        case ev[:type]
        when :update
          d = ev[:data]; next unless d && d[:trade_id].to_s == @trade_id.to_s
          if d[:from_sid].to_s != MultiplayerClient.session_id.to_s
            @their_offer = d[:offer] || {"platinum"=>0,"items"=>[],"pokemon"=>nil,"pokemon_json"=>nil}
            @their_ready = false; @their_confirm = false
            @my_confirm = false
            refresh_panel
          end
        when :ready
          d = ev[:data]; next unless d && d[:trade_id].to_s == @trade_id.to_s
          if d[:sid].to_s == MultiplayerClient.session_id.to_s
            @my_ready = !!d[:ready]
            @my_confirm = false   # <- always clear confirm when (re)ready toggles
          else
            @their_ready = !!d[:ready]
            @their_confirm = false  # <- FIXED: always clear confirm when ready state changes
          end
          refresh_panel
        when :confirm
          d = ev[:data]; next unless d && d[:trade_id].to_s == @trade_id.to_s
          if d[:sid].to_s == MultiplayerClient.session_id.to_s
            @my_confirm = true
          else
            @their_confirm = true
          end
          refresh_panel
        when :execute
          d = ev[:data]; next unless d && d[:trade_id].to_s == @trade_id.to_s
          ok, reason = apply_execution(d[:payload] || {})
          if ok
            # Validation passed - store payload for commit phase
            @pending_commit_payload = d[:payload]
            MultiplayerClient.trade_execute_ok
          else
            MultiplayerClient.trade_execute_fail(reason || "EXECUTION_FAILED")
            pbSEPlay("Battle flee") rescue nil
            pbMessage(_INTL("Trade failed: {1}", reason.to_s))
          end
        when :complete
          # Both clients validated successfully - now commit the trade
          if @pending_commit_payload
            commit_execution(@pending_commit_payload)
            @pending_commit_payload = nil
            # --- autosave right after successful execution (hard commit)
            TradeUI.autosave_safely
            pbSEPlay("Door enter") rescue nil
            pbMessage(_INTL("Trade finalized!"))
          end
          @running = false
        when :abort, :error, :declined
          @running = false
        end
      end
    end

    def handle_input
      return unless @running
      if Input.trigger?(Input::BACK)
        if TradeUI.selfpbConfirm(_INTL("Cancel the trade?"))
          MultiplayerClient.trade_cancel
          @running = false
        end
        return
      end
      return unless Input.trigger?(Input::USE)
      cmds = [
        _INTL("Add/Remove Item"),
        _INTL("Choose/Clear Pokémon"),
        _INTL("Set/Clear Money"),
        _INTL("Clear Offer"),
        _INTL("Toggle Ready"),
        _INTL("Confirm"),
        _INTL("Cancel")
      ]
      ch = pbMessage(_INTL("Select an action."), cmds, cmds.length - 1)
      case ch
      when 0 then act_items
      when 1 then act_pokemon
      when 2 then act_money
      when 3 then act_clear
      when 4 then act_toggle_ready
      when 5 then act_confirm
      when 6 then act_cancel
      end
    end

    # --- actions ---
    def act_items
      b = TradeUI.bag
      unless b; pbMessage(_INTL("Your bag is not accessible.")); return; end
      ix = pbMessage(_INTL("Choose:"), [_INTL("Add Item"), _INTL("Remove Item"), _INTL("Back")], 2)
      return if ix == 2
      if ix == 0
        sym, have_q = choose_item_from_bag
        return unless sym && have_q && have_q > 0
        unless TradeUI.tradeable_item?(sym)
          pbMessage(_INTL("That item cannot be traded.")); return
        end
        max_q = [have_q, 999].min
        qty = TradeUI.pbInputNumber(_INTL("Choose how many you want to trade:"), max_q, 1)
        return if qty.nil? || qty <= 0
        if qty > have_q
          pbMessage(_INTL("Not enough {1}!", TradeUI.item_name(sym))); return
        end
        slot = @my_offer.items.index { |h| h && h[:id] == sym }
        if slot
          @my_offer.items[slot][:qty] = (@my_offer.items[slot][:qty].to_i + qty)
        else
          if @my_offer.items.length >= MAX_ITEM_SLOTS
            pbMessage(_INTL("All item slots are filled.")); return
          end
          @my_offer.items << { id: sym, qty: qty }
        end
      else
        if @my_offer.items.empty?; pbMessage(_INTL("No items in your offer.")); return; end
        names = @my_offer.items.map { |h| "#{TradeUI.item_name(h[:id])} x#{h[:qty]}" } + [_INTL("Cancel")]
        sel = pbMessage(_INTL("Remove which?"), names, names.length - 1)
        return if sel < 0 || sel >= @my_offer.items.length
        @my_offer.items.delete_at(sel)
      end
      send_offer_update
    end

    def act_pokemon
      ix = pbMessage(_INTL("Pokémon:"), [_INTL("Choose"), _INTL("Clear"), _INTL("Back")], 2)
      return if ix == 2
      if ix == 1
        @my_offer.pokemon_index = nil
        @my_offer.pokemon_json  = nil
        send_offer_update; return
      end
      if TradeUI.party_count <= 1
        pbMessage(_INTL("You must keep at least one Pokémon.")); return
      end
      names = TradeUI.party.each_with_index.map { |pk, i|
        (pk.respond_to?(:name) && pk.respond_to?(:level)) ? _INTL("{1}  Lv.{2}", pk.name, pk.level) : _INTL("Slot {1}", i+1)
      }
      sel = pbMessage(_INTL("Pick a Pokémon to offer."), names + [_INTL("Cancel")], names.length)
      return if sel < 0 || sel >= names.length
      if TradeUI.party_count <= 1
        pbMessage(_INTL("You must keep at least one Pokémon.")); return
      end
      pk = TradeUI.party[sel]
      begin
        pj = pk.to_json
        TradeUI.ensure_complete_stat_maps!(pj)
      rescue
        pbMessage(_INTL("This Pokémon cannot be serialized.")); return
      end
      @my_offer.pokemon_index = sel
      @my_offer.pokemon_json  = pj
      send_offer_update
    end

    def act_money
      ix = pbMessage(_INTL("Platinum:"), [_INTL("Set Amount"), _INTL("Clear"), _INTL("Back")], 2)
      return if ix == 2
      if ix == 1
        @my_offer.platinum = 0; send_offer_update; return
      end
      # Use server-provided maximum (prevents over-selection)
      have = @my_platinum_max
      amt = TradeUI.pbInputMoney(_INTL("Choose how much Platinum you want to trade:"), have, 0)
      return if amt.nil?
      amt = amt.to_i
      @my_offer.platinum = amt
      send_offer_update
    end

    def act_clear
      @my_offer.clear
      @my_ready = @my_confirm = false
      send_offer_update
    end

    def act_toggle_ready
      # Platinum validation removed - server validates and client prevents over-selection
      @my_offer.items.each do |h|
        next unless h
        sym = TradeUI.item_sym(h[:id]); qty = h[:qty].to_i
        unless TradeUI.bag_has?(sym, qty)
          pbMessage(_INTL("You don't have enough {1}.", TradeUI.item_name(sym))); return
        end
      end
      if @my_offer.pokemon_index && TradeUI.party_count <= 1
        pbMessage(_INTL("You must keep at least one Pokémon.")); return
      end
      @my_ready = !@my_ready
      @my_confirm = false   # <-- always clear confirm when toggling ready
      ##MultiplayerDebug.info("TRADE-DBG", "=== act_toggle_ready ===")
      ##MultiplayerDebug.info("TRADE-DBG", "  my_ready=#{@my_ready}, my_confirm=#{@my_confirm}")
      MultiplayerClient.trade_set_ready(@my_ready)
      refresh_panel
    end

    def act_confirm
      unless @my_ready
        pbMessage(_INTL("Mark ready first.")); return
      end
      ##MultiplayerDebug.info("TRADE-DBG", "=== act_confirm ===")
      ##MultiplayerDebug.info("TRADE-DBG", "  my_ready=#{@my_ready}, my_confirm (before)=#{@my_confirm}")
      MultiplayerClient.trade_confirm
      @my_confirm = true
      ##MultiplayerDebug.info("TRADE-DBG", "  my_confirm (after)=#{@my_confirm}")
      refresh_panel
    end

    def act_cancel
      if TradeUI.selfpbConfirm(_INTL("Cancel the trade?"))
        MultiplayerClient.trade_cancel
        @running = false
      end
    end

    def send_offer_update
      @my_offer.items = @my_offer.items[0...MAX_ITEM_SLOTS]
      MultiplayerClient.trade_update_offer(@my_offer.to_hash)
      refresh_panel
    end

    # ---------- execution ----------
    def apply_execution(payload)
      mine   = payload[:my_final]    || {}
      theirs = payload[:their_final] || {}

      # Platinum handling removed - server handles platinum transfer before TRADE_EXECUTE

      g_items = (mine["items"] || []).compact.map  { |h| [TradeUI.item_sym(h["id"]),   h["qty"].to_i] }
      r_items = (theirs["items"] || []).compact.map{ |h| [TradeUI.item_sym(h["id"]),   h["qty"].to_i] }

      give_idx = mine["pokemon"]
      recv_pj  = theirs["pokemon_json"]

      # === VALIDATION PHASE - NO CHANGES MADE YET ===
      # Validate items
      g_items.each { |sym,qty| return [false, "NO_ITEM_#{sym}"]   unless TradeUI.bag_has?(sym, qty) }
      r_items.each { |sym,qty| return [false, "BAG_FULL_#{sym}"]  unless TradeUI.bag_can_add?(sym, qty) }

      # Validate: Can't give away last Pokemon
      if give_idx && TradeUI.party_count <= 1
        return [false, "KEEP_ONE_POKEMON"]
      end

      # Validate: Party space (account for Pokemon we're giving away)
      if recv_pj
        net_party_change = (give_idx ? 0 : 1)  # +1 if receiving without giving, 0 if swapping
        if TradeUI.party_count + net_party_change > 6
          return [false, "PARTY_FULL"]
        end

        # Validate the Pokemon data is valid and can be deserialized
        begin
          TradeUI.validate_pokemon_payload!(recv_pj)
          TradeUI.normalize_stat_maps!(recv_pj)
        rescue => e
          return [false, "BAD_POKEMON_DATA"]
        end
      end

      # Validate Pokemon exists if we're giving one
      if give_idx
        return [false, "POKEMON_LOST"] unless TradeUI.party[give_idx]
      end

      # === ALL VALIDATIONS PASSED - RETURN SUCCESS WITHOUT MAKING CHANGES ===
      # Server will wait for both clients to validate, then send TRADE_COMPLETE
      # Actual execution happens in feed_events when we receive TRADE_COMPLETE
      [true, nil]
    end

    # Commit the trade - actually transfer items/Pokemon
    # Only called after BOTH clients validated successfully
    def commit_execution(payload)
      mine   = payload[:my_final]    || {}
      theirs = payload[:their_final] || {}

      g_items = (mine["items"] || []).compact.map  { |h| [TradeUI.item_sym(h["id"]),   h["qty"].to_i] }
      r_items = (theirs["items"] || []).compact.map{ |h| [TradeUI.item_sym(h["id"]),   h["qty"].to_i] }

      give_idx = mine["pokemon"]
      recv_pj  = theirs["pokemon_json"]

      # Process items
      g_items.each { |sym,qty| TradeUI.bag_remove(sym, qty) }
      r_items.each { |sym,qty| TradeUI.bag_add(sym, qty) }

      # CRITICAL FIX: Remove our Pokemon FIRST, then add theirs
      # This prevents party overflow when both parties are full (6 Pokemon each)
      # Old order: add (fails silently at 6) -> remove = both Pokemon deleted
      # New order: remove -> add = proper swap even with full parties
      if give_idx
        TradeUI.remove_pokemon_at(give_idx)
      end

      # Add received Pokemon AFTER removing ours
      if recv_pj
        TradeUI.add_pokemon_from_json(recv_pj)
      end
    end

    # lets the user pick only an item they actually possess
    def choose_item_from_bag
      list = TradeUI.bag_item_list
      if list.empty?
        pbMessage(_INTL("You don't have any items suitable for trading."))
        return [nil, nil]
      end
      labels = list.map { |(sym, q)| "#{TradeUI.item_name(sym)} x#{q}" } + [_INTL("Cancel")]
      sel = pbMessage(_INTL("Pick an item."), labels, labels.length - 1)
      return [nil, nil] if sel < 0 || sel >= list.length
      list[sel]
    end
  end

  # ---------- Scene_Map hook ----------
  if defined?(Scene_Map)
    class ::Scene_Map
      alias kif_trade_update update unless method_defined?(:kif_trade_update)
      def update
        kif_trade_update
        TradeUI.tick_trade_ui
      end
    end
    ##MultiplayerDebug.info("UI-TRADE", "Hooked Scene_Map#update for trade events.")
  else
    ##MultiplayerDebug.error("UI-TRADE", "Scene_Map not found; trade hook disabled.")
  end

  def self.tick_trade_ui
    while MultiplayerClient.trade_events_pending?
      ev = MultiplayerClient.next_trade_event
      next unless ev
      if ev[:type] == :invite
        from_sid  = ev[:data][:from_sid].to_s
        from_name = ev[:data][:from_name].to_s
        label = (from_name && from_name != "" ? from_name : from_sid)
        if TradeUI.selfpbConfirm(_INTL("{1} is requesting a trade.\nDo you accept?", label))
          MultiplayerClient.trade_accept(from_sid)
        else
          MultiplayerClient.trade_decline(from_sid)
        end
        next
      elsif ev[:type] == :start
        tid  = ev[:data][:trade_id].to_s
        peer = (ev[:data][:other_name] || ev[:data][:other_sid]).to_s
        my_plat = ev[:data][:my_platinum].to_i

        # Drain any premature complete/abort events that arrived before window opens
        # This prevents the window from closing immediately on first frame
        drained = []
        while MultiplayerClient.trade_events_pending?
          peek_ev = MultiplayerClient.next_trade_event
          if peek_ev && (peek_ev[:type] == :complete || peek_ev[:type] == :abort || peek_ev[:type] == :error)
            drained << peek_ev[:type]
            ##MultiplayerDebug.warn("UI-TRADE", "Drained premature #{peek_ev[:type]} event before opening trade window")
          else
            # Put it back for scene.main to process
            MultiplayerClient.push_trade_event(peek_ev) if peek_ev
            break
          end
        end

        scene = Scene_Trade.new(tid, peer, my_plat)
        scene.main
        MultiplayerClient.trade_clear_if_final
        break
      else
        MultiplayerClient.push_trade_event(ev)
        break
      end
    end
  end
end

##MultiplayerDebug.info("UI-TRADE", "Trade UI loaded.")
