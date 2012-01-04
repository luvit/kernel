local Kernel = require('./kernel')
local Timer = require('timer')
local UV = require('uv')
Kernel.cache_lifetime = 0 -- disable cache

Kernel.compile("simple.html", function (err, template)
  if err then
    p("compile error", err)
    return
  end
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
    p(err, result)
  end)
end)


