#!/usr/bin/env bash
#############################################################
# Check the network io of running docker containers
# by reading proc information
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

TMPDIR=/tmp/check_docker_net

# Set help
print_help () {
  echo "Usage: $SCRIPTNAME [-w <warning>] [-c <critical>]"
  echo ""
  echo "This plugin checks network io for running docker containers."
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
  echo "  -w <warning>         Warning threshold in MB."
  echo "  -c <critical>        Critical threshold in MB."
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
      >&2 echo "Ignoring unknowen option $key"
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

function setExistState() {
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
  CPID=$(docker inspect -f '{{.State.Pid}}' $CID)
  NOW=$(expr `date +"%s"` \* 1000000000 + `date +"%N"`)

  # Read the values and sum interfaces
  RX=0 ; TX=0
  while read -r line; do
    RX=$(($RX + $(echo $line | awk '{print $2}')))
    TX=$(($TX + $(echo $line | awk '{print $10}')))
  done <<< "$(cat /proc/$CPID/net/dev | tail -n +3 | grep -vF lo:)"

  # Load values from last run
  [ -e "$TMPDIR/$CID" ] && source $TMPDIR/$CID

  # Save current values
  echo "LAST_NOW=$NOW" > $TMPDIR/$CID
  echo "LAST_RX=$RX" >> $TMPDIR/$CID
  echo "LAST_TX=$TX" >> $TMPDIR/$CID

  if [ "$LAST_NOW" == "" ]; then
    # This is the first run for this container, wait for second to get a delta
    echo "First run $CNAME"
    continue;
  fi

  ELAPSED_TIME=$(($NOW - $LAST_NOW))
  RX=$(($RX - $LAST_RX))
  TX=$(($TX - $LAST_TX))
  TOTAL=$(($RX + $TX))
  TOTAL_MB=$(perl -e "printf('%u', $TOTAL/1024/1024)")
  [ -n "$WARN" ] && WARN_BYTE=$(perl -e "printf('%u', $WARN * 1024 * 1024)")
  [ -n "$CRIT" ] && CRIT_BYTE=$(perl -e "printf('%u', $CRIT * 1024 * 1024)")

  if [ -n "$CRIT" ] && [ "$TOTAL_MB" -gt "$CRIT" ] ; then
    RESULT="CRITICAL ${CNAME}: ${TOTAL_MB}\n${RESULT}"
    setExistState $STATE_CRITICAL
  elif [ -n "$WARN" ] && [ "$TOTAL_MB" -gt "$WARN" ] ; then
    RESULT="WARNING ${CNAME}: ${TOTAL_MB}\n${RESULT}"
    setExistState $STATE_WARNING
  fi

  PERFDATA="$PERFDATA ${CNAME}=${RX}B;$WARN_BYTE;$CRIT_BYTE;0; ${CNAME}_RX=${RX}B;;;0; ${CNAME}_TX=${TX}B;;;0;"
done

echo -en ${RESULT:-"OK "}
echo $PERFDATA

# remove tmp files older than 3 days
find $TMPDIR -maxdepth 1 -type f -mtime +3 -exec rm {} \;

exit $EXIT_STATE

