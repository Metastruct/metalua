--*-lua-*--
package = "metalua-parser"
version = "0.7.3-1"
source = {
  url = "http://git.eclipse.org/c/koneki/org.eclipse.koneki.metalua.git/snapshot/v0.7.3.tar.gz"
}
description = {
  summary = "Metalua: parser, compiler and command line interface.",
  detailed = "Just enabling metalua-compiler powers to command line.",
  homepage = "http://git.eclipse.org/c/koneki/org.eclipse.koneki.metalua.git",
  license = "EPL + MIT"
}
dependencies = {
  "alt-getopt >= 0.7",
  "checks >= 1.0",
  "metalua-compiler == 0.7.3",
  platforms = {
    unix = {
      "readline >= 1.3", -- Better REPL experience
    }
  }
}
build = {
  type="builtin",
  bin = {
    metalua = 'bin/metalua'
  }
}
