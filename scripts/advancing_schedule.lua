-- Durations are simulation ticks. No wall-clock or kill-count dependencies.
local schedule = {}
schedule.SECOND = 60
schedule.NEST_INTERVAL = 20 * 60
schedule.NEST_CAP = 30

function schedule.wave_duration(wave)
    return (wave > 0 and wave % 60 == 0 and 10 or 2) * 60 * 60
end

function schedule.break_duration(wave)
    if wave <= 0 or wave % 20 ~= 0 then return 0 end
    return (wave % 60 == 0 and 30 or 15) * 60 * 60
end

-- Returns one transition at a time. Persisted fields make reloads idempotent.
function schedule.transition(state, tick)
    if state.break_until_tick then
        if tick < state.break_until_tick then return "rest" end
        state.break_until_tick = nil
        state.break_area = nil
        state.last_recovery_wave = state.wave_number
        state.next_wave_tick = tick
        return "wave"
    end
    if tick < state.next_wave_tick then return "combat" end
    local duration = schedule.break_duration(state.wave_number)
    if duration > 0 and state.last_recovery_wave ~= state.wave_number then
        state.break_until_tick = tick + duration
        state.next_wave_tick = state.break_until_tick
        return "break"
    end
    return "wave"
end

return schedule
