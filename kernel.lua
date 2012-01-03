-- types
-- - static
-- - variable
-- - function (always async, can pass in args)
-- - block always async, can have extra args and gets

local FS = require('fs')
local Timer = require('timer')
local String = require('string')
local Table = require('table')
local Math = require('math')

local Kernel = {
  cache_lifetime = 1000,
};


-- Load a file from disk and compile into executable template
local function compile(filename, callback)
  FS.read_file(filename, function (err, source)
    if err then return callback(err) end
    local template;
    local tokens = Kernel.tokenizer(source)
    tokens = Kernel.parser(tokens, source, filename)
    local code = Kernel.generator(tokens)
    p("code",code)
    -- try {
    --   template = Function("return " + generator(parser(tokenizer(source), source, filename)))();
    -- } catch (err) {
    --   callback(err); return;
    -- }
    -- callback(null, template);
  end)
end


-- A caching and batching wrapper around compile.
local templateCache = {}
local templateBatch = {}
function Kernel.compile(filename, callback)
  -- Check arguments
  if not (type(filename) == 'string') then error("First argument to Kernel must be a filename") end
  if not (type(callback) == 'function') then error("Second argument to Kernel must be a function") end

  -- Check to see if the cache is still hot and reuse the template if so.
  if templateCache[filename] then
    callback(nil, templateCache[filename])
    return
  end
  
  -- Check if there is still a batch in progress and join it.
  if templateBatch[filename] then
    templateBatch[filename].push(callback)
    return
  end

  -- Start a new batch, call the real function, and report.
  local batch = {callback}
  templateBatch[filename] = batch
  compile(filename, function (err, template)

    -- We don't want to cache in case of errors
    if not err and Kernel.cache_lifetime > 0 then
      templateCache[filename] = template
      -- Make sure cached values expire eventually.
      Timer.set_timeout(Kernel.cache_lifetime, function ()
        templateCache[filename] = nil
      end)
    end

    -- The batch is complete, clear it out and execute the callbacks.
    templateBatch[filename] = nil
    for i, callback in ipairs(batch) do
      callback(err, template)
    end

  end)

end

--[[
function generator(tokens) {
  var length = tokens.length;
  var left = length;

  // Shortcut for static sections
  if (tokens.length === 1 && Array.isArray(tokens[0]) && tokens[0].length === 1 && typeof tokens[0][0] === 'string') {
    return "function(L, c){c(null," + JSON.stringify(tokens[0][0]) + ")}";
  }

  for (var i = 0; i < length; i++) {
    var token = tokens[i];
    if (Array.isArray(token)) left--;
  }
  var programHead = [
  "function(L,c){",
    "var $p=new Array(" + length + ")" + (left ? ",i=" + (length - 1) : ""),
    "try{",
    "(function(){with(this){"];
  var programTail = [
    "}}).call(L);",
    "}catch(e){return c(e)}",
    "var d;$c()",
    "function $e(e){if(d)return;d=!d;c(e)}",
    "function $c(){if(d)return;while($p.hasOwnProperty(i)){i--}if(i<0){d=!d;c(null,$p.join(''))}}",
  "}"];
  var simpleTail = [
    "}}).call(L);",
    "}catch(e){return c(e)}",
    "c(null,$p.join(''))",
  "}"];
  var generated = tokens.map(function(token, i) {
    if (Array.isArray(token)) {
      return "$p[" + i + "]=" + token.map(function (token) {
        if (typeof token === "string") { return JSON.stringify(token); }
        return "(" + token.name + ")";
      }).join("+");
    }
    if (token.contents || token.hasOwnProperty('args')) {
      var args = token.args ? (token.args + ",") : "";
      if (token.contents) { args += generator(token.contents) + ","; }
      return token.name + "(" + args + "function(e,r){if(e)return $e(e);$p[" + i + "]=r;$c()})";
    }
    return "$p[" + i + "]=" + token.name;
  });
  return programHead.concat(generated).concat(left ? programTail : simpleTail).join("\n");
}

// Helper to show nicly formatter error messages with full file position.
function getPosition(source, offset, filename) {
  var line = 0;
  var position = 0;
  var last = 0;
  for (position = 0; position >= 0 && position < offset; position = source.indexOf("\n", position + 1)) {
    line++;
    last = position;
  }
  return "(" + filename + ":" + line + ":" + (offset - last) + ")";
}

function stringify(source, token) {
  return source.substr(token.start, token.end-token.start);
}

function parser(tokens, source, filename) {
  var parts = [];
  var openStack = [];
  var i, l;
  var simple;
  for (i = 0, l = tokens.length; i < l; i++) {
    var token = tokens[i];
    if (typeof token === "string") {
      if (simple) simple.push(token)
      else parts.push(simple = [token]);
    } else if (token.open) {
      simple = false;
      token.parent = parts;
      parts.push(token);
      parts = token.contents = [];
      openStack.push(token);
    } else if (token.close) {
      simple = false;
      var top = openStack.pop();
      if (top.name !== token.name) {
        throw new Error("Expected closer for " + stringify(source, top) + " but found " + stringify(source, token) + " " + getPosition(source, token.start, filename));
      }
      parts = top.parent;
      delete top.parent;
      delete top.open;
    } else {
      if (token.hasOwnProperty('args')) {
        simple = false;
        parts.push(token);
      } else {
        if (simple) simple.push(token)
        else parts.push(simple = [token]);
      }
    }
  }
  if (openStack.length) {
    var top = openStack.pop();
    throw new Error("Expected closer for " + stringify(source, top) + " but reached end " + getPosition(source, top.end, filename));
  }
  return parts;
}
]]

-- Pattern to match all template tags. Allows balanced parens within the arguments
-- Also allows basic expressions in double {{tags}} with balanced {} within
local patterns = {
  tag = "{([#/]?)([%a_][%a%d_.]*)}",
  call = "{([#]?)([%a_][%a%d_.]*)(%b())}",
  raw = "{(%b{})}",
}

-- This lexes a source string into discrete tokens for easy parsing.
function Kernel.tokenizer(source)
  local parts = {}
  local position = 1
  local match

  function findMatch()
    local min = Math.huge
    local kind
    for name, pattern in pairs(patterns) do
      local m = {String.find(source, pattern, position)}
      if m[1] and m[1] < min then
        min = m[1]
        match = m
        kind = name
      end
    end
    if not kind then return end
    match.kind = kind
    return true
  end

  while findMatch() do
    local start = match[1]

    if start > position then -- Raw text was before this tag
      parts[#parts + 1] = source:sub(position, start - 1)
    end

    -- Move search to after tag match
    position = match[2]
    
    -- Create a token and tag the position in the source file for error reporting.
    local obj = { start = start, stop = position }
    
    if match.kind == "raw" then -- Raw expression
      obj.name = match[3]:sub(2, #match[3]-1)
    else
      if match[3] == "#" then
        obj.open = true
      elseif match[3] == "/" then
        obj.close = true
      end
      obj.name = match[4]
      if match.kind == "call" then -- With arguments
        obj.args = match[5]:sub(2,#match[5]-1)
      end
    end
    
    parts[#parts + 1] = obj
    
  end
  
  if #source > position then -- There is raw text left over
    parts[#parts + 1] = source:sub(position + 1)
  end
  
--[[            
    if (match[1] === "{") { // Raw expression
      obj.name = match.substr(2, match.length - 4);
    } else if (match[1] === "#") { // Open tag
    } else if (match[1] === "/") { // Close tag
      obj.close = true;
      obj.name = match.substr(2, match.length - 3);
    } else { // Normal tag
      if (match[match.length - 2] === ")") { // With arguments
        var i = match.indexOf("(");
        obj.name = match.substr(1, i - 1);
        obj.args = match.substr(i + 1, match.length - i - 3);
      } else { // Without arguments
        obj.name = match.substr(1, match.length - 2);
      }
    }
    parts.push(obj);
    tagRegex.lastIndex = position;
  }
  ]]
  return parts
end

return Kernel


