#===============================================================================
# Boss Pokemon System - EBDX UI Hooks
#===============================================================================
# This file MUST load AFTER 660_EBDX (hence the 661_ prefix)
# Hooks into DataBoxEBDX to hide it for bosses and show boss UI instead.
#===============================================================================

MultiplayerDebug.info("BOSS-UI", "Loading 661_BossUIHooks/001_Boss_UI_EBDX.rb...") if defined?(MultiplayerDebug)

#===============================================================================
# Hook into EBDX DataBox to hide it for bosses and show boss UI
#===============================================================================
if defined?(DataBoxEBDX)
  MultiplayerDebug.info("BOSS-UI", "DataBoxEBDX found, applying hooks...") if defined?(MultiplayerDebug)

  class DataBoxEBDX
    # Hook into render (initial setup)
    alias boss_ui_ebdx_render render

    def render
      # Check if this battler is a boss
      if @battler&.pokemon&.is_boss?
        MultiplayerDebug.info("BOSS-UI", "render: Battler #{@battler.index} is BOSS, hiding EBDX databox") if defined?(MultiplayerDebug)

        # Hide all EBDX databox sprites
        @sprites.each_value { |s| s.visible = false if s && s.respond_to?(:visible=) }

        # Create boss databox if not exists
        unless defined?(BossUIManager) && BossUIManager.has_boss_databox?(@battler)
          if defined?(BossUIManager)
            MultiplayerDebug.info("BOSS-UI", "render: Creating boss databox for battler #{@battler.index}") if defined?(MultiplayerDebug)
            BossUIManager.create_boss_databox(@viewport, @battler)
          end
        end
        return
      end

      boss_ui_ebdx_render
    end

    # Hook into refresh (data updates)
    alias boss_ui_ebdx_refresh refresh

    def refresh
      return if self.disposed?

      # Check if this battler is a boss
      if @battler&.pokemon&.is_boss?
        # Hide all EBDX databox sprites
        @sprites.each_value { |s| s.visible = false if s && s.respond_to?(:visible=) }

        # Create or update boss databox
        if defined?(BossUIManager)
          unless BossUIManager.has_boss_databox?(@battler)
            BossUIManager.create_boss_databox(@viewport, @battler)
          else
            BossUIManager.update_boss_databox(@battler)
          end
        end
        return
      end

      boss_ui_ebdx_refresh
    end

    # Hook into update (per-frame animation)
    alias boss_ui_ebdx_update update

    # Debug counter for update calls
    @@update_call_count = 0

    def update
      return if self.disposed?

      # Check if this battler is a boss
      if @battler&.pokemon&.is_boss?
        @@update_call_count += 1
        if @@update_call_count % 10 == 1 && defined?(MultiplayerDebug)
          MultiplayerDebug.info("BOSS-EBDX", "EBDX update hook ##{@@update_call_count} for boss battler #{@battler.index}")
        end

        # Keep EBDX databox hidden
        @sprites.each_value { |s| s.visible = false if s && s.respond_to?(:visible=) }

        # Call boss databox update for animations (damage fade, etc.)
        if defined?(BossUIManager)
          boss_db = BossUIManager.get_boss_databox(@battler)
          if boss_db
            boss_db.update
          else
            MultiplayerDebug.info("BOSS-EBDX", "WARNING: boss_db is nil in update!") if defined?(MultiplayerDebug)
          end
        end
        return
      end

      boss_ui_ebdx_update
    end

    # Hook into damage (red flash when hit)
    alias boss_ui_ebdx_damage damage

    def damage
      # Check if this battler is a boss
      if @battler&.pokemon&.is_boss?
        # Use boss databox damage animation instead
        if defined?(BossUIManager)
          BossUIManager.damage_boss_databox(@battler)
        end
        return
      end

      boss_ui_ebdx_damage
    end

    # Hook into animateHP (HP bar animation)
    alias boss_ui_ebdx_animateHP animateHP

    def animateHP(oldHP, newHP)
      # Check if this battler is a boss
      if @battler&.pokemon&.is_boss?
        # Use boss databox HP animation instead
        if defined?(BossUIManager)
          boss_db = BossUIManager.get_boss_databox(@battler)
          boss_db&.animateHP(oldHP, newHP)
        end
        return
      end

      boss_ui_ebdx_animateHP(oldHP, newHP)
    end

    # Expose animatingHP for boss - scene checks this to wait for animation
    alias boss_ui_ebdx_animatingHP animatingHP

    # Debug counter to avoid log spam
    @@anim_hp_check_count = 0

    def animatingHP
      # Check if this battler is a boss
      if @battler&.pokemon&.is_boss?
        if defined?(BossUIManager)
          boss_db = BossUIManager.get_boss_databox(@battler)

          # FORCE update here since the update hook might not be triggering
          boss_db&.update

          result = boss_db&.animatingHP || false

          # Debug log every 10th check
          @@anim_hp_check_count += 1
          if @@anim_hp_check_count % 10 == 1 && defined?(MultiplayerDebug)
            MultiplayerDebug.info("BOSS-EBDX", "animatingHP check ##{@@anim_hp_check_count}: result=#{result}, cur=#{boss_db&.instance_variable_get(:@currenthp).to_i rescue '?'}, end=#{boss_db&.instance_variable_get(:@endhp).to_i rescue '?'}")
          end

          return result
        end
        return false
      end

      boss_ui_ebdx_animatingHP
    end
  end

  MultiplayerDebug.info("BOSS-UI", "DataBoxEBDX hooks applied successfully!") if defined?(MultiplayerDebug)
else
  MultiplayerDebug.info("BOSS-UI", "WARNING: DataBoxEBDX not found! EBDX hooks NOT applied.") if defined?(MultiplayerDebug)
end

#===============================================================================
# Hook into EBDX Scene to reposition Ability Message for boss battles
#===============================================================================
if defined?(PokeBattle_Scene)
  class PokeBattle_Scene
    # Hook pbShowAbilitySplash to reposition for boss battles
    alias boss_ui_pbShowAbilitySplash pbShowAbilitySplash if method_defined?(:pbShowAbilitySplash)

    def pbShowAbilitySplash(battler, delay = false, logTrigger = true, abilityName = nil)
      # Call original (handles slide animation setup)
      if defined?(boss_ui_pbShowAbilitySplash)
        boss_ui_pbShowAbilitySplash(battler, delay, logTrigger, abilityName)
      end

      # During boss battles, adjust the slide target so it doesn't cover the boss databox
      if @sprites && @sprites["abilityMessage"] && battler.respond_to?(:is_boss?) && battler.is_boss?
        @sprites["abilityMessage"].y = 140
      end
    end
  end
  MultiplayerDebug.info("BOSS-UI", "PokeBattle_Scene ability splash hook applied") if defined?(MultiplayerDebug)
end

MultiplayerDebug.info("BOSS-UI", "Boss EBDX UI hooks loaded") if defined?(MultiplayerDebug)
