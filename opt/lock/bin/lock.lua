package.path = "/opt/?.lua;" .. package.path

local Lock = require "lock.lib.lock"
local Logger = require "mb.log.handle_logger"

local args = {...}

local log_level = Logger.LEVEL.INFO

local options = {
  ["log-level"] = function(value)
    if value == "error" then
      log_level = Logger.LEVEL.ERROR
    elseif value == "warning" then
      log_level = Logger.LEVEL.WARNING
    elseif value == "info" then
      log_level = Logger.LEVEL.INFO
    elseif value == "debug" then
      log_level = Logger.LEVEL.DEBUG
    elseif value == "trace" then
      log_level = Logger.LEVEL.TRACE
    elseif tonumber(value, 10) then
      log_level = tonumber(value, 10)
    else
      error("Invalid value for log-level: " .. value)
    end
  end
}

for _, arg in pairs(args) do
  local option = arg:match("^--.+=")
  local value = arg:match("=.+$")

  local selected = options[option:sub(3, #option - 1)]
  if selected then
    selected(value:sub(2))
  else
    error("Invalid option: " .. arg)
  end
end

local lock = Lock.new{ log = Logger.new(io.stdout, log_level) }

lock:run()
