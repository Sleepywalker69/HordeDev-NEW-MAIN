local gui = require "gui"
local settings = {
    enabled = false,
    elites_only = false,
    pit_level = 1,
    salvage = false,
    path_angle = 10,
    reset_time = 1,
    selected_chest_type = nil,
    always_open_ga_chest = false,
    loot_mothers_gift = false,
    merry_go_round = true,
    open_chest_delay = 1.5,
    boss_kill_delay = 6,
    chest_move_attempts = 40,
}

function settings:update_settings()
    settings.enabled = gui.elements.main_toggle:get()
    settings.elites_only = gui.elements.elite_only_toggle:get()
    settings.salvage = gui.elements.salvage_toggle:get()
    settings.path_angle = gui.elements.path_angle_slider:get()
    settings.selected_chest_type = gui.elements.chest_type_selector:get()
    settings.always_open_ga_chest = gui.elements.always_open_ga_chest:get()
    settings.loot_mothers_gift = gui.elements.loot_mothers_gift:get()
    settings.merry_go_round = gui.elements.merry_go_round:get()
    settings.open_chest_delay = gui.elements.open_chest_delay:get()
    settings.boss_kill_delay = gui.elements.boss_kill_delay:get()
    settings.chest_move_attempts = gui.elements.chest_move_attempts:get()
end

return settings