local args = {...}

shell.run("/opt/lock/bin/lock " .. table.concat(args, " "))
