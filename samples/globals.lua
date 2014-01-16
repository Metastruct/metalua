-------------------------------------------------------------------------------
-- Copyright (c) 2006-2014 Fabien Fleutot and others.
--
-- All rights reserved.
--
-- This program and the accompanying materials are made available
-- under the terms of the Eclipse Public License v1.0 which
-- accompanies this distribution, and is available at
-- http://www.eclipse.org/legal/epl-v10.html
--
-- This program and the accompanying materials are also made available
-- under the terms of the MIT public license which accompanies this
-- distribution, and is available at http://www.lua.org/license.html
--
-- Contributors:
--     Fabien Fleutot - API and implementation
--
-------------------------------------------------------------------------------

--
-- Example of treequery usage: list all the unauthorized global
-- variable occurrences in a given source file.
--
-- Usage: lua globals.lua file_to_analyze.lua
--
-- TODO:
-- * take command-line options
-- * 

require 'metalua.loader' -- needed to load "metalua/treequery.mlua"

mlc     = require 'metalua.compiler'.new() -- compiler
Q       = require 'metalua.treequery'      -- AST queries
pp      = require 'metalua.pprint'         -- pretty-printer
srcfile = assert(..., "no file name")      -- filename to analyze...
ast     = mlc :srcfile_to_ast(srcfile)     -- ...converted in an AST

-- Global variable names which won't be reported:

allowed = [[ _G _VERSION assert collectgarbage coroutine
coroutine.create coroutine.resume coroutine.running coroutine.status
coroutine.wrap coroutine.yield debug debug.debug debug.getfenv
debug.gethook debug.getinfo debug.getlocal debug.getmetatable
debug.getregistry debug.getupvalue debug.setfenv debug.sethook
debug.setlocal debug.setmetatable debug.setupvalue debug.traceback
dofile error gcinfo getfenv getmetatable io io.close io.flush io.input
io.lines io.open io.output io.popen io.read io.stderr io.stdin
io.stdout io.tmpfile io.type io.write ipairs list load loadfile
loadstring math math.abs math.acos math.asin math.atan math.atan2
math.ceil math.cos math.cosh math.deg math.exp math.floor math.fmod
math.frexp math.huge math.ldexp math.log math.log10 math.max math.min
math.mod math.modf math.pi math.pow math.rad math.random
math.randomseed math.sin math.sinh math.sqrt math.tan math.tanh module
newproxy next os os.clock os.date os.difftime os.execute os.exit
os.getenv os.remove os.rename os.setlocale os.time os.tmpname package
package.config package.cpath package.loaded package.loaders
package.loadlib package.path package.preload package.seeall pairs
pcall print rawequal rawget rawset require select setfenv setmetatable
string string.byte string.char string.dump string.find string.format
string.gfind string.gmatch string.gsub string.len string.lower
string.match string.rep string.reverse string.sub string.upper table
table.concat table.foreach table.foreachi table.getn table.insert
table.maxn table.remove table.setn table.sort tonumber tostring type
unpack xpcall ]]


-- The same, put in a hash-table for easy retrieval:
allowed_set = { }
for word in allowed :gmatch "%S+" do allowed_set[word]=true end

function analyze(ast)
    local globals = { } -- variable name -> list of line numbers

    -- add the line number where node `id` occurs into table `globals`:
    local function log_global(id, ...)
        local name = id[1]
        local line = id.lineinfo and id.lineinfo.first.line or "no info"
        local full_chain = {[0]=id, ...}
        -- Retrieve the subfields x.subfield_1.....subfield_n
        for i, ancestor in ipairs(full_chain) do
            -- `Index{ x, `String y } if x==full_chain[i-1]
            if ancestor.tag=='Index' and
                ancestor[1]==full_chain[i-1] and
                ancestor[2].tag=='String' then
                name = name.."."..ancestor[2][1]
            else break end
        end
        local lines = globals[name]
        if lines then table.insert(lines, line)
        else globals[name] = { line } end
    end

    -- Treequery command to retrieve global variable occurrences:
    Q(ast)                         -- globals are...
        :filter 'Id'               -- ...nodes with tag 'Id'...
        :filter_not (Q.is_binder)  -- ...which are not local binders...
        :filter_not (Q.get_binder) -- ...and aren't bound;
        :foreach (log_global)      -- log each of them in `globals`.

    -- format and sort the result
    local sort_them = { }
    for name, lines in pairs(globals) do
        if not allowed_set[name] then
            local line = name .. ": " .. pp.tostring(lines) :sub (2, -2)
            table.insert(sort_them, line)
        end
    end

    -- print the result
    if next(sort_them) then
        table.sort(sort_them)
        print(table.concat(sort_them, "\n"))
    else print "no global found" end
end

function list()
  local banned = { ['package.loaded'] = true }
  local acc  = { }
  local seen = { }
  local function rec(prefix, t)
    if seen[t] then return end
    seen[t]=true
    for k, v in pairs(t) do
      if type(k)=='string' then
        local path = prefix and prefix..'.'..k or k
        table.insert(acc, path)
        if type(v)=='table' and not banned[path] then rec(path, v) end
      end
    end
  end
  rec(nil, _G)
  table.sort(acc)
  return table.concat(acc, ' ')
end

analyze(ast)

