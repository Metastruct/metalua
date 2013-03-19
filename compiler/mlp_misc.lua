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

---------------------------------------------------------------------
--
-- Summary: metalua parser, miscellaneous utility functions.
--
----------------------------------------------------------------------

--------------------------------------------------------------------------------
--
-- Exported API:
-- * [mlp.fget()]
-- * [mlp.id()]
-- * [mlp.opt_id()]
-- * [mlp.id_list()]
-- * [mlp.gensym()]
-- * [mlp.string()]
-- * [mlp.opt_string()]
-- * [mlp.id2string()]
--
--------------------------------------------------------------------------------

--require "gg"
--require "mll"

module ("mlp", package.seeall)

--------------------------------------------------------------------------------
-- returns a function that takes the [n]th element of a table.
-- if [tag] is provided, then this element is expected to be a
-- table, and this table receives a "tag" field whose value is
-- set to [tag].
--
-- The primary purpose of this is to generate builders for
-- grammar generators. It has little purpose in metalua, as lambda has
-- a lightweight syntax.
--------------------------------------------------------------------------------

function fget (n, tag) 
   assert (type (n) == "number")
   if tag then
      assert (type (tag) == "string")
      return function (x) 
         assert (type (x[n]) == "table")       
         return {tag=tag, unpack(x[n])} end 
   else
      return function (x) return x[n] end 
   end
end


--------------------------------------------------------------------------------
-- Try to read an identifier (possibly as a splice), or return [false] if no
-- id is found.
--------------------------------------------------------------------------------
function opt_id (lx)
   local a = lx:peek();
   if lx:is_keyword (a, "-{") then
      local v = gg.sequence{ "-{", splice_content, "}" } (lx) [1]
      if v.tag ~= "Id" and v.tag ~= "Splice" then
         return gg.parse_error(lx, "Bad id splice")
      end
      return v
   elseif a.tag == "Id" then return lx:next()
   else return false end
end

--------------------------------------------------------------------------------
-- Mandatory reading of an id: causes an error if it can't read one.
--------------------------------------------------------------------------------
function id (lx)
   return opt_id (lx) or gg.parse_error(lx,"Identifier expected")
end

--------------------------------------------------------------------------------
-- Common helper function
--------------------------------------------------------------------------------
id_list = gg.list { primary = mlp.id, separators = "," }

--------------------------------------------------------------------------------
-- Symbol generator: [gensym()] returns a guaranteed-to-be-unique identifier.
-- The main purpose is to avoid variable capture in macros.
--
-- If a string is passed as an argument, theis string will be part of the
-- id name (helpful for macro debugging)
--------------------------------------------------------------------------------
local gensymidx = 0

function gensym (arg)
   gensymidx = gensymidx + 1
   return { tag="Id", _G.string.format(".%i.%s", gensymidx, arg or "")}
end

--------------------------------------------------------------------------------
-- Converts an identifier into a string. Hopefully one day it'll handle
-- splices gracefully, but that proves quite tricky.
--------------------------------------------------------------------------------
function id2string (id)
   --print("id2string:", disp.ast(id))
   if id.tag == "Id" then id.tag = "String"; return id
   elseif id.tag == "Splice" then
      assert (in_a_quote, "can't do id2string on an outermost splice")
      error ("id2string on splice not implemented")
      -- Evaluating id[1] will produce `Id{ xxx },
      -- and we want it to produce `String{ xxx }
      -- Morally, this is what I want:
      -- return `String{ `Index{ `Splice{ id[1] }, `Number 1 } }
      -- That is, without sugar:
      return {tag="String",  {tag="Index", {tag="Splice", id[1] }, 
                                           {tag="Number", 1 } } }
   elseif id.tag == 'Error' then return id
   else error ("Identifier expected: ".._G.table.tostring(id, 'nohash')) end
end

--------------------------------------------------------------------------------
-- Read a string, possibly spliced, or return an error if it can't
--------------------------------------------------------------------------------
function string (lx)
   local a = lx:peek()
   if lx:is_keyword (a, "-{") then
      local v = gg.sequence{ "-{", splice_content, "}" } (lx) [1]
      if v.tag ~= "" and v.tag ~= "Splice" then
         return gg.parse_error(lx,"Bad string splice")
      end
      return v
   elseif a.tag == "String" then return lx:next()
   else error "String expected" end
end

--------------------------------------------------------------------------------
-- Try to read a string, or return false if it can't. No splice allowed.
--------------------------------------------------------------------------------
function opt_string (lx)
   return lx:peek().tag == "String" and lx:next()
end
   
--------------------------------------------------------------------------------
-- Chunk reader: block + Eof
--------------------------------------------------------------------------------
function skip_initial_sharp_comment (lx)
   -- Dirty hack: I'm happily fondling lexer's private parts
   -- FIXME: redundant with lexer:newstream()
   lx :sync()
   local i = lx.src:match ("^#.-\n()", lx.i)
   if i then lx.i, lx.column_offset, lx.line = i, i, lx.line+1 end
end

local function _chunk (lx)
   if PRINT_PARSED_STAT then print "HI"; printf("about to chunk on %s", tostring(lx:peek())) end
   if lx:peek().tag == 'Eof' then
       if PRINT_PARSED_STAT then print "at EOF" end
       return { } -- handle empty files
   else 
      skip_initial_sharp_comment (lx)
      if PRINT_PARSED_STAT then printf("after skipping, at %s", tostring(lx:peek())) end
      local chunk = block (lx)
      if lx:peek().tag ~= "Eof" then 
          _G.table.insert(chunk, gg.parse_error(lx, "End-of-file expected"))
      end
      return chunk
   end
end

-- chunk is wrapped in a sequence so that it has a "transformer" field.
chunk = gg.sequence { _chunk, builder = unpack }
