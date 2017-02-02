#!/usr/bin/env bash
#############################################################
# Check the state of running containers
#
# Licence: LGPL
# Author: Christoph Wiechert <wio@psitrx.de>
#############################################################

set -e

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

EXIT_STATE=$STATE_OK;
declare -a CONTAINERS_WARN;
declare -a CONTAINERS_CRIT;

while read LINE ; do

  STATE=$(echo $LINE | cut -d" " -f2)
  if [ "$STATE" != "Up" ] || echo $LINE | grep -qF unhealthy ; then
    EXIT_STATE=$STATE_CRITICAL
  fi

  case "$STATE" in
    Created)
    ;;
    Up)
    ;;
    Restarting)
      if echo $LINE | grep -qF "minutes ago"; then
        EXIT_STATE=$STATE_CRITICAL;
        CONTAINERS_CRITICAL+=("$LINE");
      else
        echo 2;
        if [ $EXIT_STATE == $STATE_OK ]; then
          EXIT_STATE=$STATE_WARNING;
        fi;
        CONTAINERS_WARN+=("$LINE");
      fi
    ;;
    Exited)
      EXIT_STATE=$STATE_CRITICAL
      CONTAINERS_CRITICAL+=("$LINE");
    ;;
    *)
     >&2 echo "unkown state "$STATE;
  esac
done < <(docker ps --format '{{.Names}} {{.Status}}' $FILTER)

[ $EXIT_STATE == $STATE_OK ] && echo OK

if [ ${#CONTAINERS_CRITICAL[@]} -gt 0 ]; then
  printf 'CRITICAL: %s\n' "${CONTAINERS_CRITICAL[@]}"
fi;
if [ ${#CONTAINERS_WARN[@]} -gt 0 ]; then
  printf 'WARNING: %s\n' "${CONTAINERS_WARN[@]}"
fi;

exit $EXIT_STATE

