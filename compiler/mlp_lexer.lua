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
-- Summary: Source file lexer. ~~Currently only works on strings.
-- Some API refactoring is needed.
--
----------------------------------------------------------------------

module ("mlp", package.seeall)

require "lexer"

local mlp_lexer = lexer.lexer:clone()

local keywords = {
    "and", "break", "do", "else", "elseif",
    "end", "false", "for", "function",
    "goto", -- Lua5.2
    "if",
    "in", "local", "nil", "not", "or", "repeat",
    "return", "then", "true", "until", "while",
    "...", "..", "==", ">=", "<=", "~=",
    "::", -- Lua5,2
    "+{", "-{" }
 
for w in values(keywords) do mlp_lexer:add(w) end

_M.lexer = mlp_lexer
