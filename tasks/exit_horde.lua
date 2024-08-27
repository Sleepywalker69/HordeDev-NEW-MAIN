local utils = require "core.utils"
local settings = require "core.settings"
local enums = require "data.enums"
local tracker = require "core.tracker"
local open_chests_task = require "tasks.open_chests"
local explorer = require "core.explorer"

-- Reference the position from horde.lua
local horde_boss_room_position = vec3:new(-36.17675, -36.3222, 2.200)

exit_horde_task = {
    name = "Exit Horde",
    delay_start_time = nil,
    moved_to_center = false,
    no_gold_chest_count = 0,

    shouldExecute = function()
        return utils.player_in_zone("S05_BSK_Prototype02")
            and utils.get_stash() ~= nil
            and (tracker.gold_chest_opened or not utils.get_chest(enums.chest_types["GOLD"])) 
    end,

    Execute = function(self)
        local current_time = get_time_since_inject()

        -- First, move to the center if not already there
        if not self.moved_to_center then
            if utils.distance_to(horde_boss_room_position) > 2 then
                console.print("Moving to boss room position.")
                explorer:set_custom_target(horde_boss_room_position)
                explorer:move_to_target()
                return
            else
                self.moved_to_center = true
                console.print("Reached Central Room Position.")
            end
        end

        -- Check for the presence of the gold chest
        local gold_chest = utils.get_chest(enums.chest_types["GOLD"])
        if not gold_chest then
            console.print("No gold chest found. Exiting.")
            self.no_gold_chest_count = self.no_gold_chest_count + 1
            
            if self.no_gold_chest_count >= 5 then
                console.print("No gold chest found 5 times. Triggering new horde start.")
                self:reset()
                self:full_reset()
                tracker.force_horde_start = true
                return
            end
            
            return
        end

        -- Reset the counter if a gold chest is found
        self.no_gold_chest_count = 0

        -- Proceed with exit procedure
        if not self.delay_start_time then
            self.delay_start_time = current_time
            console.print("Starting 5-second delay before initiating exit procedure")
            return
        end

        local delay_elapsed_time = current_time - self.delay_start_time
        if delay_elapsed_time < 5 then
            console.print(string.format("Waiting to start exit procedure. Time remaining: %.2f seconds", 5 - delay_elapsed_time))
            return
        end

        if not tracker.exit_horde_start_time then
            console.print("Starting 5-second timer before exiting Horde")
            tracker.exit_horde_start_time = current_time
        end

        local elapsed_time = current_time - tracker.exit_horde_start_time
        if elapsed_time >= 10 then
            console.print("10-second timer completed. Resetting all dungeons")
            reset_all_dungeons()
            self:reset()
            self:full_reset()
        else
            console.print(string.format("Waiting to exit Horde. Time remaining: %.2f seconds", 10 - elapsed_time))
        end
    end,

    reset = function(self)
        console.print("Resetting exit horde task")
        tracker.exit_horde_start_time = nil
        tracker.exit_horde_completion_time = get_time_since_inject()
        tracker.horde_opened = false
        tracker.start_dungeon_time = nil
        self.delay_start_time = nil
        self.moved_to_center = false
        self.no_gold_chest_count = 0
    end,

    full_reset = function(self)
        console.print("Performing full reset for new horde start")
        -- Reset all relevant tracker flags
        tracker.ga_chest_opened = false
        tracker.selected_chest_opened = false
        tracker.gold_chest_opened = false
        tracker.finished_chest_looting = false
        tracker.has_salvaged = false
        tracker.has_entered = false
        tracker.first_run = true
        tracker.exit_horde_completed = false
        tracker.wave_start_time = 0
        tracker.needs_salvage = false

        -- Reset open_chests_task
        open_chests_task:reset()

        -- Reset explorer if necessary
        explorer:clear_path_and_target()

        -- Any other task-specific resets can be added here
    end
}

return exit_horde_task