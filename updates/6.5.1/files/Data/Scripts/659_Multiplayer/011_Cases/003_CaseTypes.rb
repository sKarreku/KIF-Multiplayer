#===============================================================================
# KIF Cases — Case Type Definitions
# File: 011_Cases/003_CaseTypes.rb
#
# Defines the three case types (PokéCase, MegaCase, MoveCase) with their
# pool builders, tile rendering, award logic, and display properties.
#===============================================================================

module KIFCases

  # ── Case type definitions ──────────────────────────────────────────────────
  CASE_DEFS = {
    poke: {
      name:        "PokéCase",
      cost:        200,
      color_rgb:   [50, 170, 170],
      description: "Contains NPT Pokémon across 7 rarity tiers",
      has_rarity:  true,
      server_tag:  "poke",
    },
    mega: {
      name:        "MegaCase",
      cost:        1000,
      color_rgb:   [180, 80, 255],
      description: "Contains a random Mega Stone",
      has_rarity:  false,
      server_tag:  "mega",
    },
    move: {
      name:        "MoveCase",
      cost:        500,
      color_rgb:   [80, 200, 80],
      description: "Contains a random NPT Move TM",
      has_rarity:  false,
      server_tag:  "move",
    },
  }.freeze

  # ── Pool builders ──────────────────────────────────────────────────────────

  # MegaCase: flat array of all mega stone item symbols
  def self.build_mega_pool
    return @mega_pool if @mega_pool
    stones = []
    GameData::Item.each do |item|
      next unless item.id_number.between?(9300, 9439)
      # type 12 = mega stone
      stones << item.id
    end
    @mega_pool = stones.sort_by { |sym| GameData::Item.get(sym).id_number }
    @mega_pool
  end

  # MoveCase: flat array of all NPT TM item symbols (excludes signature moves)
  def self.build_move_pool
    return @move_pool if @move_pool
    tms = []
    GameData::Item.each do |item|
      next unless item.id_number.between?(9500, 9699)
      next unless item.is_TM?
      # Skip signature move TMs (tagged by NPT)
      desc = item.description rescue ""
      next if desc.include?("(Signature move)")
      tms << item.id
    end
    @move_pool = tms.sort_by { |sym| GameData::Item.get(sym).id_number }
    @move_pool
  end

  def self.reset_mega_pool; @mega_pool = nil; end
  def self.reset_move_pool; @move_pool = nil; end

  # Generic pool accessor by case type
  def self.pool_for(case_type)
    case case_type
    when :poke then build_pool          # existing 7-tier pool
    when :mega then build_mega_pool     # flat array
    when :move then build_move_pool     # flat array
    end
  end

  # Pool size by type
  def self.pool_size_for(case_type)
    pool = pool_for(case_type)
    return pool.sum(&:size) if pool.is_a?(Array) && pool.first.is_a?(Array) # tiered
    return pool.size if pool.is_a?(Array)
    0
  end

  # Resolve result by type
  #   poke: (tier, position) → species symbol
  #   mega/move: (position) → item symbol
  def self.resolve_result(case_type, tier_or_position, position = nil)
    case case_type
    when :poke
      resolve_species(tier_or_position, position)
    when :mega
      pool = build_mega_pool
      return nil if pool.empty?
      pool[tier_or_position % pool.size]
    when :move
      pool = build_move_pool
      return nil if pool.empty?
      pool[tier_or_position % pool.size]
    end
  end

  # ── Award logic ────────────────────────────────────────────────────────────

  # Award a mega stone to the player's bag
  def self.award_item(item_sym)
    return nil unless $Trainer && item_sym
    return nil unless GameData::Item.exists?(item_sym)

    if $PokemonBag.pbStoreItem(item_sym, 1)
      Kernel.tryAutosave() rescue nil
      return item_sym
    end
    nil
  end

  # ── Tile bitmap builders ───────────────────────────────────────────────────

  # Build a tile bitmap for a mega stone
  def self.make_mega_tile(item_sym, tile_size = 64)
    bmp = Bitmap.new(tile_size, tile_size)
    border = Color.new(180, 80, 255, 255)
    inner  = Color.new(240, 228, 255, 255)
    bmp.fill_rect(0, 0, tile_size, tile_size, border)
    bmp.fill_rect(3, 3, tile_size - 6, tile_size - 6, inner)
    if item_sym
      icon_file = "Graphics/Items/#{item_sym}" rescue nil
      _blt_item_icon(bmp, icon_file, tile_size)
    end
    bmp
  end

  # Build a tile bitmap for a TM move
  def self.make_move_tile(item_sym, tile_size = 64)
    bmp = Bitmap.new(tile_size, tile_size)
    border = Color.new(80, 200, 80, 255)
    inner  = Color.new(228, 245, 228, 255)
    bmp.fill_rect(0, 0, tile_size, tile_size, border)
    bmp.fill_rect(3, 3, tile_size - 6, tile_size - 6, inner)
    if item_sym
      # Use type-based TM sprite
      begin
        item_data = GameData::Item.get(item_sym)
        if item_data.move
          move_data = GameData::Move.get(item_data.move)
          type_name = move_data.type.to_s
          icon_file = "Graphics/Items/machine_#{type_name}"
          _blt_item_icon(bmp, icon_file, tile_size)
        end
      rescue; end
    end
    bmp
  end

  # Shared: blit an item icon centered on a tile bitmap
  def self._blt_item_icon(bmp, icon_file, tile_size)
    return unless icon_file
    begin
      icon_bmp = AnimatedBitmap.new(icon_file)
      raw = icon_bmp.deanimate
      if raw && !raw.disposed?
        ix = (tile_size - raw.width) / 2
        iy = (tile_size - raw.height) / 2
        bmp.blt(ix, iy, raw, Rect.new(0, 0, raw.width, raw.height))
        raw.dispose
      end
      icon_bmp.dispose rescue nil
    rescue; end
  end
  private_class_method :_blt_item_icon

  # ── Display name for results ───────────────────────────────────────────────

  def self.result_display_name(case_type, result_sym)
    case case_type
    when :poke
      GameData::Species.get(result_sym).name rescue result_sym.to_s
    when :mega
      GameData::Item.get(result_sym).name rescue result_sym.to_s
    when :move
      item_data = GameData::Item.get(result_sym) rescue nil
      if item_data&.move
        move_data = GameData::Move.get(item_data.move) rescue nil
        move_data ? move_data.name : result_sym.to_s
      else
        result_sym.to_s
      end
    end
  end
end
