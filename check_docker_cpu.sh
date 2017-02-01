#!/usr/bin/env bash
#############################################################
# Check the cpu consumption of running docker containers
# by reading cgroup information
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

TMPDIR=/tmp/check_docker_cpu

# Set help
print_help () {
  echo "Usage: $SCRIPTNAME [-w <warning>] [-c <critical>]"
  echo ""
  echo "This plugin checks network io of running docker containers."
  echo ""
  echo "Warn and crit thresholds per check cycle in MB."
  echo "Omit -w and -c to return OK for every value"
  echo "Omit -i and -n to check all running containers"
  echo ""
  echo "Options:"
  echo "  -h                   Prints this helpscreen"
  echo "  -v                   Prints the version"
  echo "  -f <filter>          docker ps --filter value"
  echo "  -n <containerName>   Name of the running docker container"
  echo "  -i <containerId>     CID"
  echo "  -w <warning>         Warning threshold in percent."
  echo "  -c <critical>        Critical threshold in percent."
  echo ""
}

set -e

mkdir -p $TMPDIR
if [ ! -w $TMPDIR ]; then
 >&2 echo "Error: $TMPDIR not writeable"
 exit $STATE_UNKNOWN
fi

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
    -n)
      CONTAINER_NAME="$2"
      shift
    ;;
    -i)
      CONTAINER_ID="$2"
      shift
    ;;
    -f)
      FILTER="$2"
      shift
    ;;
    -w)
      WARN="$2"
      shift
    ;;
    -c)
      CRIT="$2"
      shift
    ;;
    *)
      >&2 echo "Ignoring unknown option $key"
    ;;
  esac
  shift # past argument or value
done


# Resolve ContainerName to CID
if [ -n "$CONTAINER_NAME" ]; then
  CONTAINER_ID=$(docker ps | grep -E "$CONTAINER_NAME[ ]*$" | cut -d " " -f 1)
  if [ "$CONTAINER_ID" == "" ] ; then
    >&2 echo "Error: Could not find CID for $CONTAINER_NAME. Is the container running?"
    exit $STATE_UNKNOWN
  fi
fi

# Populate CIDs
if [ -n "$CONTAINER_ID" ] ; then
  CIDS=$CONTAINER_ID
else
  [ -n "$FILTER" ] && FILTER="-f $FILTER"
  CIDS="$(docker ps -q)"
fi

EXIT_STATE=$STATE_OK

function setExitState() {
  if [ $1 -gt $EXIT_STATE ]; then
    [ $1 -eq $STATE_UNKNOWN ] && [ $EXIT_STATE -ne $STATE_OK ] && return
    EXIT_STATE=$1
  fi
}

RESULT=""
PERFDATA=" | "

for CID in $CIDS; do
  # Resolve ContainerName
  CNAME=$(docker inspect -f '{{.Name}}' $CID)
  CNAME=${CNAME:1} # strip trailing /
  USAGE=$(cat /sys/fs/cgroup/cpu,cpuacct/docker/$CID*/cpuacct.usage)
  NOW=$(expr `date +"%s"` \* 1000000000 + `date +"%N"`)

  # Load values from last run
  [ -e "$TMPDIR/$CID" ] && source $TMPDIR/$CID

  # Save current values
  echo "LAST_NOW=$NOW" > $TMPDIR/$CID
  echo "LAST_USAGE=$USAGE" >> $TMPDIR/$CID

  if [ "$LAST_NOW" == "" ]; then
    # This is the first run for this container, wait for second to get a delta
    echo "First run $CNAME"
    continue;
  fi

  ELAPSED_TIME=$(($NOW - $LAST_NOW))
  USAGE=$(($USAGE - $LAST_USAGE))
  PERCENT=$(expr $USAGE \* 100 / $ELAPSED_TIME / `nproc` || true)

  if [ -n "$CRIT" ] && [ "$PERCENT" -gt "$CRIT" ] ; then
    RESULT="CRITICAL ${CNAME}: ${PERCENT}\n${RESULT}"
    setExitState $STATE_CRITICAL
  elif [ -n "$WARN" ] && [ "$PERCENT" -gt "$WARN" ] ; then
    RESULT="WARNING ${CNAME}: ${PERCENT}\n${RESULT}"
    setExitState $STATE_WARNING
  fi

  PERFDATA="$PERFDATA ${CNAME}=${PERCENT}%;$WARN;$CRIT;0;100"
done

echo -en ${RESULT:-"OK "}
echo $PERFDATA

# remove tmp files older than 3 days
find $TMPDIR -maxdepth 1 -type f -mtime +3 -exec rm {} \;

exit $EXIT_STATE

