local Ui = require "lock.lib.ui.side"

local RsReader = require "mb.peripheral.rs_reader"

--- Side controller.
---@class Side
---@field private _config SideConfig Configuration.
---@field private _lock RsReader? Door lock.
---@field private _log Logger Logger.
---@field private _ui SideUi UI.
---@field private _unlocked_for number Remaining time the door is unlocked. [s]
local Side = {}
Side.__index = Side

--- Side config.
---@class SideConfig
---@field lock LockConfig Lock configuration.
---@field panel PanelConfig Panel configuration.

--- Lock config.
--- In device is defined, all of them must be defined.
---@class LockConfig
---@field device string? Optional. Lock controller name.
---@field device_side string? Optional. Lock controller side.
---@field level number? Optional. Lock level displayed on panel.
---@field unlock_duration number? Optional. How long should door be unlocked. [s]

--- Side creation parameters.
---@class SideCreationParams
---@field config SideConfig Side configuration.
---@field log Logger Logger.
---@field request_open function Callback used to request door opening.
---@field ui table GuiH

--- Constructor
---@param params SideCreationParams Side creation parameters.
function Side.new(params)
  local self = setmetatable({}, Side)

  self._config = params.config
  self._log = params.log
  self._log:trace("Side controller creation.")

  self._lock = self._config.lock.device and RsReader.new{
    name = self._config.lock.device,
    side = self._config.lock.device_side
  }

  if not self._lock then
    self._log:info("No lock.")
  else
    self._unlocked_for = 0.0
  end

  self._ui = Ui.new{
    panel = self._config.panel,
    lock_level = self._config.lock.level,
    request_open = params.request_open,
    ui = params.ui
  }

  self._log:trace("Side controller created.")

  return self
end

--- Start main loop.
---@param params ExecutionParameters
function Side:execute(params)
  self._log:debug("Execution started.")
  self._ui:execute(params)
  self._log:debug("Execution ended.")
end

--- Schedule async task.
---@param params AsyncParameters
function Side:async(params)
  self._log:trace("Task scheduled.")
  self._ui:async(params)
end

--- Update
---@param delta_t number Time difference between ticks. [s]
function Side:update(delta_t)
  self._log:trace("Side update.")

  if self._lock then
    if self._lock:is_on() then
      if self._unlocked_for <= 0 then
        self._log:debug("Unlocking.")
        self._unlocked_for = self._config.lock.unlock_duration
        self._ui:set_locked(false)
      end
    elseif self._unlocked_for > 0 then
      self._log:trace("Lock timer decremented.")
      self._unlocked_for = self._unlocked_for - delta_t
    elseif not self._ui:get_locked() then
      self._log:debug("Locking.")
      self._ui:set_locked(true)
    end
  end
  self._log:trace("Side updated.")
end

--- Return whether suspended.
function Side:is_suspended()
  return self._ui:is_suspended()
end

--- Suspend controller.
function Side:suspend()
  self._log:debug("Side control suspended.")
  self._ui:suspend()
end

--- Unsuspend controller.
function Side:resume()
  self._log:debug("Side control unsuspended.")
  self._ui:resume()
end

return Side