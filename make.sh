#! /bin/sh

# --- BEGINNING OF USER-EDITABLE PART ---

# Metalua sources
BASE=${PWD}

# Temporary building location.
# Upon installation, everything will be moved to ${INSTALL_LIB} and ${INSTALL_BIN}

if [ -z "${BUILD}" ]; then
  BUILD=$(mkdir -p ../build; cd ../build; pwd)
fi

if [ -z "${BUILD_BIN}" ]; then
  BUILD_BIN=${BUILD}/bin
fi

if [ -z "${BUILD_LIB}" ]; then
  BUILD_LIB=${BUILD}/lib
fi

# Where to place the final results
# DESTDIR=
# INSTALL_BIN=/usr/local/bin
# INSTALL_LIB=/usr/local/lib/lua/5.1
if [ -z "${INSTALL_BIN}" ]; then
  INSTALL_BIN=~/local/bin
fi

if [ -z "${INSTALL_LIB}" ]; then
  INSTALL_LIB=~/local/lib/lua
fi

# Where to find Lua executables.
# On many Debian-based systems, those can be installed with "sudo apt-get install lua5.1"
LUA=$(which lua)
LUAC=$(which luac)

# --- END OF USER-EDITABLE PART ---

if [ -z ${LUA}  ] ; then echo "Error: no lua interpreter found"; exit 1; fi
if [ -z ${LUAC} ] ; then echo "Error: no lua compiler found"; exit 1; fi

if [ -f ~/.metaluabuildrc ] ; then . ~/.metaluabuildrc; fi

if [ -z "$LINEREADER" ] ; then LINEREADER=$(which rlwrap); fi

if [ -z "$LINEREADER" ] ; then
    echo "Warning, rlwrap not found, no line editor support for interactive mode"
    echo "Consider performing the equivalent of 'sudo apt-get install rlwrap'."
fi

echo '*** Lua paths setup ***'

export LUA_PATH="?.luac;?.lua;${BUILD_LIB}/?.luac;${BUILD_LIB}/?.lua"
export LUA_MPATH="?.mlua;${BUILD_LIB}/?.mlua"

echo '*** Create the distribution directories, populate them with lib sources ***'

mkdir -p ${BUILD_BIN}
mkdir -p ${BUILD_LIB}
cp -Rp lib/* ${BUILD_LIB}/
# cp -Rp bin/* ${BUILD_BIN}/ # No binaries provided for unix (for now)

echo '*** Generating a callable metalua shell script ***'

cat > ${BUILD_BIN}/metalua <<EOF
#!/bin/sh
export LUA_PATH='?.luac;?.lua;${BUILD_LIB}/?.luac;${BUILD_LIB}/?.lua'
export LUA_MPATH='?.mlua;${BUILD_LIB}/?.mlua'
exec ${LINEREADER} ${LUA} ${BUILD_LIB}/metalua.luac \$*
EOF
chmod a+x ${BUILD_BIN}/metalua

echo '*** Compiling the parts of the compiler written in plain Lua ***'

cd compiler
${LUAC} -o ${BUILD_LIB}/metalua/bytecode.luac lopcodes.lua lcode.lua ldump.lua compile.lua || exit 1
${LUAC} -o ${BUILD_LIB}/metalua/mlp.luac lexer.lua gg.lua mlp_lexer.lua mlp_misc.lua mlp_table.lua mlp_meta.lua mlp_expr.lua mlp_stat.lua mlp_ext.lua || exit 1
cd ..

echo '*** Bootstrap the parts of the compiler written in metalua ***'

${LUA} ${BASE}/build-utils/bootstrap.lua ${BASE}/compiler/mlc.mlua output=${BUILD_LIB}/metalua/mlc.luac
${LUA} ${BASE}/build-utils/bootstrap.lua ${BASE}/compiler/metalua.mlua output=${BUILD_LIB}/metalua.luac
${LUA} ${BASE}/build-utils/bootstrap.lua ${BASE}/lib/metalua/treequery/walk.mlua output=${BUILD_LIB}/metalua/treequery/walk.luac

echo '*** Finish the bootstrap: recompile the metalua parts of the compiler with itself ***'

${BUILD_BIN}/metalua -vb -f compiler/mlc.mlua     -o ${BUILD_LIB}/metalua/mlc.luac
${BUILD_BIN}/metalua -vb -f compiler/metalua.mlua -o ${BUILD_LIB}/metalua.luac
${BUILD_BIN}/metalua -vb -f lib/metalua/treequery/walk.mlua -o ${BUILD_LIB}/metalua/treequery/walk.luac

echo '*** Precompile metalua libraries ***'
for SRC in $(find ${BUILD_LIB} -name '*.mlua'); do
    DST=$(dirname $SRC)/$(basename $SRC .mlua).luac
    if [ $DST -nt $SRC ]; then
        echo "+ $DST already up-to-date"
    else
        echo "- $DST generated from $SRC"
        ${BUILD_BIN}/metalua $SRC -o $DST
    fi
done

echo '*** Generate make-install.sh script ***'

cat > make-install.sh <<EOF2
#!/bin/sh
mkdir -p ${INSTALL_BIN}
mkdir -p ${INSTALL_LIB}
if [ -n "${DESTDIR}" ]; then
    mkdir -p ${DESTDIR}${INSTALL_BIN}
    mkdir -p ${DESTDIR}${INSTALL_LIB}
fi
cat > ${DESTDIR}${INSTALL_BIN}/metalua <<EOF
#!/bin/sh
METALUA_LIB=${INSTALL_LIB}
export LUA_PATH="?.luac;?.lua;\\\${METALUA_LIB}/?.luac;\\\${METALUA_LIB}/?.lua"
export LUA_MPATH="?.mlua;\\\${METALUA_LIB}/?.mlua"
exec ${LINEREADER} ${LUA} \\\${METALUA_LIB}/metalua.luac "\\\$@"
EOF

chmod a+x ${DESTDIR}${INSTALL_BIN}/metalua

cp -pR ${BUILD_LIB}/* ${DESTDIR}${INSTALL_LIB}/

echo "metalua libs installed in ${INSTALL_LIB};"
echo "metalua executable in ${INSTALL_BIN}."
EOF2
chmod a+x make-install.sh

echo
echo "Build completed, proceed to installation with './make-install.sh' or 'sudo ./make-install.sh'"
echo
