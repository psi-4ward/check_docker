# check_docker

Monitoring Plugins to check running docker contianers with perfdata support.  
Written in Bash.


## check_docker_memory

Check memory consumption of containers using cgroup `memory.usage_in_bytes`.  
Respects docker container resource limits.

```
Usage: ./check_docker_memory.sh [-w <warning>] [-c <critical>]

This plugin checks memory consumption for running docker containers.

Warn and crit thresholds could be MB or %.
To use a relative value append a % sign. The value is calculated using
the cgroup memory-limit or if its not set, the available system memory.
Omit -w and -c to return OK for every value
Omit -i and -n to check all running containers

Options:
  -h                   Prints this helpscreen
  -v                   Prints the version
  -f <filter>          docker ps --filter value
  -n <containerName>   Name of the running docker container
  -i <containerId>     CID
  -w <warning>         Warning threshold in MB. To use percentage append %
  -c <critical>        Critical threshold in MB. To use percentage append %

```

## check_docker_netio

Check network I/O of containers using proc.  
Prints only the delta since last run.  
Perfdata includes sum, RX, RX for each container.

```
Usage: ./check_docker_netio.sh [-w <warning>] [-c <critical>]

This plugin checks network io for running docker containers.

Warn and crit thresholds per check cycle in MB.
Omit -w and -c to return OK for every value
Omit -i and -n to check all running containers

Options:
  -h                   Prints this helpscreen
  -v                   Prints the version
  -f <filter>          docker ps --filter value
  -n <containerName>   Name of the running docker container
  -i <containerId>     CID
  -w <warning>         Warning threshold in MB.
  -c <critical>        Critical threshold in MB.
```

### Example

```
$ ./check_docker_netio.sh -w 200 -c 250 -f network=public

OK | nginx=47225B;209715200;262144000;0; nginx_RX=47225B;;;0; nginx_TX=18479B;;;0; psitransfer=0B;209715200;262144000;0; psitransfer_RX=0B;;;0; psitransfer_TX=0B;;;0;
```

## check_docker_cpu

Check CPU consumption of containers using jiffies

## check_docker_state

Checks state of running containers. It prints any conspicuity. If everything is fine it just prints "OK".
 
### Examples

```
$ ./check_docker_state.sh
OK
```


```
$ ./check_docker_state.sh
CRITICAL: meteor_run_2 Restarting (0) 45 minutes ago
```
