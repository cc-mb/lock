local Door = require "lock.lib.door"

local Pns = require "pns.client"

local Table = require "mb.algorithm.table"
local PrefixedLogger = require "mb.log.prefixed_logger"
local VOID_LOGGER = require "mb.log.void_logger"
local DoorDevice = require "mb.peripheral.door"

local GuiH = require "GuiH"

--- Execution parameters
---@class ExecutionParameters
---@field runtime function? Main runtime. If defined and its execution ends, whole execution ends.
---@field on_event function? On UI event callback.
---@field before_draw function? Callback called right before UI drawing.
---@field after_draw function? Callback called right after UI drawing.

--- Asynchronous task parameters
---@class AsyncParameters
---@field fn function Function that should run asynchronously.
---@field delay number? How long should be the task execution delayed.
---@field error_flag boolean? If set, error inside task causes exception.
---@field debug boolean? If set, error and state logging are enabled.

--- Lock
---@class Lock
---@field private _config Config Config.
---@field private _door RsDevice Door controller.
---@field private _left Side Left side controller.
---@field private _right Side Right side controller.
---@field private _log Logger Logger.
---@field private _terminate boolean If set lock will terminate.
local Lock = {
  --- Configuration file.
  CONFIG_FILE = "/etc/lock.cfg",
  --- Default configuration file.
  DEFAULT_CONFIG_FILE = "/opt/lock/default_config.cfg",
}
Lock.__index = Lock

--- Master config.
---@class Config
---@field pns PnsConfig PNS configuration.
---@field door DoorConfig Door configuration.
---@field left SideConfig Left side configuration.
---@field right SideConfig Right side configuration.

--- PNS config.
---@class PnsConfig
---@field enabled boolean If set PNS will be used.
---@field prefix string? Prefix applied to all symbolic names.

--- Door config.
---@class DoorConfig
---@field device string Door controller name.
---@field device_side string Door controller side.
---@field keep_open_duration number How long will be the door kept open. [s]
---@field transition_duration number How long does it take to open/close the door. [s]

--- Lock creation parameters.
---@class LockCreationParams
---@field log Logger? Logger to use.

--- Constructor
---@param params LockCreationParams
function Lock.new(params)
  local self = setmetatable({}, Lock)

  self._log = PrefixedLogger.new(params.log or VOID_LOGGER, "[lock]")
  self._log:trace("Creating new lock.")

  local config = {}

  -- read default config
  local default_config_file = fs.open(Lock.DEFAULT_CONFIG_FILE, "r")
  if default_config_file then
    config = textutils.unserialise(default_config_file.readAll())
  else
    self._log:warning("Default config file  \"" .. Lock.DEFAULT_CONFIG_FILE .. "\" could not be read.")
  end

  local config_file = fs.open(Lock.CONFIG_FILE, "r")
  if config_file then
    config = Table.merge(config, textutils.unserialise(config_file.readAll()))
  else
    self._log:warning("Config file \"" .. Lock.CONFIG_FILE .. "\" could not be read.")
  end

  self._config = config

  if self._config.pns.enabled then
    self._log:debug("PNS enabled.")
    self:apply_pns()
  end

  self:init()

  self._log:trace("Lock created.")

  return self
end

--- Apply PNS on names.
---@private
function Lock:apply_pns()
  self._log:trace("Applying PNS.")

  self._log:debug("Starting RedNet.")
  peripheral.find("modem", rednet.open)

  self._log:trace("Creating PNS client.")
  local pns = Pns.new{}

  local function translate(config)
    self._log:trace(("Translating %s."):format(config.device))
    local symbolic_name = config.device
    if self._config.pns.prefix then
      symbolic_name = self._config.pns.prefix .. "." .. symbolic_name
    end

    config.device = pns:look_up(self._config.pns.prefix .. "." .. config.device)
    self._log:trace(("Got %s."):format(config.device))
  end

  translate(self._config.door)
  translate(self._config.left.lock)
  translate(self._config.left.panel)
  translate(self._config.right.lock)
  translate(self._config.right.panel)

  if self._config.left.lock.device == "" then
    self._config.left.lock.device = nil
  end

  if self._config.right.lock.device == "" then
    self._config.right.lock.device = nil
  end

  self._log:trace("All PNS names translated.")
  self._log:debug("Stopping RedNet.")
  rednet.close()
end

--- Init devices software.
---@private
function Lock:init()
  self._log:trace("Device initialization started.")

  self._door = DoorDevice.new{
    name = self._config.door.device,
    side = self._config.door.device_side
  }

  self._left = Door.new{
    config = self._config.left,
    log = PrefixedLogger.new(self._log, "[left]"),
    request_open = function () self:request_open() end,
    ui = GuiH
  }

  self._right = Door.new{
    config = self._config.right,
    log = PrefixedLogger.new(self._log, "[right]"),
    request_open = function () self:request_open() end,
    ui = GuiH,
  }

  self._log:trace("Device initialization done.")
end

--- Init hardware.
---@private
function Lock:initialize()
  self._log:debug("Door initialization sequence.")
  self._door:open()
  os.sleep(self._config.door.transition_duration)
  self._door:close()
  os.sleep(self._config.door.transition_duration)
  self._log:trace("Door initialization sequence complete.")
end

--- Main loop.
---@private
function Lock:main_loop()
  local last_clock = os.clock()

  self._log:trace(("Main loop started @ %f."):format(last_clock))

  self._terminate = false
  while not self._terminate do
    local clock = os.clock()
    self._log:trace(("Tick @ %f."):format(clock))
    self:update(clock - last_clock)
    last_clock = clock

    -- limit to 4 Hz
    os.sleep(0.25)
  end

  self._log:trace(("Main loop ended @ %f."):format(os.clock()))
end

--- Update.
---@private
---@param delta_t number Time difference since last update. [s]
function Lock:update(delta_t)
  self._log:trace(("Lock update with delta T %f."):format(delta_t))
  self._left:update(delta_t)
  self._right:update(delta_t)
  self._log:trace("Lock updated.")
end

--- Run lock main loop.
---@param ... ... Asynchronous tasks.
function Lock:run(...)
  self._log:info("Starting lock.")
  self:initialize()

  self._left:async{ fn = function() self._right:execute{} end }

  for _, task in pairs({...}) do
    self._left:async{ fn = function() task() end }
  end

  self._left:execute{ runtime = function() self:main_loop() end }

  self._log:info("Lock stopped.")
end

--- Request opening of the door.
---@private
function Lock:request_open()
  self._log:debug("Left open requested.")
  self._chamber:async{
    fn = function()
      self._log:trace("Suspend all.")
      self._chamber:suspend()
      self._left:suspend()
      self._right:suspend()

      self._log:info("Door open procedure running.")

      self._log:debug("Opening door.")
      self._door:open()
      os.sleep(self._config.door.transition_duration)
    
      self._log:debug("Door open.")
      os.sleep(self._config.door.keep_open_duration)
    
      self._log:debug("Closing door.")
      self._door:close()
      os.sleep(self._config.door.transition_duration)
    
      self._log:info("Door closed.")

      self._log:trace("Unsuspend all.")
      self._chamber:resume()
      self._left:resume()
      self._right:resume()
    end
  }
end

return Lock
