local utils = require "core.utils"
local settings = require "core.settings"
local enums = require "data.enums"
local tracker = require "core.tracker"
local open_chests_task = require "tasks.open_chests"
local explorer = require "core.explorer"

local horde_boss_room_position = vec3:new(-36.17675, -36.3222, 2.200)

local exit_horde_states = {
    MOVE_TO_CENTER = "MOVE_TO_CENTER",
    CHECK_CHESTS = "CHECK_CHESTS",
    OPEN_CHESTS = "OPEN_CHESTS",
    WAIT_FOR_CHEST_OPENING = "WAIT_FOR_CHEST_OPENING",
    PREPARE_EXIT = "PREPARE_EXIT",
    EXIT = "EXIT",
    FORCE_EXIT = "FORCE_EXIT"
}

local exit_horde_task = {
    name = "Exit Horde",
    current_state = exit_horde_states.MOVE_TO_CENTER,
    delay_start_time = nil,
    chest_opening_start_time = nil,
    no_gold_chest_count = 0,
    force_exit_time = nil,
    max_chest_opening_time = 60, -- 1 minute timeout for chest opening

    shouldExecute = function()
        return utils.player_in_zone("S05_BSK_Prototype02")
            and utils.get_stash() ~= nil
    end,

    Execute = function(self)
        console.print("Executing exit_horde_task")
        console.print("Current state: " .. self.current_state)

        local current_time = get_time_since_inject()

        if self.current_state == exit_horde_states.MOVE_TO_CENTER then
            self:move_to_center()
        elseif self.current_state == exit_horde_states.CHECK_CHESTS then
            self:check_chests()
        elseif self.current_state == exit_horde_states.OPEN_CHESTS then
            self:open_chests()
        elseif self.current_state == exit_horde_states.WAIT_FOR_CHEST_OPENING then
            self:wait_for_chest_opening(current_time)
        elseif self.current_state == exit_horde_states.PREPARE_EXIT then
            self:prepare_exit(current_time)
        elseif self.current_state == exit_horde_states.EXIT then
            self:exit_horde(current_time)
        elseif self.current_state == exit_horde_states.FORCE_EXIT then
            self:force_exit(current_time)
        end
    end,

    move_to_center = function(self)
        if utils.distance_to(horde_boss_room_position) > 2 then
            console.print("Moving to boss room position.")
            explorer:set_custom_target(horde_boss_room_position)
            explorer:move_to_target()
        else
            console.print("Reached Central Room Position.")
            self.current_state = exit_horde_states.CHECK_CHESTS
        end
    end,

    check_chests = function(self)
        local ga_chest = utils.get_chest(enums.chest_types["GREATER_AFFIX"])
        local selected_chest = utils.get_chest(enums.chest_types[settings.selected_chest_type])
        local gold_chest = utils.get_chest(enums.chest_types["GOLD"])

        if ga_chest or selected_chest or gold_chest then
            console.print("Chests found. Moving to open chests state.")
            self.current_state = exit_horde_states.OPEN_CHESTS
            self.chest_opening_start_time = get_time_since_inject()
        else
            console.print("No chests found. Preparing to exit.")
            self.current_state = exit_horde_states.PREPARE_EXIT
        end

        if not gold_chest then
            self.no_gold_chest_count = self.no_gold_chest_count + 1
            console.print("No gold chest found. Count: " .. self.no_gold_chest_count)
            if self.no_gold_chest_count >= 5 then
                console.print("No gold chest found 5 times. Forcing exit.")
                self.current_state = exit_horde_states.FORCE_EXIT
            end
        else
            self.no_gold_chest_count = 0
        end
    end,

    open_chests = function(self)
        if not tracker.finished_chest_looting then
            console.print("Opening chests.")
            open_chests_task:Execute()
            self.current_state = exit_horde_states.WAIT_FOR_CHEST_OPENING
        else
            console.print("Chests already opened. Moving to prepare exit.")
            self.current_state = exit_horde_states.PREPARE_EXIT
        end
    end,

    wait_for_chest_opening = function(self, current_time)
        if tracker.finished_chest_looting then
            console.print("Chest opening completed. Moving to prepare exit.")
            self.current_state = exit_horde_states.PREPARE_EXIT
        elseif current_time - self.chest_opening_start_time > self.max_chest_opening_time then
            console.print("Chest opening timed out. Moving to prepare exit.")
            self.current_state = exit_horde_states.PREPARE_EXIT
        else
            console.print("Waiting for chest opening to complete...")
        end
    end,

    prepare_exit = function(self, current_time)
        if not self.delay_start_time then
            self.delay_start_time = current_time
            console.print("Starting 5-second delay before initiating exit procedure")
        end

        local delay_elapsed_time = current_time - self.delay_start_time
        if delay_elapsed_time >= 5 then
            console.print("Delay complete. Moving to exit state.")
            self.current_state = exit_horde_states.EXIT
        else
            console.print(string.format("Waiting to start exit procedure. Time remaining: %.2f seconds", 5 - delay_elapsed_time))
        end
    end,

    exit_horde = function(self, current_time)
        if not tracker.exit_horde_start_time then
            tracker.exit_horde_start_time = current_time
            console.print("Starting 10-second timer before exiting Horde")
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

    force_exit = function(self, current_time)
        if not self.force_exit_time then
            self.force_exit_time = current_time
            console.print("Forcing horde exit. Resetting all dungeons.")
            reset_all_dungeons()
        end

        local elapsed_time = current_time - self.force_exit_time
        if elapsed_time >= 10 then
            console.print("Force exit complete. Triggering new horde start.")
            tracker.force_horde_start = true
            self:reset()
            self:full_reset()
        else
            console.print(string.format("Waiting before starting new horde... %.2f seconds remaining", 10 - elapsed_time))
        end
    end,

    reset = function(self)
        console.print("Resetting exit horde task")
        self.current_state = exit_horde_states.MOVE_TO_CENTER
        self.delay_start_time = nil
        self.chest_opening_start_time = nil
        self.no_gold_chest_count = 0
        self.force_exit_time = nil
        tracker.exit_horde_start_time = nil
        tracker.exit_horde_completion_time = get_time_since_inject()
        tracker.horde_opened = false
        tracker.start_dungeon_time = nil
    end,

    full_reset = function(self)
        console.print("Performing full reset for new horde start")
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

        open_chests_task:reset()
        explorer:clear_path_and_target()
    end
}

return exit_horde_task