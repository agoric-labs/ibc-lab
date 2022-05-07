#! /bin/bash
hermes ${1+"$@"} &
while sleep 30; do :; done
