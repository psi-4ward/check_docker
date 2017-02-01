#!/usr/bin/env bash
#############################################################
# Check the state of running containers
#
# Licence: LGPL
# Author: Christoph Wiechert <wio@psitrx.de>
#############################################################

# Set States
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

SCRIPTNAME=$0
VERSION=1.0.0

# Set help
print_help () {
  echo "Usage: $SCRIPTNAME [-w <warning>] [-c <critical>]"
  echo ""
  echo "This plugin checks the state of running docker containers."
  echo ""
  echo "Returns with CRIT with any container are not \"Up\""
  echo "or \"unhealthy\""
  echo ""
  echo "Options:"
  echo "  -h                   Prints this helpscreen"
  echo "  -v                   Prints the version"
  echo "  -f <filter>          docker ps --filter value"
  echo ""
}

set -e

# Parse CLI args
while [[ $# > 0 ]]; do
  key=$1
  case "$key" in
    -h|--help)
      print_help
      exit 0
    ;;
    -v|--version)
      echo $VERSION
      exit 0
    ;;
    -f)
      FILTER="$2"
      shift
    ;;
    *)
      >&2 echo "Ignoring unknown option $key"
    ;;
  esac
  shift # past argument or value
done

[ -n "$FILTER" ] && FILTER="-f $FILTER"

EXIT_STATE=$STATE_OK

while read LINE ; do
  STATE=$(echo $LINE | cut -d" " -f2)
  if [ "$STATE" != "Up" ] || echo $LINE | grep -qF unhealthy ; then
    echo $LINE
    EXIT_STATE=$STATE_CRITICAL
  fi
done < <(docker ps --format '{{.Names}} {{.Status}}' $FILTER)

[ $EXIT_STATE == $STATE_OK ] && echo OK

exit $EXIT_STATE

