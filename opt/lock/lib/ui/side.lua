local Monitor = require "mb.peripheral.monitor"

--- UI for the door.
---@class SideUi
---@field private _locked boolean If set controls are locked.
---@field private _suspended boolean Flag marking UI as suspended.
---@field private _ui table GuiH instance.
local SideUi = {}
SideUi.__index = SideUi

--- Panel config
---@class PanelConfig
---@field device string Panel monitor.
---@field room RoomInfo Room information shown on panel.

--- Room information
---@class RoomInfo
---@field hazard string? Hazard warning.
---@field name string? Room name.
---@field number number? Room number.

--- Side UI creation parameters.
---@class SideUiCreationParams
---@field panel PanelConfig Panel config.
---@field lock_level number? Room lock level shown.
---@field request_open function Callback used to request door opening.
---@field ui table GuiH
local DoorUiParams = {}

--- Constructor.
---@param params SideUiCreationParams Side UI creation parameters.
function SideUi.new(params)
  local self = setmetatable({}, SideUi)

  self._suspended = false
  self._locked = false
  local monitor = Monitor.new{ name = params.panel.device}
  monitor.setTextScale(0.5)
  self._ui = params.ui.new(monitor)

  self:init_ui(params)
  
  return self
end

--- Return whether suspended.
function SideUi:is_suspended()
  return self._suspended
end

--- Suspend the UI.
function SideUi:suspend()
  self._suspended = true
  self:update_ui()
end

--- Unsuspend the UI.
function SideUi:resume()
  self._suspended = false
  self:update_ui()
end

--- Return current lock state.
function SideUi:get_locked()
  return self._locked
end

--- Set new lock state.
function SideUi:set_locked(locked)
  self._locked = locked
  self:update_ui()
end

--- Start main loop.
---@param params ExecutionParameters
function SideUi:execute(params)
  self._ui.execute(params.runtime, params.on_event, params.before_draw, params.after_draw)
end

--- Schedule async task.
---@param params AsyncParameters
function SideUi:async(params)
  self._ui.async(params.fn, params.delay, params.error_flag, params.debug)
end

--- Init UI
---@param params DoorUiCreationParams Door UI creation parameters.
---@private
function SideUi:init_ui(params)
  self._ui.new.rectangle{
    name = "upper_area",
    graphic_order = 0,
    x = 1, y = 1,
    width = self._ui.width, height = 3,
    color = colors.white
  }

  self._ui.new.rectangle{
    name = "lower_area",
    graphic_order = -1,
    x = 1, y = 4,
    width = self._ui.width, height = self._ui.height - 3,
    color = colors.yellow
  }

  if params.panel.room.number then
    self._ui.new.text{
      name = "room_number",
      text = self._ui.text{
        text = tostring(params.panel.room.number),
        x = 1, y = 1,
        transparent = true,
        fg = colors.gray
      }
    }
  end

  if params.panel.room.name then
    self._ui.new.text{
      name = "room_name",
      text = self._ui.text{
        text = params.panel.room.name,
        x = 1, y = 2,
        centered = true,
        transparent = true,
        fg = colors.black,
        width = self._ui.width, height = 1
      }
    }
  end

  if params.panel.room.hazard then
    self._ui.new.text{
      name = "room_hazard",
      text = self._ui.text{
        text = params.panel.room.hazard,
        x = 1, y = 3,
        centered = true,
        transparent = true,
        fg = colors.red,
        width = self._ui.width, height = 1
      }
    }
  end

  if params.lock_level then
    local color = {
      [1] = { bg = colors.yellow, fg = colors.black },
      [2] = { bg = colors.orange, fg = colors.white },
      [3] = { bg = colors.red, fg = colors.white },
      [4] = { bg = colors.pink, fg = colors.black },
      [5] = { bg = colors.purple, fg = colors.white }
    }

    self._ui.new.text{
      name = "lock_level",
      text = self._ui.text{
        text = tostring(params.lock_level),
        x = self._ui.width, y = 1,
        bg = color[params.lock_level].bg,
        fg = color[params.lock_level].fg
      }
    }
  end

  self._ui.new.button{
    name = "button",
    x = 3, y = 5,
    width = self._ui.width - 4, height = self._ui.height - 5,
    text = self._ui.text{
      text = "OPEN",
      centered = true,
      transparent = true,
      fg = colors.white
    },
    background_color = colors.green,
    on_click = params.request_open
  }

  self._ui.new.rectangle{
    name = "lower_area_locked",
    visible = false,
    graphic_order = 0,
    x = 1, y = 4,
    width = self._ui.width, height = self._ui.height - 3,
    color = colors.red
  }

  self._ui.new.text{
    name = "locked",
    visible = false,
    text = self._ui.text{
      text = "LOCKED",
      x = 1, y = self._ui.height,
      centered = true,
      transparent = true,
      fg = colors.white,
      width = self._ui.width, height = 1
    }
  }

  self:update_ui()
end

--- Update UI based on the state.
---@private
function SideUi:update_ui()
  local button_props = {}
  if self._suspended then
    button_props = {
      fg = colors.lightGray,
      bg = colors.gray
    }
  else
    button_props = {
      fg = colors.white,
      bg = colors.green
    }
  end

  local button = self._ui.elements.button["button"]
  button.text.fg = button_props.fg
  button.background_color = button_props.bg
  button.reactive = not (self._suspended or self._locked)

  local lower_area_locked = self._ui.elements.rectangle["lower_area_locked"]
  lower_area_locked.visible = self._locked

  local locked = self._ui.elements.text["locked"]
  locked.visible = self._locked
end

return SideUi