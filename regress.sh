#!/bin/sh

$BP_FE_DIR/regress.sh  $1
$BP_BE_DIR/regress.sh  $1
$BP_ME_DIR/regress.sh  $1
$BP_TOP_DIR/regress.sh $1

