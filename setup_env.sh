#!/bin/sh

CWD=$PWD

# Set common environment variables
export BSG_IP_CORES_DIR=$CWD/bsg_ip_cores
export BSG_CADENV_DIR=$CWD/bsg_cadenv
export BP_COMMON_DIR=$CWD/bp_common
export BP_FE_DIR=$CWD/bp_fe
export BP_BE_DIR=$CWD/bp_be
export BP_ME_DIR=$CWD/bp_me
export BP_TOP_DIR=$CWD/bp_top
export BP_EXTERNAL_DIR=$CWD/external

# Override these tool paths if needed
export VCS=${VCS:-vcs}
export VERILATOR=${VERILATOR:-verilator}

# Needed for verilator g++ compilation
export VERILATOR_ROOT=$BP_EXTERNAL_DIR/
export SYSTEMC_INCLUDE=$BP_EXTERNAL_DIR/include
export SYSTEMC_LIBDIR=$BP_EXTERNAL_DIR/lib-linux64

# Add external tools to path
export PATH=$CWD/external/bin:$PATH
export LD_LIBRARY_PATH=$SYSTEMC_LIBDIR:$LD_LIBRARY_PATH

if [ "$1" = "tools" ]; then
  # Make external tools (uncomment whichever individual tool you would like to build)
  git submodule update --init --recursive
  make -C $CWD/external all
  #make -C $CWD/external verilator
  #make -C $CWD/external gnu
  #make -C $CWD/external fesvr
  #make -C $CWD/external spike
  #make -C $CWD/external axe
  git submodule deinit -f --all
fi

# HACK
rm -rf bsg_ip_cores
git submodule update --init bsg_ip_cores --depth 50

if [ "$1" = "roms" ]; then
  # Make test roms
  make -C $BP_FE_DIR/test/rom all clean
  make -C $BP_BE_DIR/test/rom all clean
  make -C $BP_ME_DIR/test/rom all clean
  make -C $BP_TOP_DIR/test/rom all clean
fi

