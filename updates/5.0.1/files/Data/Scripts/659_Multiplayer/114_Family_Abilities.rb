#===============================================================================
# MODULE: Family Boosted Abilities - GameData Registration
#===============================================================================
# Registers the 8 boosted Family talents as GameData::Ability entries.
# Hook into load() to register after DATA is populated from .dat file.
#===============================================================================

if defined?(GameData) && defined?(GameData::Ability)
  class GameData::Ability
    class << self
      alias family_talent_original_load load
      def load
        family_talent_original_load

        # Register boosted abilities AFTER DATA loaded from abilities.dat
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("FAMILY-TALENT", "Post-load: Registering 8 boosted abilities...")
        end

        register({
          id: :PANMORPHOSIS,
          id_number: 900,
          name: "Panmorphosis",
          description: "Changes type to match moves and resist attacks."
        })

        register({
          id: :VEILBREAKER,
          id_number: 901,
          name: "Veilbreaker",
          description: "Bypasses all battle conditions and protections."
        })

        register({
          id: :VOIDBORNE,
          id_number: 902,
          name: "Voidborne",
          description: "Ground immunity and immune to special attacks."
        })

        register({
          id: :VITALREBIRTH,
          id_number: 903,
          name: "Vital Rebirth",
          description: "Heals 50% HP and cures status on switch out."
        })

        register({
          id: :IMMOVABLE,
          id_number: 904,
          name: "Immovable",
          description: "Can only faint at 1 HP. Heals to full on first 1 HP."
        })

        register({
          id: :INDOMITABLE,
          id_number: 905,
          name: "Indomitable",
          description: "Ignores abilities, stat changes, and defenses."
        })

        register({
          id: :COSMICBLESSING,
          id_number: 906,
          name: "Cosmic Blessing",
          description: "Secondary effects always activate."
        })

        register({
          id: :MINDSHATTER,
          id_number: 907,
          name: "Mindshatter",
          description: "Lowers Attack and Sp. Attack on switch-in."
        })

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("FAMILY-TALENT", "  Registered. DATA[:PANMORPHOSIS] = #{DATA[:PANMORPHOSIS].inspect}")
        end
      end
    end

    alias family_talent_original_name name
    def name
      translated = family_talent_original_name
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("ABILITY-NAME", "=== name() called ===")
        MultiplayerDebug.info("ABILITY-NAME", "  @id: #{@id}")
        MultiplayerDebug.info("ABILITY-NAME", "  @id_number: #{@id_number}")
        MultiplayerDebug.info("ABILITY-NAME", "  translated: '#{translated}'")
        MultiplayerDebug.info("ABILITY-NAME", "  @real_name: '#{@real_name}'")
      end
      return translated if translated && !translated.empty?
      return @real_name
    end

    alias family_talent_original_description description
    def description
      translated = family_talent_original_description
      return translated if translated && !translated.empty?
      return @real_description
    end
  end
else
  if defined?(MultiplayerDebug)
    MultiplayerDebug.error("FAMILY-TALENT", "GameData::Ability not available at load time")
  end
end
