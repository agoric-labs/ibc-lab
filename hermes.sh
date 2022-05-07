#! /bin/bash

thisdir=$PWD

IMAGE_HERMES=${IMAGE_HERMES-informalsystems/hermes:0.14.1}

opts="-v$thisdir/hermes-home:/home/hermes:z -v$thisdir:/config $IMAGE_HERMES -c /config/hermes.config"
interaction=-it

case $1 in
-d | --detach) interaction=--detach; shift ;;
esac

case $1 in
start)
  exec docker run --rm $interaction --entrypoint=/config/start.sh $opts ${1+"$@"}
  ;;
esac

exec docker run --rm $interaction $opts ${1+"$@"}
