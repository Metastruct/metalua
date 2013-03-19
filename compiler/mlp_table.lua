-------------------------------------------------------------------------------
-- Copyright (c) 2006-2013 Fabien Fleutot and others.
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

----------------------------------------------------------------------
--
-- Summary: metalua parser, table constructor parser. This is part
--   of thedefinition of module [mlp].
--
----------------------------------------------------------------------

--------------------------------------------------------------------------------
--
-- Exported API:
-- * [mlp.table_field()]
-- * [mlp.table_content()]
-- * [mlp.table()]
--
-- KNOWN BUG: doesn't handle final ";" or "," before final "}"
--
--------------------------------------------------------------------------------

--require "gg"
--require "mll"
--require "mlp_misc"
local tableinsert = table.insert

module ("mlp", package.seeall)

--------------------------------------------------------------------------------
-- eta expansion to break circular dependencies:
--------------------------------------------------------------------------------
local function _expr (lx) return expr(lx) end

--------------------------------------------------------------------------------
-- [[key] = value] table field definition
--------------------------------------------------------------------------------
local bracket_field = gg.sequence{ "[", _expr, "]", "=", _expr, builder = "Pair" }

--------------------------------------------------------------------------------
-- [id = value] or [value] table field definition;
-- [[key]=val] are delegated to [bracket_field()]
--------------------------------------------------------------------------------
function table_field (lx)
   if lx:is_keyword (lx:peek(), "[") then return bracket_field (lx) end
   local e = _expr (lx)
   if lx:is_keyword (lx:peek(), "=") then 
      lx:next(); -- skip the "="
      local key = id2string(e)
      local val = _expr(lx)
      local r = { tag="Pair", key, val } 
      r.lineinfo = { first = key.lineinfo.first, last = val.lineinfo.last }
      return r
   else return e end
end

local function _table_field(lx) return table_field(lx) end

--------------------------------------------------------------------------------
-- table constructor, without enclosing braces; returns a full table object
--------------------------------------------------------------------------------
function table_content(lx)
    local items = {tag = "Table"}
    while not lx:is_keyword(lx:peek(), '}') do
        -- Seek for table values
        local tablevalue = _table_field (lx)
        if tablevalue then
            tableinsert(items, tablevalue)
        else 
            return gg.parse_error(lx, '`Pair of value expected.')
        end

        -- Seek for values separators
        if lx:is_keyword(lx:peek(), ',', ';') then
            lx:next()
        elseif not lx:is_keyword(lx:peek(), '}') then
            return gg.parse_error(lx, '} expected.')
        end
    end
    return items
end

local function _table_content(lx) return table_content(lx) end

--------------------------------------------------------------------------------
-- complete table constructor including [{...}]
--------------------------------------------------------------------------------
table = gg.sequence{ "{", _table_content, "}", builder = fget(1) }
