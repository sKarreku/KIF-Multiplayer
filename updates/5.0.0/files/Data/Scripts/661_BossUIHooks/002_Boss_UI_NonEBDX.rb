#===============================================================================
# Boss Pokemon System - Non-EBDX (Vanilla) UI Hooks
#===============================================================================
# This file hooks into PokemonDataBox (the vanilla/standard databox) to show
# boss UI instead. Only active when EBDX is NOT loaded.
#
# Key difference from EBDX: PokemonDataBox extends SpriteWrapper, which does
# NOT store viewport as @viewport. Must use self.viewport to get the correct
# viewport for creating boss sprites.
#===============================================================================

MultiplayerDebug.info("BOSS-UI", "Loading 661_BossUIHooks/002_Boss_UI_NonEBDX.rb...") if defined?(MultiplayerDebug)

#===============================================================================
# Hook PokemonDataBox unconditionally.
# When EBDX is active, DataBoxEBDX replaces PokemonDataBox entirely, so these
# hooks simply never fire. No guard needed (and guards can fail if DataBoxEBDX
# is forward-declared/stubbed somewhere).
#===============================================================================
MultiplayerDebug.info("BOSS-UI", "Applying vanilla PokemonDataBox hooks for boss UI...") if defined?(MultiplayerDebug)

class PokemonDataBox
    #---------------------------------------------------------------------------
    # Hook refresh: hide standard databox, create/update boss UI
    # Uses self.viewport (NOT @viewport which is nil in SpriteWrapper)
    #---------------------------------------------------------------------------
    alias boss_ui_vanilla_refresh refresh

    def refresh
      begin
        if @battler&.is_boss?
          MultiplayerDebug.info("BOSS-VANILLA", "refresh: battler #{@battler.index} is BOSS, hiding databox") if defined?(MultiplayerDebug)

          # Hide the standard databox and all its child sprites
          self.visible = false

          if defined?(BossUIManager)
            unless BossUIManager.has_boss_databox?(@battler)
              vp = self.viewport
              MultiplayerDebug.info("BOSS-VANILLA", "refresh: Creating boss databox, viewport=#{vp.inspect}") if defined?(MultiplayerDebug)
              BossUIManager.create_boss_databox(vp, @battler)
            else
              BossUIManager.update_boss_databox(@battler)
            end
          end
          return
        end
      rescue => e
        MultiplayerDebug.error("BOSS-VANILLA", "refresh CRASH: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}") if defined?(MultiplayerDebug)
      end
      boss_ui_vanilla_refresh
    end

    #---------------------------------------------------------------------------
    # Hook update: forward per-frame animation to boss databox
    # EBDX pattern: skip original update entirely for bosses
    #---------------------------------------------------------------------------
    alias boss_ui_vanilla_update update

    def update(frameCounter = 0)
      begin
        if @battler&.is_boss?
          # Keep standard databox hidden
          self.visible = false

          # Do NOT call original update for bosses - matches EBDX pattern
          # Original update touches internal HP/Exp animation state we don't need

          # Forward to boss databox for visual animation
          if defined?(BossUIManager)
            boss_db = BossUIManager.get_boss_databox(@battler)
            boss_db&.update
          end
          return
        end
      rescue => e
        MultiplayerDebug.error("BOSS-VANILLA", "update CRASH: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}") if defined?(MultiplayerDebug)
      end
      boss_ui_vanilla_update(frameCounter)
    end

    #---------------------------------------------------------------------------
    # Hook animateHP: forward HP animation to boss databox
    # Vanilla PokemonDataBox.animateHP takes 3 args: (oldHP, newHP, rangeHP)
    # BossDataBoxSprite.animateHP takes 2 args: (oldHP, newHP)
    #---------------------------------------------------------------------------
    alias boss_ui_vanilla_animateHP animateHP

    def animateHP(oldHP, newHP, rangeHP = nil)
      begin
        if @battler&.is_boss?
          MultiplayerDebug.info("BOSS-VANILLA", "animateHP: #{oldHP} -> #{newHP}") if defined?(MultiplayerDebug)
          if defined?(BossUIManager)
            boss_db = BossUIManager.get_boss_databox(@battler)
            if boss_db
              boss_db.damage if newHP < oldHP
              boss_db.animateHP(oldHP, newHP)
            end
          end
          # Don't call vanilla animateHP - it touches internal state we skip in update
          return
        end
      rescue => e
        MultiplayerDebug.error("BOSS-VANILLA", "animateHP CRASH: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}") if defined?(MultiplayerDebug)
      end
      boss_ui_vanilla_animateHP(oldHP, newHP, rangeHP)
    end

    #---------------------------------------------------------------------------
    # Override animatingHP: return boss databox animation state
    # The scene waits in a loop while this is true; must reflect boss UI state
    #---------------------------------------------------------------------------
    alias boss_ui_vanilla_animatingHP animatingHP

    def animatingHP
      begin
        if @battler&.is_boss? && defined?(BossUIManager)
          boss_db = BossUIManager.get_boss_databox(@battler)
          if boss_db
            # Force update here to drive the animation forward
            boss_db.update
            return boss_db.animatingHP
          end
          return false
        end
      rescue => e
        MultiplayerDebug.error("BOSS-VANILLA", "animatingHP CRASH: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}") if defined?(MultiplayerDebug)
      end
      boss_ui_vanilla_animatingHP
    end
  end

MultiplayerDebug.info("BOSS-UI", "Vanilla PokemonDataBox hooks applied successfully!") if defined?(MultiplayerDebug)

MultiplayerDebug.info("BOSS-UI", "Boss Non-EBDX UI hooks loaded") if defined?(MultiplayerDebug)
