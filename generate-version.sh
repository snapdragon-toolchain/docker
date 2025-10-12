#!/usr/bin/env bash
#

ROOTDIR=$(dirname $0)

if [ -r $ROOTDIR/.git ]; then
    # Found git repo
    git --git-dir=$ROOTDIR/.git describe --tags --abbrev=14
    exit 0
fi

if [ -r $ROOTDIR/default-version ]; then
    cat $ROOTDIR/default-version
    exit 0
fi

# Just use latest by default if we don't have git repo or default-version
echo latest
