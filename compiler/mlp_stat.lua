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
-- Summary: metalua parser, statement/block parser. This is part of
--   the definition of module [mlp].
--
----------------------------------------------------------------------

--------------------------------------------------------------------------------
--
-- Exports API:
-- * [mlp.stat()]
-- * [mlp.block()]
-- * [mlp.for_header()]
--
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- eta-expansions to break circular dependency
--------------------------------------------------------------------------------
local expr      = function (lx) return mlp.expr     (lx) end
local func_val  = function (lx) return mlp.func_val (lx) end
local expr_list = function (lx) return mlp.expr_list(lx) end

module ("mlp", package.seeall)

--------------------------------------------------------------------------------
-- List of all keywords that indicate the end of a statement block. Users are
-- likely to extend this list when designing extensions.
--------------------------------------------------------------------------------


local block_terminators = { "else", "elseif", "end", "until", ")", "}", "]" }

-- FIXME: this must be handled from within GG!!!
function block_terminators:add(x) 
   if type (x) == "table" then for _, y in ipairs(x) do self:add (y) end
   else _G.table.insert (self, x) end
end

--------------------------------------------------------------------------------
-- list of statements, possibly followed by semicolons
--------------------------------------------------------------------------------
block = gg.list {
   name        = "statements block",
   terminators = block_terminators,
   primary     = function (lx)
      -- FIXME use gg.optkeyword()
      local x = stat (lx)
      if lx:is_keyword (lx:peek(), ";") then lx:next() end
      return x
   end }

--------------------------------------------------------------------------------
-- Helper function for "return <expr_list>" parsing.
-- Called when parsing return statements.
-- The specific test for initial ";" is because it's not a block terminator,
-- so without itgg.list would choke on "return ;" statements.
-- We don't make a modified copy of block_terminators because this list
-- is sometimes modified at runtime, and the return parser would get out of
-- sync if it was relying on a copy.
--------------------------------------------------------------------------------
local return_expr_list_parser = gg.multisequence{
   { ";" , builder = function() return { } end }, 
   default = gg.list { 
      expr, separators = ",", terminators = block_terminators } }

--------------------------------------------------------------------------------
-- for header, between [for] and [do] (exclusive).
-- Return the `Forxxx{...} AST, without the body element (the last one).
--------------------------------------------------------------------------------
function for_header (lx)
    local vars = mlp.id_list(lx)
    if lx :is_keyword (lx:peek(), "=") then       
        if #vars ~= 1 then 
            return gg.parse_error (lx, "numeric for only accepts one variable")
        end
        lx:next() -- skip "="
        local exprs = expr_list (lx)
        if #exprs < 2 or #exprs > 3 then
            return gg.parse_error (lx, "numeric for requires 2 or 3 boundaries")
        end
        return { tag="Fornum", vars[1], unpack (exprs) }
    else
        if not lx :is_keyword (lx :next(), "in") then
            return gg.parse_error (lx, '"=" or "in" expected in for loop')
        end
        local exprs = expr_list (lx)
        return { tag="Forin", vars, exprs }
    end
end

--------------------------------------------------------------------------------
-- Function def parser helper: id ( . id ) *
--------------------------------------------------------------------------------
local function fn_builder (list)
   local r = list[1]
   for i = 2, #list do r = { tag="Index", r, id2string(list[i]) } end
   return r
end
local func_name = gg.list{ id, separators = ".", builder = fn_builder }

--------------------------------------------------------------------------------
-- Function def parser helper: ( : id )?
--------------------------------------------------------------------------------
local method_name = gg.onkeyword{ name = "method invocation", ":", id, 
   transformers = { function(x) return x and x.tag=='Id' and id2string(x) end } }

--------------------------------------------------------------------------------
-- Function def builder
--------------------------------------------------------------------------------
local function funcdef_builder(x)

   local name   = x[1] or gg.earlier_error()
   local method = x[2]
   local func   = x[3] or gg.earlier_error()


   if method then 
      name = { tag="Index", name, method, lineinfo = {
         first = name.lineinfo.first,
         last  = method.lineinfo.last } }
      _G.table.insert (func[1], 1, {tag="Id", "self"}) 
   end
   local r = { tag="Set", {name}, {func} } 
   r[1].lineinfo = name.lineinfo
   r[2].lineinfo = func.lineinfo
   return r
end 


--------------------------------------------------------------------------------
-- if statement builder
--------------------------------------------------------------------------------
local function if_builder (x)
   local cb_pairs, else_block, r = x[1], x[2], {tag="If"}
   if cb_pairs.tag=='Error' then return cb_pairs end -- propagate errors 
   local n_pairs = #cb_pairs
   for i = 1, n_pairs do
       local cond, block = unpack(cb_pairs[i])
       r[2*i-1], r[2*i] = cond, block
   end
   if else_block then r[#r+1] = else_block end
   return r
end 

--------------------------------------------------------------------------------
-- produce a list of (expr,block) pairs
--------------------------------------------------------------------------------
local elseifs_parser = gg.list {
   gg.sequence { expr, "then", block, name='if/then block' },
   separators  = "elseif",
   terminators = { "else", "end" } }

--------------------------------------------------------------------------------
-- assignments and calls: statements that don't start with a keyword
--------------------------------------------------------------------------------
local function assign_or_call_stat_parser (lx)
   local e = expr_list (lx)
   local a = lx:is_keyword(lx:peek())
   local op = a and stat.assignments[a]
   if op then
      --FIXME: check that [e] is a LHS
      lx:next()
      local v = expr_list (lx)
      if type(op)=="string" then return { tag=op, e, v }
      else return op (e, v) end
   else 
      assert (#e > 0)
      if #e > 1 then 
         return gg.parse_error (lx, 
            "comma is not a valid statement separator; statement can be "..
            "separated by semicolons, or not separated at all") end
      if e[1].tag ~= "Call" and e[1].tag ~= "Invoke" then
         local typename
         if e[1].tag == 'Id' then 
            typename = '("'..e[1][1]..'") is an identifier'
         elseif e[1].tag == 'Op' then 
            typename = "is an arithmetic operation"
         else typename = "is of type '"..(e[1].tag or "<list>").."'" end

         return gg.parse_error (lx, "This expression " .. typename ..
            "; a statement was expected, and only function and method call "..
            "expressions can be used as statements");
      end
      return e[1]
   end
end

local_stat_parser = gg.multisequence{
   -- local function <name> <func_val>
   { "function", id, func_val, builder = 
      function(x) 
         local vars = { x[1], lineinfo = x[1].lineinfo }
         local vals = { x[2], lineinfo = x[2].lineinfo }
         return { tag="Localrec", vars, vals } 
      end },
   -- local <id_list> ( = <expr_list> )?
   default = gg.sequence{ id_list, gg.onkeyword{ "=", expr_list },
      builder = function(x) return {tag="Local", x[1], x[2] or { } } end } }

--------------------------------------------------------------------------------
-- statement
--------------------------------------------------------------------------------
stat = gg.multisequence { 
   name="statement",
   { "do", block, "end", builder = 
      function (x) return { tag="Do", unpack (x[1]) } end },
   { "for", for_header, "do", block, "end", builder = 
      function (x) x[1][#x[1]+1] = x[2]; return x[1] end },
   { "function", func_name, method_name, func_val, builder=funcdef_builder },
   { "while", expr, "do", block, "end", builder = "While" },
   { "repeat", block, "until", expr, builder = "Repeat" },
   { "local", local_stat_parser, builder = fget (1) },
   { "return", return_expr_list_parser, builder = fget (1, "Return") },
   { "break", builder = function() return { tag="Break" } end },
   { "-{", splice_content, "}", builder = fget(1) },
   { "if", gg.nonempty(elseifs_parser), gg.onkeyword{ "else", block }, "end", 
     builder = if_builder },
   default = assign_or_call_stat_parser }

stat.assignments = {
   ["="] = "Set" }

stat.dontfail = true
function stat.assignments:add(k, v) self[k] = v end
