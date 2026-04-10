#===============================================================================
# MP Settings File
#===============================================================================
# Persists Multiplayer settings to a plain-text file (mp_settings.txt) that
# lives next to the save file.  This is intentionally separate from Game.rxdata
# so that settings survive save resets, cannot corrupt save data, and are shared
# across all save slots.
#
# Load order:
#   - Game.load (continue)    → SaveData.load_all_values → MPSettingsFile.load
#   - Game.start_new          → SaveData.load_new_game_values → MPSettingsFile.load
# Save order:
#   - MultiplayerOptScene closes  → MPSettingsFile.save
#   - apply_mp_settings (sync)    → MPSettingsFile.save
#===============================================================================

module MPSettingsFile
  # Same directory as Game.rxdata so the file is always findable.
  FILE_PATH = SaveData::FILE_PATH.sub("Game.rxdata", "mp_settings.txt")

  # All mp_ keys managed by this system (must match PokemonSystem attr_accessors).
  KEYS = %w[
    mp_family_enabled
    mp_family_abilities_enabled
    mp_family_rate
    mp_family_font_enabled
    mp_coop_timeout_disabled
    mp_bosses_disabled
    mp_skip_trainer_anim
    mp_ebdx_zoom_disabled
    mp_ebdx_enabled
    mp_stat_stage_overlay
    mp_overworld_zoom
    mp_family_outline_animated
  ].freeze

  # Write current $PokemonSystem mp_ values to the txt file.
  def self.save
    return unless $PokemonSystem
    lines = ["# KIF Multiplayer settings — auto-saved, loaded on every game start"]
    KEYS.each do |k|
      val = $PokemonSystem.send(k) rescue nil
      next if val.nil?
      lines << "#{k}=#{val.to_i}"
    end
    File.open(FILE_PATH, "w") { |f| f.puts lines }
    MultiplayerDebug.info("MP-FILE", "Saved #{FILE_PATH}") if defined?(MultiplayerDebug)
  rescue => e
    echoln "[MPSettingsFile] Save failed: #{e.message}" rescue nil
  end

  # Read the txt file and apply values to $PokemonSystem, overriding whatever
  # the save file (or defaults) set.  Missing keys keep their current values.
  def self.load_and_apply
    return unless $PokemonSystem
    unless File.exist?(FILE_PATH)
      MultiplayerDebug.info("MP-FILE", "#{FILE_PATH} not found — using defaults") if defined?(MultiplayerDebug)
      return
    end
    File.readlines(FILE_PATH).each do |line|
      line = line.strip
      next if line.empty? || line.start_with?("#")
      key, val = line.split("=", 2)
      next unless key && val && KEYS.include?(key)
      $PokemonSystem.send(:"#{key}=", val.to_i) if $PokemonSystem.respond_to?(:"#{key}=")
    end
    MultiplayerDebug.info("MP-FILE", "Loaded #{FILE_PATH}") if defined?(MultiplayerDebug)
  rescue => e
    echoln "[MPSettingsFile] Load failed: #{e.message}" rescue nil
  end
end

#===============================================================================
# Hook Game.load (Continue) — fires after $PokemonSystem is restored from save
#===============================================================================
module Game
  class << self
    alias mp_file_orig_load load
    def load(save_data)
      mp_file_orig_load(save_data)
      MPSettingsFile.load_and_apply
    end

    alias mp_file_orig_start_new start_new
    def start_new(*args)
      mp_file_orig_start_new(*args)
      MPSettingsFile.load_and_apply
    end
  end
end

#===============================================================================
# Hook MultiplayerOptScene — auto-save when the MP options menu closes
#===============================================================================
class MultiplayerOptScene
  alias mp_file_orig_pbEndScene pbEndScene if method_defined?(:pbEndScene)
  def pbEndScene
    result = mp_file_orig_pbEndScene if defined?(mp_file_orig_pbEndScene)
    MPSettingsFile.save
    result
  end
end

#===============================================================================
# Hook apply_mp_settings — save after a network settings sync
#===============================================================================
module MultiplayerSettingsSync
  module_function

  alias mp_file_orig_apply_mp_settings apply_mp_settings if method_defined?(:apply_mp_settings)
  def apply_mp_settings(settings)
    mp_file_orig_apply_mp_settings(settings)
    MPSettingsFile.save
  end
end

MultiplayerDebug.info("MP-FILE", "MPSettingsFile loaded — path: #{MPSettingsFile::FILE_PATH}") if defined?(MultiplayerDebug)
