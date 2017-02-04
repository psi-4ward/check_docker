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

EXITFILTER="ok"

# Set help
print_help () {
  echo "Usage: $SCRIPTNAME [-e <crit|warn>] [-f <filter>]"
  echo ""
  echo "This plugin checks the state of running docker containers."
  echo ""
  echo "It returns a warning if there are any freshly restarted containers."
  echo ""
  echo "It returns CRIT for any container that are neither \"Up\""
  echo "nor \"healthy\""
  echo ""
  echo "Options:"
  echo "  -h                     Prints this helpscreen"
  echo "  -v                     Prints the version"
  echo "  -e <crit|warn>         Explicitly handle exited containers. Otherwise exited containers are ignored."
  echo "  -f <filter>            docker ps --filter value"
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
    -e)
      EXITFILTER="$2"
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

  PAUSED=$(echo $LINE | cut -d" " -f5)
  if [ $PAUSED == '(Paused)' ] ; then
    if [ $EXIT_STATE == $STATE_OK ]; then
      EXIT_STATE=$STATE_WARNING;
    fi;
    CONTAINERS_WARN+=("$LINE");
    continue;
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
        if [ $EXIT_STATE == $STATE_OK ]; then
          EXIT_STATE=$STATE_WARNING;
        fi;
        CONTAINERS_WARN+=("$LINE");
      fi
    ;;
    Exited)
      if [ $EXITFILTER == "crit" ]; then
        EXIT_STATE=$STATE_CRITICAL
        CONTAINERS_CRITICAL+=("$LINE");
      fi
      if [ $EXITFILTER == "warn" ]; then
        if [ $EXIT_STATE == $STATE_OK ]; then
          EXIT_STATE=$STATE_WARNING;
        fi;
        CONTAINERS_WARN+=("$LINE");
      fi
    ;;
    ## TODO: check if this output can really happen
    Dead)
      EXIT_STATE=$STATE_CRITICAL
      CONTAINERS_CRITICAL+=("$LINE");
    ;;
    *)
     >&2 echo "unkown state "$STATE;
     if [ $EXIT_STATE == $STATE_OK ]; then
       EXIT_STATE=$STATE_UNKNOWN;
     fi;
  esac
done < <(docker ps -a --format '{{.Names}} {{.Status}}' $FILTER)

[ $EXIT_STATE == $STATE_OK ] && echo OK

if [ ${#CONTAINERS_CRITICAL[@]} -gt 0 ]; then
  printf 'CRITICAL: %s\n' "${CONTAINERS_CRITICAL[@]}"
fi;
if [ ${#CONTAINERS_WARN[@]} -gt 0 ]; then
  printf 'WARNING: %s\n' "${CONTAINERS_WARN[@]}"
fi;

exit $EXIT_STATE

