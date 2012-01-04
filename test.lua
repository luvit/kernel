local Kernel = require('./kernel')
local Timer = require('timer')
local UV = require('uv')
Kernel.cacheLifetime = 0 -- disable cache

Kernel.compile("simple.html", function (err, template)
  if err then error(err) end
  p("template", template)
  template({
    foo = function (callback)
      Timer.set_timeout(10, function ()
        callback(nil, UV.hrtime())
      end)
    end,
    bar = "bar",
    section = function (block, callback)
      block({}, callback)
    end,
    conditional = function (condition, block, callback)
      if condition then block({}, callback)
      else callback(nil, "") end
    end
  }, function (err, result)
    if err then error(err) end
    p("result", result)
  end)
end)


