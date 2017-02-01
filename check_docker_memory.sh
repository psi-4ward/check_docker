#!/usr/bin/env bash
#############################################################
# Check the memory consumption of running docker containers
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

# Set help
print_help () {
  echo "Usage: $SCRIPTNAME [-w <warning>] [-c <critical>]"
  echo ""
  echo "This plugin checks memory consumption of running docker containers."
  echo ""
  echo "Warn and crit thresholds are MB or %."
  echo "To use a relative value append a % sign. The value is calculated using"
  echo "the cgroup memory-limit or if its not set, the available system memory."
  echo "Omit -w and -c to return OK for every value"
  echo "Omit -i and -n to check all running containers"
  echo ""
  echo "Options:"
  echo "  -h                   Prints this helpscreen"
  echo "  -v                   Prints the version"
  echo "  -f <filter>          docker ps --filter value"
  echo "  -n <containerName>   Name of the running docker container"
  echo "  -i <containerId>     CID"
  echo "  -w <warning>         Warning threshold in MB. To use percentage append %"
  echo "  -c <critical>        Critical threshold in MB. To use percentage append %"
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
  CIDS="$(docker ps -q $FILTER)"
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

  # Read the values
  LIMIT=`cat /sys/fs/cgroup/memory/docker/$CID*/memory.limit_in_bytes 2>/dev/null || echo ""`
  USAGE=`cat /sys/fs/cgroup/memory/docker/$CID*/memory.usage_in_bytes 2>/dev/null || echo ""`

  if [ "$LIMIT" == "" ] || [ "$USAGE" == "" ] ; then
    >&2 echo "Error: Could not read cgroup values for $CNAME. Is the container running and cgroup_enable=memory?"
    setExitState $STATE_UNKNOWN
    continue;
  fi

  # Set *nolimit* to system maximum
  if [ ${#LIMIT} -gt 12 ] ; then
    LIMIT=`cat /proc/meminfo | grep MemTotal | awk '{ print $2 }'`
    LIMIT=$(perl -e "printf('%u', $LIMIT*1024)")
  fi
  USAGE_MB=$(perl -e "printf('%u', $USAGE/1024/1024)")
  LIMIT_MB=$(perl -e "printf('%u', $LIMIT/1024/1024)")
  USAGE_PERC=$(perl -e "printf('%u', $USAGE_MB/$LIMIT_MB*100)")

  # Calc warn value
  if [ "$WARN" != "" ]; then
    if [ "${WARN: -1}" == "%" ] ; then
      WARN_VAL=$(perl -e "printf('%u', $LIMIT_MB*${WARN:0:-1}/100)")
    else
      WARN_VAL=$WARN
    fi
  fi

  # Calc warn value
  if [ -n "$CRIT" ]; then
    if [ "${CRIT: -1}" == "%" ] ; then
      CRIT_VAL=$(perl -e "printf('%u', $LIMIT_MB*${CRIT:0:-1}/100)")
    else
      CRIT_VAL=$CRIT
    fi
  fi

  RES="$CNAME: ${USAGE_MB}MB $USAGE_PERC%\n"

  if [ -n "$CRIT" ] && [ "$USAGE_MB" -gt "$CRIT_VAL" ] ; then
    RESULT="CRITICAL ${RES}${RESULT}"
    setExitState $STATE_CRITICAL
  elif [ -n "$WARN" ] && [ "$USAGE_MB" -gt "$WARN_VAL" ] ; then
    RESULT="${RESULT}WARNING ${RES}"
    setExitState $STATE_WARNING
  fi

  PERFDATA="$PERFDATA $CNAME=${USAGE_MB}MB;$WARN_VAL;$CRIT_VAL;0;$LIMIT_MB"

done

echo -en ${RESULT:-"OK "}
echo $PERFDATA


exit $EXIT_STATE

