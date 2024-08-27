local utils = require "core.utils"
local settings = require "core.settings"
local enums = require "data.enums"
local tracker = require "core.tracker"
local explorer = require "core.explorer"

local chest_state = {
    INIT = "INIT",
    MOVING_TO_AETHER = "MOVING_TO_AETHER",
    COLLECTING_AETHER = "COLLECTING_AETHER",
    SELECTING_CHEST = "SELECTING_CHEST",
    MOVING_TO_CHEST = "MOVING_TO_CHEST",
    OPENING_CHEST = "OPENING_CHEST",
    WAITING_FOR_VFX = "WAITING_FOR_VFX",
    FINISHED = "FINISHED",
    PAUSED_FOR_SALVAGE = "PAUSED_FOR_SALVAGE",
}

local chest_order = {"GREATER_AFFIX", "SELECTED", "GOLD"}

local open_chests_task = {
    name = "Open Chests",
    current_state = chest_state.INIT,
    current_chest_type = nil,
    current_chest_index = nil,
    failed_attempts = 0,
    max_attempts = 3,
    state_before_pause = nil,
    move_attempts = 0,
    max_move_attempts = 60,
    move_cooldown = 0,
    chests_opened = {},
    current_chest_order = {},

    shouldExecute = function()
        local in_correct_zone = utils.player_in_zone("S05_BSK_Prototype02")

        if not in_correct_zone then
            console.print("Not in correct zone for chest opening")
            return false
        end

        if tracker.needs_salvage then
            console.print("Needs salvage, not opening chests")
            return false
        end

        if tracker.finished_chest_looting then
            console.print("Chest looting already finished")
            return false
        end

        console.print("Should execute chest opening")
        return true
    end,

    Execute = function(self)
        console.print("Executing open_chests_task")
        console.print("Current state: " .. self.current_state)

        if tracker.needs_salvage then
            if self.current_state ~= chest_state.PAUSED_FOR_SALVAGE then
                self.state_before_pause = self.current_state
                self.current_state = chest_state.PAUSED_FOR_SALVAGE
                console.print("Pausing chest opening for salvage")
            end
            return
        elseif self.current_state == chest_state.PAUSED_FOR_SALVAGE then
            self.current_state = self.state_before_pause
            self.state_before_pause = nil
            console.print("Resuming chest opening after salvage")
        end

        if self.current_state == chest_state.FINISHED then
            self:finish_chest_opening()
        elseif self.current_state == chest_state.INIT then
            self:init_chest_opening()
        elseif self.current_state == chest_state.MOVING_TO_AETHER then
            self:move_to_aether()
        elseif self.current_state == chest_state.COLLECTING_AETHER then
            self:collect_aether()
        elseif self.current_state == chest_state.SELECTING_CHEST then
            self:select_chest()
        elseif self.current_state == chest_state.MOVING_TO_CHEST then
            self:move_to_chest()
        elseif self.current_state == chest_state.OPENING_CHEST then
            self:open_chest()
        elseif self.current_state == chest_state.WAITING_FOR_VFX then
            self:wait_for_vfx()
        end
    end,

    init_chest_opening = function(self)
        console.print("Initializing chest opening")
        local aether_bomb = utils.get_aether_actor()
        if aether_bomb then
            self.current_state = chest_state.MOVING_TO_AETHER
            return
        end

        console.print("settings.always_open_ga_chest: " .. tostring(settings.always_open_ga_chest))
        console.print("tracker.ga_chest_opened: " .. tostring(tracker.ga_chest_opened))
        console.print("settings.selected_chest_type: " .. tostring(settings.selected_chest_type))

        local chest_type_map = {"GEAR", "MATERIALS", "GOLD"}
        self.selected_chest_type = chest_type_map[settings.selected_chest_type + 1]

        self.current_chest_order = {}
        if settings.always_open_ga_chest and not tracker.ga_chest_opened then
            table.insert(self.current_chest_order, "GREATER_AFFIX")
        end
        if self.selected_chest_type ~= "GOLD" then
            table.insert(self.current_chest_order, self.selected_chest_type)
        end
        table.insert(self.current_chest_order, "GOLD")

        self.current_chest_index = 1
        self.current_chest_type = self.current_chest_order[self.current_chest_index]

        console.print("self.selected_chest_type: " .. tostring(self.selected_chest_type))
        console.print("self.current_chest_type: " .. tostring(self.current_chest_type))
        self.current_state = chest_state.MOVING_TO_CHEST
        self.failed_attempts = 0
    end,

    move_to_aether = function(self)
        local aether_bomb = utils.get_aether_actor()
        if aether_bomb then
            if utils.distance_to(aether_bomb) > 2 then
                explorer:set_custom_target(aether_bomb:get_position())
                explorer:move_to_target()
            else
                self.current_state = chest_state.COLLECTING_AETHER
            end
        else
            console.print("No aether bomb found")
            self.current_state = chest_state.SELECTING_CHEST
        end
    end,

    collect_aether = function(self)
        local aether_bomb = utils.get_aether_actor()
        if aether_bomb then
            interact_object(aether_bomb)
            self.current_state = chest_state.SELECTING_CHEST
        else
            console.print("No aether bomb found to collect")
            self.current_state = chest_state.SELECTING_CHEST
        end
    end,

    select_chest = function(self)
        console.print("Selecting chest")
        console.print("Current self.selected_chest_type: " .. tostring(self.selected_chest_type))
        console.print("Current self.current_chest_type: " .. tostring(self.current_chest_type))
        self.current_state = chest_state.MOVING_TO_CHEST
    end,

    move_to_chest = function(self)
        if self.current_chest_type == nil then
            console.print("Error: current_chest_type is nil")
            self:try_next_chest(false)
            return
        end

        console.print("Attempting to find " .. self.current_chest_type .. " chest")
        local chest = utils.get_chest(enums.chest_types[self.current_chest_type])

        if chest then
            local distance = utils.distance_to(chest)
            console.print(string.format("Distance to %s chest: %.2f", self.current_chest_type, distance))

            if distance > 3 then
                local current_time = get_time_since_inject()
                if current_time >= self.move_cooldown then
                    console.print(string.format("Moving to %s chest", self.current_chest_type))
                    explorer:set_custom_target(chest:get_position())
                    explorer:move_to_target()

                    self.move_attempts = (self.move_attempts or 0) + 1
                    self.move_cooldown = current_time + 0.5  -- Set a 0.5 second cooldown

                    if self.move_attempts >= self.max_move_attempts then
                        console.print("Failed to reach chest after multiple attempts")
                        self:try_next_chest(false)
                        return
                    end
                end
            else
                console.print(string.format("Close enough to %s chest. Preparing to open.", self.current_chest_type))
                self.current_state = chest_state.OPENING_CHEST
                self.move_attempts = 0
            end
        else
            console.print("Chest not found")
            self:try_next_chest(false)
        end
    end,

    open_chest = function(self)
        if tracker.check_time("chest_opening_time", 1) then
            local chest = utils.get_chest(enums.chest_types[self.current_chest_type])
            if chest then
                local try_open_chest = interact_object(chest)
                console.print("Chest interaction result: " .. tostring(try_open_chest))
                self.current_state = chest_state.WAITING_FOR_VFX
            else
                console.print("Chest not found when trying to open")
                self:try_next_chest(false)
                -- Log all nearby actors to help debug
                local actors = actors_manager:get_all_actors()
                for _, actor in pairs(actors) do
                    if actor:get_skin_name():match("Chest") then
                        console.print("Found chest: " .. actor:get_skin_name() .. ", Distance: " .. utils.distance_to(actor))
                    end
                end
            end
        end
    end,

    wait_for_vfx = function(self)
        if tracker.check_time("chest_vfx_wait", 1) then
            local actors = actors_manager:get_all_actors()
            for _, actor in pairs(actors) do
                local name = actor:get_skin_name()
                if name == "vfx_resplendentChest_coins" or name == "vfx_resplendentChest_lightRays" then
                    console.print("Chest opened successfully: " .. name)
                    self.failed_attempts = 0
                    self:try_next_chest(true)  -- Move to next chest type after successful opening
                    return
                end
            end

            console.print("No visual effects found, chest opening may have failed")
            self.failed_attempts = self.failed_attempts + 1
            if self.failed_attempts >= self.max_attempts then
                self:try_next_chest(false)
            else
                self.current_state = chest_state.OPENING_CHEST
            end
        end
    end,

    try_next_chest = function(self, was_successful)
        console.print("Trying next chest")
        console.print("Current self.current_chest_type: " .. tostring(self.current_chest_type))
        console.print("Current self.selected_chest_type: " .. tostring(self.selected_chest_type))

        if was_successful then
            self.chests_opened[self.current_chest_type] = true
            if self.current_chest_type == "GREATER_AFFIX" then
                tracker.ga_chest_opened = true
            elseif self.current_chest_type == self.selected_chest_type then
                tracker.selected_chest_opened = true
            elseif self.current_chest_type == "GOLD" then
                tracker.gold_chest_opened = true
            end
        end

        local function move_to_next_chest()
            self.current_chest_index = self.current_chest_index + 1
            if self.current_chest_index <= #self.current_chest_order then
                self.current_chest_type = self.current_chest_order[self.current_chest_index]
                return true
            end
            return false
        end

        if not move_to_next_chest() then
            if self:any_chest_opened() then
                console.print("All available chests opened, finishing task")
                self.current_state = chest_state.FINISHED
                tracker.finished_chest_looting = true
            else
                console.print("Failed to open any chests, resetting task")
                self:reset()
            end
            return
        end

        console.print("Next chest type set to: " .. self.current_chest_type)
        self.current_state = chest_state.MOVING_TO_CHEST
        self.move_attempts = 0
        self.move_cooldown = 0
    end,

    finish_chest_opening = function(self)
        console.print("Finishing chest opening task")
        
        if self:any_chest_opened() then
            console.print("At least one chest was opened")
            tracker.finished_chest_looting = true
        else
            console.print("No chests were opened, resetting task")
            self:reset()
        end

        console.print("Chest opening task finished")
    end,

    any_chest_opened = function(self)
        for _, opened in pairs(self.chests_opened) do
            if opened then
                return true
            end
        end
        return false
    end,

    reset = function(self)
        self.current_state = chest_state.INIT
        self.current_chest_type = nil
        self.failed_attempts = 0
        self.current_chest_index = nil
        self.move_attempts = 0
        self.move_cooldown = 0
        self.chests_opened = {}
        tracker.finished_chest_looting = false
        tracker.ga_chest_opened = false
        tracker.selected_chest_opened = false
        tracker.gold_chest_opened = false
        console.print("Reset open_chests_task and related tracker flags")
    end,
}

return open_chests_task