#===============================================================================
# MODULE 8: Boss Pokemon System - Loot System
#===============================================================================
# Handles boss loot voting and distribution:
#   - 3 pre-rolled loot options displayed after boss defeat
#   - 10 second voting timer
#   - Hidden votes until timer ends
#   - Majority wins (ties = random)
#   - All players receive winning loot
#
# Test: Defeat boss, vote UI appears. After 10s, item distributed.
#===============================================================================

module BossLootSystem
  @votes = {}           # player_sid => option_index
  @options = []         # 3 loot options
  @battle_id = nil
  @timer_start = nil
  @voting_active = false
  @vote_ui = nil

  #=============================================================================
  # Start Loot Voting
  #=============================================================================
  def self.start_vote(battle, boss_pkmn)
    return unless boss_pkmn&.is_boss?

    @votes = {}
    @options = boss_pkmn.boss_loot_options
    @battle_id = boss_pkmn.boss_battle_id
    @timer_start = Time.now
    @voting_active = true
    @battle = battle

    # Get local player SID
    @local_sid = defined?(MultiplayerClient) ? MultiplayerClient.session_id.to_s : "LOCAL"

    MultiplayerDebug.info("BOSS-LOOT", "Starting vote for battle #{@battle_id}") if defined?(MultiplayerDebug)

    # Show vote UI
    show_vote_screen

    # Start timer (non-blocking via update loop)
  end

  #=============================================================================
  # Cast Vote (local player)
  #=============================================================================
  def self.cast_vote(option_index)
    return unless @voting_active
    return if option_index < 0 || option_index >= 3

    @votes[@local_sid] = option_index

    # Send to server for multiplayer sync
    if defined?(MultiplayerClient) && @battle_id
      payload = {
        "battle_id" => @battle_id,
        "vote" => option_index,
        "sid" => @local_sid
      }
      json_str = MiniJSON.dump(payload) rescue payload.to_s
      MultiplayerClient.send_data("BOSS_VOTE:#{json_str}")
    end

    MultiplayerDebug.info("BOSS-LOOT", "Cast vote: option #{option_index}") if defined?(MultiplayerDebug)

    # Update UI to show selection
    update_vote_ui_selection(option_index)
  end

  #=============================================================================
  # Receive Vote from Network (other players)
  #=============================================================================
  def self.receive_vote(sid, option_index)
    return unless @voting_active
    @votes[sid] = option_index
    MultiplayerDebug.info("BOSS-LOOT", "Received vote from #{sid}: option #{option_index}") if defined?(MultiplayerDebug)
  end

  #=============================================================================
  # Update (called each frame while voting)
  #=============================================================================
  def self.update
    return unless @voting_active

    # Check timer
    elapsed = Time.now - @timer_start
    remaining = BossConfig::VOTE_SECONDS - elapsed.to_i

    # Update timer display
    update_timer_display(remaining)

    # Time's up
    if elapsed >= BossConfig::VOTE_SECONDS
      resolve_vote
    end
  end

  #=============================================================================
  # Resolve Vote
  #=============================================================================
  def self.resolve_vote
    return unless @voting_active
    @voting_active = false

    # Count votes
    counts = [0, 0, 0]
    @votes.each_value { |v| counts[v] += 1 if v && v >= 0 && v < 3 }

    # Find winner (ties = random among tied)
    max_votes = counts.max
    winners = counts.each_index.select { |i| counts[i] == max_votes }
    winner_idx = winners.sample

    winning_loot = @options[winner_idx]

    MultiplayerDebug.info("BOSS-LOOT", "Vote resolved: option #{winner_idx} wins (#{counts.inspect})") if defined?(MultiplayerDebug)

    # Show results
    show_vote_results(counts, winner_idx)

    # Notify server (initiator only sends BOSS_DEFEATED)
    if defined?(MultiplayerClient) && @battle_id
      # Check if we're initiator or if this is solo
      payload = { "battle_id" => @battle_id, "winner" => winner_idx }
      json_str = MiniJSON.dump(payload) rescue payload.to_s
      MultiplayerClient.send_data("BOSS_DEFEATED:#{json_str}")
    end

    # Distribute loot locally
    distribute_loot(winning_loot)

    # Cleanup
    hide_vote_screen
  end

  #=============================================================================
  # Distribute Loot
  #=============================================================================
  def self.distribute_loot(loot)
    return unless loot

    item = loot[:item]
    qty = loot[:qty] || 1

    # Special rewards (eggs) - not bag items
    if BossConfig.special_reward?(item)
      distribute_special_reward(item)
      return
    end

    # Normal item: add to bag
    if defined?($PokemonBag) && $PokemonBag
      $PokemonBag.pbStoreItem(item, qty)
    end

    # Get item name for display
    item_name = GameData::Item.get(item).name rescue item.to_s

    # Show message
    pbMessage(_INTL("You received {1}x {2}!", qty, item_name))

    MultiplayerDebug.info("BOSS-LOOT", "Distributed: #{qty}x #{item}") if defined?(MultiplayerDebug)
  end

  #=============================================================================
  # Distribute Special Rewards (Shiny Eggs)
  #=============================================================================
  def self.distribute_special_reward(reward_id)
    case reward_id
    when :SHINY_EGG
      give_shiny_egg
    when :SHINY_LEGENDARY_EGG
      give_shiny_legendary_egg
    else
      MultiplayerDebug.error("BOSS-LOOT", "Unknown special reward: #{reward_id}") if defined?(MultiplayerDebug)
    end
  end

  #=============================================================================
  # Shiny Egg (<500 BST, base stage, weighted by catch rate)
  #=============================================================================
  def self.give_shiny_egg
    bst_max = 500

    candidates = []
    (1..NB_POKEMON).each do |i|
      species = GameData::Species.get(i) rescue next
      bst = calcBaseStatsSum(species.id) rescue 0
      next if bst >= bst_max

      has_prevo = species.respond_to?(:get_previous_species) ? species.get_previous_species != species.id : false
      next if has_prevo

      candidates << { species: species.id, bst: bst, catch_rate: species.catch_rate }
    end

    if candidates.empty?
      pbMessage(_INTL("No eligible Pokemon found for Shiny Egg!"))
      return
    end

    # Weighted selection by catch rate
    total_weight = candidates.sum { |c| c[:catch_rate] }
    roll = rand(total_weight)
    cumulative = 0
    selected = nil
    candidates.each do |c|
      cumulative += c[:catch_rate]
      if roll < cumulative
        selected = c[:species]
        break
      end
    end
    selected ||= candidates.first[:species]

    # Create shiny egg
    pokemon = Pokemon.new(selected, 1)
    pokemon.shiny = true
    pokemon.name = _INTL("Egg")
    pokemon.steps_to_hatch = pokemon.species_data.hatch_steps rescue 5120
    pokemon.hatched_map = 0
    pokemon.obtain_method = 1
    pokemon.obtain_text = "Boss Reward Egg"
    pokemon.time_form_set = nil
    pokemon.form = 0 if pokemon.isSpecies?(:SHAYMIN)
    pokemon.heal

    pbAddPokemon(pokemon, 1, true, true) if defined?(pbAddPokemon)
    pbMessage(_INTL("You received a Shiny Egg!"))
    MultiplayerDebug.info("BOSS-LOOT", "Gave Shiny Egg: #{selected}") if defined?(MultiplayerDebug)
  rescue => e
    MultiplayerDebug.error("BOSS-LOOT", "Shiny egg error: #{e.message}") if defined?(MultiplayerDebug)
    pbMessage(_INTL("Error generating Shiny Egg."))
  end

  #=============================================================================
  # Shiny Legendary Egg (500+ BST, legendaries favored, rarer = more likely)
  #=============================================================================
  def self.give_shiny_legendary_egg
    bst_min = 500

    candidates = []

    # Legendaries first
    if defined?(LEGENDARIES_LIST) && LEGENDARIES_LIST.is_a?(Array)
      LEGENDARIES_LIST.each do |legendary_id|
        species = GameData::Species.get(legendary_id) rescue next
        bst = calcBaseStatsSum(species.id) rescue 0
        next if bst < bst_min
        candidates << { species: species.id, bst: bst, catch_rate: species.catch_rate }
      end
    end

    # High BST non-legendaries
    (1..NB_POKEMON).each do |i|
      species = GameData::Species.get(i) rescue next
      bst = calcBaseStatsSum(species.id) rescue 0
      next if bst < bst_min
      next if candidates.any? { |c| c[:species] == species.id }

      has_prevo = species.respond_to?(:get_previous_species) ? species.get_previous_species != species.id : false
      next if has_prevo

      candidates << { species: species.id, bst: bst, catch_rate: species.catch_rate }
    end

    if candidates.empty?
      pbMessage(_INTL("No eligible Pokemon found for Shiny Legendary Egg!"))
      return
    end

    # Inverted catch rate weighting (rarer Pokemon more likely)
    max_catch = candidates.map { |c| c[:catch_rate] }.max
    weighted = candidates.map { |c| { species: c[:species], weight: max_catch - c[:catch_rate] + 3 } }

    total_weight = weighted.sum { |c| c[:weight] }
    roll = rand(total_weight)
    cumulative = 0
    selected = nil
    weighted.each do |c|
      cumulative += c[:weight]
      if roll < cumulative
        selected = c[:species]
        break
      end
    end
    selected ||= candidates.first[:species]

    # Create shiny legendary egg
    pokemon = Pokemon.new(selected, 1)
    pokemon.shiny = true
    pokemon.name = _INTL("Egg")
    pokemon.steps_to_hatch = pokemon.species_data.hatch_steps rescue 10240
    pokemon.hatched_map = 0
    pokemon.obtain_method = 1
    pokemon.obtain_text = "Legendary Boss Reward Egg"
    pokemon.time_form_set = nil
    pokemon.form = 0 if pokemon.isSpecies?(:SHAYMIN)
    pokemon.heal

    pbAddPokemon(pokemon, 1, true, true) if defined?(pbAddPokemon)
    pbMessage(_INTL("You received a Shiny Legendary Egg!"))
    MultiplayerDebug.info("BOSS-LOOT", "Gave Shiny Legendary Egg: #{selected}") if defined?(MultiplayerDebug)
  rescue => e
    MultiplayerDebug.error("BOSS-LOOT", "Legendary egg error: #{e.message}") if defined?(MultiplayerDebug)
    pbMessage(_INTL("Error generating Shiny Legendary Egg."))
  end

  #=============================================================================
  # Vote UI: Show Screen
  #=============================================================================
  def self.show_vote_screen
    @vote_ui = BossVoteUI.new(@options)
    @vote_ui.show
  end

  #=============================================================================
  # Vote UI: Update Selection
  #=============================================================================
  def self.update_vote_ui_selection(index)
    @vote_ui&.set_selection(index)
  end

  #=============================================================================
  # Vote UI: Update Timer
  #=============================================================================
  def self.update_timer_display(remaining)
    @vote_ui&.set_timer(remaining)
  end

  #=============================================================================
  # Vote UI: Show Results
  #=============================================================================
  def self.show_vote_results(counts, winner)
    @vote_ui&.show_results(counts, winner)
    # Brief pause to show results
    Graphics.update
    pbWait(60)  # 1 second
  end

  #=============================================================================
  # Vote UI: Hide Screen
  #=============================================================================
  def self.hide_vote_screen
    @vote_ui&.dispose
    @vote_ui = nil
  end

  #=============================================================================
  # Check if Voting is Active
  #=============================================================================
  def self.voting_active?
    @voting_active
  end

  #=============================================================================
  # Cancel Voting (if battle ends prematurely)
  #=============================================================================
  def self.cancel
    @voting_active = false
    hide_vote_screen
  end
end

#===============================================================================
# Vote UI Sprite Class
#===============================================================================
class BossVoteUI
  def initialize(options)
    @options = options
    @selection = nil
    @sprites = {}
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999

    create_sprites
  end

  def create_sprites
    # Semi-transparent background
    @sprites[:bg] = Sprite.new(@viewport)
    @sprites[:bg].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites[:bg].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 180))

    # Title
    @sprites[:title] = Sprite.new(@viewport)
    @sprites[:title].bitmap = Bitmap.new(Graphics.width, 50)
    @sprites[:title].bitmap.font.size = 28
    @sprites[:title].bitmap.font.bold = true
    pbDrawOutlineText(@sprites[:title].bitmap, 0, 10, Graphics.width, 40, "Choose Your Reward!", Color.new(255, 220, 100), Color.new(0, 0, 0), 1)
    @sprites[:title].y = 30

    # Timer
    @sprites[:timer] = Sprite.new(@viewport)
    @sprites[:timer].bitmap = Bitmap.new(100, 40)
    @sprites[:timer].x = Graphics.width / 2 - 50
    @sprites[:timer].y = 75

    # Option boxes (3 columns)
    @box_width = 150
    @box_height = 160
    spacing = 30
    start_x = (Graphics.width - (@box_width * 3 + spacing * 2)) / 2
    @start_y = 120

    3.times do |i|
      x = start_x + i * (@box_width + spacing)

      # Box background
      @sprites["box_#{i}"] = Sprite.new(@viewport)
      @sprites["box_#{i}"].bitmap = Bitmap.new(@box_width, @box_height)
      @sprites["box_#{i}"].bitmap.fill_rect(0, 0, @box_width, @box_height, Color.new(40, 40, 60))
      @sprites["box_#{i}"].bitmap.fill_rect(2, 2, @box_width - 4, @box_height - 4, Color.new(60, 60, 80))
      @sprites["box_#{i}"].x = x
      @sprites["box_#{i}"].y = @start_y

      # Item icon (48x48, centered horizontally)
      if @options[i]
        item_id = @options[i][:item]
        icon_x = x + (@box_width - 48) / 2
        icon_y = @start_y + 8
        if BossConfig.special_reward?(item_id)
          # Special reward: draw an egg sprite
          egg_path = pbResolveBitmap("Graphics/Pokemon/Eggs/000") ||
                     pbResolveBitmap("Graphics/Pokemon/Eggs/000_icon")
          if egg_path
            @sprites["icon_#{i}"] = Sprite.new(@viewport)
            @sprites["icon_#{i}"].bitmap = Bitmap.new(egg_path)
            @sprites["icon_#{i}"].x = icon_x
            @sprites["icon_#{i}"].y = icon_y
          end
        else
          @sprites["icon_#{i}"] = ItemIconSprite.new(icon_x, icon_y, item_id, @viewport)
        end
      end

      # Item info text (drawn below the icon)
      @sprites["item_#{i}"] = Sprite.new(@viewport)
      @sprites["item_#{i}"].bitmap = Bitmap.new(@box_width, @box_height)
      @sprites["item_#{i}"].x = x
      @sprites["item_#{i}"].y = @start_y

      draw_option(i)
    end

    # Instructions
    @sprites[:instructions] = Sprite.new(@viewport)
    @sprites[:instructions].bitmap = Bitmap.new(Graphics.width, 40)
    @sprites[:instructions].bitmap.font.size = 18
    pbDrawOutlineText(@sprites[:instructions].bitmap, 0, 10, Graphics.width, 30, "Press 1, 2, or 3 to vote", Color.new(200, 200, 200), Color.new(0, 0, 0), 1)
    @sprites[:instructions].y = @start_y + @box_height + 20
  end

  def draw_option(index)
    return unless @options[index]

    bitmap = @sprites["item_#{index}"].bitmap
    bitmap.clear

    opt = @options[index]
    item_id = opt[:item]
    qty = opt[:qty]
    rarity = opt[:rarity]

    # Text starts below the 48px icon area + padding
    text_y = 58

    # Item name
    item_name = if BossConfig.special_reward?(item_id)
                  BossConfig.special_reward_name(item_id)
                else
                  GameData::Item.get(item_id).name rescue item_id.to_s
                end
    bitmap.font.size = 16
    bitmap.font.bold = true
    pbDrawOutlineText(bitmap, 5, text_y, 140, 25, item_name, Color.new(255, 255, 255), Color.new(0, 0, 0), 1)

    # Quantity
    bitmap.font.size = 20
    bitmap.font.bold = true
    pbDrawOutlineText(bitmap, 5, text_y + 26, 140, 30, "x#{qty}", Color.new(255, 220, 100), Color.new(0, 0, 0), 1)

    # Rarity
    rarity_color = case rarity
      when :legendary then Color.new(255, 180, 0)
      when :epic then Color.new(180, 100, 255)
      when :rare then Color.new(100, 180, 255)
      when :uncommon then Color.new(100, 255, 100)
      else Color.new(200, 200, 200)
    end
    bitmap.font.size = 14
    pbDrawOutlineText(bitmap, 5, text_y + 76, 140, 20, rarity.to_s.upcase, rarity_color, Color.new(0, 0, 0), 1)

    # Number indicator
    bitmap.font.size = 24
    bitmap.font.bold = true
    pbDrawOutlineText(bitmap, 5, text_y + 50, 30, 30, "#{index + 1}", Color.new(150, 150, 150), Color.new(0, 0, 0), 0)
  end

  def set_selection(index)
    @selection = index

    # Update box borders to show selection
    3.times do |i|
      box = @sprites["box_#{i}"]
      box.bitmap.clear
      if i == index
        box.bitmap.fill_rect(0, 0, @box_width, @box_height, Color.new(255, 220, 100))
        box.bitmap.fill_rect(3, 3, @box_width - 6, @box_height - 6, Color.new(60, 60, 80))
      else
        box.bitmap.fill_rect(0, 0, @box_width, @box_height, Color.new(40, 40, 60))
        box.bitmap.fill_rect(2, 2, @box_width - 4, @box_height - 4, Color.new(60, 60, 80))
      end
    end
  end

  def set_timer(seconds)
    bitmap = @sprites[:timer].bitmap
    bitmap.clear
    bitmap.font.size = 32
    bitmap.font.bold = true

    color = seconds <= 3 ? Color.new(255, 100, 100) : Color.new(255, 255, 255)
    pbDrawOutlineText(bitmap, 0, 0, 100, 40, "#{[seconds, 0].max}", color, Color.new(0, 0, 0), 1)
  end

  def show_results(counts, winner)
    # Highlight winner
    3.times do |i|
      box = @sprites["box_#{i}"]
      box.bitmap.clear
      if i == winner
        box.bitmap.fill_rect(0, 0, @box_width, @box_height, Color.new(100, 255, 100))
        box.bitmap.fill_rect(3, 3, @box_width - 6, @box_height - 6, Color.new(60, 80, 60))
      else
        box.bitmap.fill_rect(0, 0, @box_width, @box_height, Color.new(60, 60, 60))
        box.bitmap.fill_rect(2, 2, @box_width - 4, @box_height - 4, Color.new(40, 40, 40))
      end

      # Show vote counts
      item_bmp = @sprites["item_#{i}"].bitmap
      item_bmp.font.size = 16
      pbDrawOutlineText(item_bmp, 100, @box_height - 30, 45, 20, "#{counts[i]} votes", Color.new(200, 200, 200), Color.new(0, 0, 0), 2)
    end

    # Update title
    @sprites[:title].bitmap.clear
    @sprites[:title].bitmap.font.size = 28
    @sprites[:title].bitmap.font.bold = true
    pbDrawOutlineText(@sprites[:title].bitmap, 0, 10, Graphics.width, 40, "Winner!", Color.new(100, 255, 100), Color.new(0, 0, 0), 1)
  end

  def show
    @sprites.each_value { |s| s.visible = true if s }
  end

  def hide
    @sprites.each_value { |s| s.visible = false if s }
  end

  def dispose
    @sprites.each_value { |s| s.dispose if s && !s.disposed? }
    @sprites.clear
    @viewport.dispose if @viewport && !@viewport.disposed?
  end
end

#===============================================================================
# Input Handler for Vote Selection
#===============================================================================
module BossLootInput
  def self.update
    return unless BossLootSystem.voting_active?

    # Check for number key inputs (1, 2, 3)
    if Input.triggerex?(:N1) || Input.triggerex?(0x31)  # Key '1'
      BossLootSystem.cast_vote(0)
    elsif Input.triggerex?(:N2) || Input.triggerex?(0x32)  # Key '2'
      BossLootSystem.cast_vote(1)
    elsif Input.triggerex?(:N3) || Input.triggerex?(0x33)  # Key '3'
      BossLootSystem.cast_vote(2)
    end
  end
end

#===============================================================================
# Hook into Battle End to Trigger Loot Voting
#===============================================================================
class PokeBattle_Battle
  alias boss_loot_pbEndOfBattle pbEndOfBattle

  def pbEndOfBattle
    # Check if a boss was defeated
    boss_defeated = nil
    @battlers.each do |b|
      next unless b && b.pokemon&.is_boss? && b.fainted?
      boss_defeated = b.pokemon
      break
    end

    # Start loot voting if boss was defeated
    if boss_defeated && @decision == 1  # Player won
      BossLootSystem.start_vote(self, boss_defeated)

      # Run voting loop
      while BossLootSystem.voting_active?
        Graphics.update
        Input.update
        BossLootInput.update
        BossLootSystem.update
      end
    end

    boss_loot_pbEndOfBattle
  end
end

#===============================================================================
# Network Handler for Receiving Votes
#===============================================================================
# Add this to your multiplayer message handler:
#
# if data.start_with?("BOSS_VOTE:")
#   payload = MiniJSON.parse(data.sub("BOSS_VOTE:", ""))
#   sid = payload["sid"]
#   vote = payload["vote"]
#   BossLootSystem.receive_vote(sid, vote)
# end
