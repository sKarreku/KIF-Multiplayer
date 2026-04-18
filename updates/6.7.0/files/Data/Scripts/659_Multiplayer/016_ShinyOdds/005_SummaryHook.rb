#===============================================================================
# MODULE: Shiny Odds Tracking — Summary Screen Display
#===============================================================================
# Hooks drawPageTwo (Trainer Memo) to:
#   1. Fix text clipping by redrawing memo at y=84 (original y=82 clips tops)
#   2. Append shiny odds / family rate for server-stamped shiny Pokemon
#
# Display format (below the characteristic line):
#   Shiny Odds: N/65536
#   Family: N/100
#
# Only shows for shiny Pokemon with shiny_odds_stamped == true.
#===============================================================================

class PokemonSummary_Scene
  alias shiny_odds_original_drawPageTwo drawPageTwo

  def drawPageTwo
    # Run the original chain (original + Family hook)
    shiny_odds_original_drawPageTwo

    overlay = @sprites["overlay"].bitmap

    # Clear the memo text area (right panel) and redraw at y=84 to fix clipping
    overlay.fill_rect(232, 80, 268, 300, Color.new(0, 0, 0, 0))

    # Rebuild the memo string (same logic as original drawPageTwo)
    memo = ""
    showNature = !@pokemon.shadowPokemon? || @pokemon.heartStage > 3
    if showNature
      natureName = @pokemon.nature.name
      memo += _INTL("<c3=F83820,E09890>{1}<c3=404040,B0B0B0> nature.\n", natureName)
    end
    if @pokemon.timeReceived
      date  = @pokemon.timeReceived.day
      month = pbGetMonthName(@pokemon.timeReceived.mon)
      year  = @pokemon.timeReceived.year
      memo += _INTL("<c3=404040,B0B0B0>{1} {2}, {3}\n", date, month, year)
    end
    mapname = pbGetMapNameFromId(@pokemon.obtain_map)
    mapname = @pokemon.obtain_text if @pokemon.obtain_text && !@pokemon.obtain_text.empty?
    mapname = _INTL("Faraway place") if nil_or_empty?(mapname)
    memo += sprintf("<c3=F83820,E09890>%s\n", mapname)
    mettext = [_INTL("Met at Lv. {1}.", @pokemon.obtain_level),
               _INTL("Egg received."),
               _INTL("Traded at Lv. {1}.", @pokemon.obtain_level),
               "",
               _INTL("Had a fateful encounter at Lv. {1}.", @pokemon.obtain_level)
    ][@pokemon.obtain_method]
    memo += sprintf("<c3=404040,B0B0B0>%s\n", mettext) if mettext && mettext != ""
    if @pokemon.obtain_method == 1
      if @pokemon.timeEggHatched
        date  = @pokemon.timeEggHatched.day
        month = pbGetMonthName(@pokemon.timeEggHatched.mon)
        year  = @pokemon.timeEggHatched.year
        memo += _INTL("<c3=404040,B0B0B0>{1} {2}, {3}\n", date, month, year)
      end
      mapname = pbGetMapNameFromId(@pokemon.hatched_map)
      mapname = _INTL("Faraway place") if nil_or_empty?(mapname)
      memo += sprintf("<c3=F83820,E09890>%s\n", mapname)
      memo += _INTL("<c3=404040,B0B0B0>Egg hatched.\n")
    else
      memo += "\n"
    end
    if showNature
      best_stat = nil
      best_iv = 0
      stats_order = [:HP, :ATTACK, :DEFENSE, :SPEED, :SPECIAL_ATTACK, :SPECIAL_DEFENSE]
      start_point = @pokemon.personalID % stats_order.length
      for i in 0...stats_order.length
        stat = stats_order[(i + start_point) % stats_order.length]
        if !best_stat || @pokemon.iv[stat] > @pokemon.iv[best_stat]
          best_stat = stat
          best_iv = @pokemon.iv[best_stat]
        end
      end
      characteristics = {
        :HP              => [_INTL("Loves to eat."),       _INTL("Takes plenty of siestas."),
                             _INTL("Nods off a lot."),     _INTL("Scatters things often."),
                             _INTL("Likes to relax.")],
        :ATTACK          => [_INTL("Proud of its power."), _INTL("Likes to thrash about."),
                             _INTL("A little quick tempered."), _INTL("Likes to fight."),
                             _INTL("Quick tempered.")],
        :DEFENSE         => [_INTL("Sturdy body."),        _INTL("Capable of taking hits."),
                             _INTL("Highly persistent."),  _INTL("Good endurance."),
                             _INTL("Good perseverance.")],
        :SPECIAL_ATTACK  => [_INTL("Highly curious."),     _INTL("Mischievous."),
                             _INTL("Thoroughly cunning."), _INTL("Often lost in thought."),
                             _INTL("Very finicky.")],
        :SPECIAL_DEFENSE => [_INTL("Strong willed."),      _INTL("Somewhat vain."),
                             _INTL("Strongly defiant."),   _INTL("Hates to lose."),
                             _INTL("Somewhat stubborn.")],
        :SPEED           => [_INTL("Likes to run."),       _INTL("Alert to sounds."),
                             _INTL("Impetuous and silly."), _INTL("Somewhat of a clown."),
                             _INTL("Quick to flee.")]
      }
      memo += sprintf("<c3=404040,B0B0B0>%s\n", characteristics[best_stat][best_iv % 5])
    end

    # Append shiny odds if applicable
    if @pokemon && @pokemon.respond_to?(:shiny_catch_odds) && @pokemon.shiny_catch_odds &&
       @pokemon.respond_to?(:shiny_odds_stamped) && @pokemon.shiny_odds_stamped &&
       (@pokemon.shiny? || (@pokemon.respond_to?(:fakeshiny?) && @pokemon.fakeshiny?))
      eff = @pokemon.shiny_catch_odds

      # Build context label for display
      ctx = @pokemon.respond_to?(:shiny_catch_context) ? @pokemon.shiny_catch_context : nil
      ctx_label = case ctx
        when "wild"      then " (Wild)"
        when "pokeradar" then " (PokeRadar)"
        when "breeding"  then " (Bred)"
        when "kegg"      then " (K-Egg)"
        when "gamble"    then " (Gamble)"
        when "resonance" then " (Resonance)"
        else ""
      end

      memo += _INTL("<c3=B464FF,6432A0>Shiny Odds: <c3=404040,B0B0B0>{1}/65536{2}\n", eff, ctx_label)

      if @pokemon.respond_to?(:family_catch_rate) && @pokemon.family_catch_rate &&
         @pokemon.respond_to?(:has_family_data?) && @pokemon.has_family_data?
        memo += _INTL("<c3=B464FF,6432A0>Family: <c3=404040,B0B0B0>{1}/100\n", @pokemon.family_catch_rate)
      end
    end

    # Draw at y=84 (2px lower than original y=82 to prevent top clipping)
    drawFormattedTextEx(overlay, 232, 84, 268, memo)
  end
end
