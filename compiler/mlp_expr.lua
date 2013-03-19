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

--------------------------------------------------------------------------------
--
-- Exported API:
-- * [mlp.expr()]
-- * [mlp.expr_list()]
-- * [mlp.func_val()]
--
--------------------------------------------------------------------------------

--require "gg"
--require "mlp_misc"
--require "mlp_table"
--require "mlp_meta"

--------------------------------------------------------------------------------
-- These function wrappers (eta-expansions actually) are just here to break
-- some circular dependencies between mlp_xxx.lua files.
--------------------------------------------------------------------------------
local function _expr (lx) return  mlp.expr (lx) end
local function block (lx) return mlp.block (lx) end
local function stat  (lx) return mlp.stat (lx)  end

local function _table_content (lx) return mlp.table_content (lx) end

module ("mlp", package.seeall)

--------------------------------------------------------------------------------
-- Non-empty expression list. Actually, this isn't used here, but that's
-- handy to give to users.
--------------------------------------------------------------------------------
expr_list = gg.list{ _expr, separators = "," }

--------------------------------------------------------------------------------
-- Helpers for function applications / method applications
--------------------------------------------------------------------------------
func_args_content = gg.list { 
   name = "function arguments",
   _expr, separators = ",", terminators = ")" } 

-- Used to parse methods
method_args = gg.multisequence{
   name = "function argument(s)",
   { "{", table_content, "}" },
   { "(", func_args_content, ")", builder = fget(1) },
   { "+{", quote_content, "}" }, 
   function(lx) local r = opt_string(lx); return r and {r} or { } end }

--------------------------------------------------------------------------------
-- [func_val] parses a function, from opening parameters parenthese to
-- "end" keyword included. Used for anonymous functions as well as
-- function declaration statements (both local and global).
--
-- It's wrapped in a [_func_val] eta expansion, so that when expr
-- parser uses the latter, they will notice updates of [func_val]
-- definitions.
--------------------------------------------------------------------------------
func_params_content = gg.list{ name="function parameters",
   gg.multisequence{ { "...", builder = "Dots" }, id },
   separators  = ",", terminators = {")", "|"} } 

local _func_params_content = function (lx) return func_params_content(lx) end

func_val = gg.sequence { name="function body",
   "(", func_params_content, ")", block, "end", builder = "Function" }

local _func_val = function (lx) return func_val(lx) end

--------------------------------------------------------------------------------
-- Default parser for primary expressions
--------------------------------------------------------------------------------
function id_or_literal (lx)
   local a = lx:next()
   if a.tag~="Id" and a.tag~="String" and a.tag~="Number" then
      local msg
      if a.tag=='Eof' then
         msg = "End of file reached when an expression was expected"
      elseif a.tag=='Keyword' then
         msg = "An expression was expected, and `"..a[1]..
            "' can't start an expression"
      else
         msg = "Unexpected expr token " .. _G.table.tostring (a, 'nohash')
      end
      return gg.parse_error (lx, msg)
   end
   return a
end


--------------------------------------------------------------------------------
-- Builder generator for operators. Wouldn't be worth it if "|x|" notation
-- were allowed, but then lua 5.1 wouldn't compile it 
--------------------------------------------------------------------------------

-- opf1 = |op| |_,a| `Op{ op, a }
local function opf1 (op) return 
   function (_,a) return { tag="Op", op, a } end end

-- opf2 = |op| |a,_,b| `Op{ op, a, b }
local function opf2 (op) return 
   function (a,_,b) return { tag="Op", op, a, b } end end

-- opf2r = |op| |a,_,b| `Op{ op, b, a } -- (args reversed)
local function opf2r (op) return 
   function (a,_,b) return { tag="Op", op, b, a } end end

local function op_ne(a, _, b) 
   -- The first version guarantees to return the same code as Lua,
   -- but it relies on the non-standard 'ne' operator, which has been
   -- suppressed from the official AST grammar (although still supported
   -- in practice by the compiler).
   -- return { tag="Op", "ne", a, b }
   return { tag="Op", "not", { tag="Op", "eq", a, b, lineinfo= {
            first = a.lineinfo.first, last = b.lineinfo.last } } }
end
   

--------------------------------------------------------------------------------
--
-- complete expression
--
--------------------------------------------------------------------------------

-- FIXME: set line number. In [expr] transformers probably

expr = gg.expr { name = "expression",

   primary = gg.multisequence{ name="expr primary",
      { "(", _expr, ")",           builder = "Paren" },
      { "function", _func_val,     builder = fget(1) },
      { "-{", splice_content, "}", builder = fget(1) },
      { "+{", quote_content, "}",  builder = fget(1) }, 
      { "nil",                     builder = "Nil" },
      { "true",                    builder = "True" },
      { "false",                   builder = "False" },
      { "...",                     builder = "Dots" },
      table,
      id_or_literal },

   infix = { name="expr infix op",
      { "+",  prec = 60, builder = opf2 "add"  },
      { "-",  prec = 60, builder = opf2 "sub"  },
      { "*",  prec = 70, builder = opf2 "mul"  },
      { "/",  prec = 70, builder = opf2 "div"  },
      { "%",  prec = 70, builder = opf2 "mod"  },
      { "^",  prec = 90, builder = opf2 "pow",    assoc = "right" },
      { "..", prec = 40, builder = opf2 "concat", assoc = "right" },
      { "==", prec = 30, builder = opf2 "eq"  },
      { "~=", prec = 30, builder = op_ne  },
      { "<",  prec = 30, builder = opf2 "lt"  },
      { "<=", prec = 30, builder = opf2 "le"  },
      { ">",  prec = 30, builder = opf2r "lt"  },
      { ">=", prec = 30, builder = opf2r "le"  },
      { "and",prec = 20, builder = opf2 "and" },
      { "or", prec = 10, builder = opf2 "or"  } },

   prefix = { name="expr prefix op",
      { "not", prec = 80, builder = opf1 "not" },
      { "#",   prec = 80, builder = opf1 "len" },
      { "-",   prec = 80, builder = opf1 "unm" } },

   suffix = { name="expr suffix op",
      { "[", _expr, "]", builder = function (tab, idx) 
         return {tag="Index", tab, idx[1]} end},
      { ".", id, builder = function (tab, field) 
         return {tag="Index", tab, id2string(field[1])} end },
      { "(", func_args_content, ")", builder = function(f, args) 
         return {tag="Call", f, unpack(args[1])} end },
      { "{", _table_content, "}", builder = function (f, arg)
         return {tag="Call", f, arg[1]} end},
      { ":", id, method_args, builder = function (obj, post)
         return {tag="Invoke", obj, id2string(post[1]), unpack(post[2])} end},
      { "+{", quote_content, "}", builder = function (f, arg) 
         return {tag="Call", f,  arg[1] } end },
      default = { name="opt_string_arg", parse = mlp.opt_string, builder = function(f, arg) 
         return {tag="Call", f, arg } end } } }
