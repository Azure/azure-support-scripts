#!/usr/bin/env bash
#
# Azure/azure-support-scripts
# 
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# 
# MIT License
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the ""Software""), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify, merge,
# publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
# to whom the Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED *AS IS*, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT 
# NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE 
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Usage
#  Syntax: $0 [-h|-v]
#    options:"
#      -h     Print this Help.
#      -v     Verbose mode, up to -vvv.
#      -r     Always show the 'bash' report when spawning the python script
#
# Need 
# - disclaimers
# - eula - in bootstrap
# - any other legalease

# Version
VMASHVER="1.0.1"
# defaults for the script structure
DEBUG=""
BASHREPORT=""  # should we show the report from this script, even if it would normally be suppressed?
LOGDIR="/var/log/azure"
LOGFILE="$LOGDIR/"$(basename $0)".log"
FSFULLPCENT=80
STARTTIME=$(date --rfc-3339=seconds)

# Telemetry
AI_INSTRUMENTATION_KEY="deadbeef-dead-beef-dead-beefdeadbeef"
AI_ENDPOINT="https://dc.services.visualstudio.com/v2/track"


# logical variable defaults for values to be derived later
source /etc/os-release
DISTRO="tuxos"
PY="/usr/bin/python3"
PYCOUNT=0
PYSTAT=0  # we will use this variable to flag if it's ok to spawn the python sub-script or if we just error out here
SERVICE="waagent.service"
PKG="rpm"
DNF="dnf"
UNITFILE="/usr/bin/false"
UNITSTAT="undef"
UNITSTATRC=0

# process command-line switches
while getopts ":hvr" option; do
   case $option in
      h) # display Help
        echo "help would go here"
        exit;;
      v) # turn on verbose mode
        DEBUG=$((DEBUG+1))
        ;;
      r)
        BASHREPORT=1
        ;;
      \?) # Invalid option
        echo "Error: Invalid option"
        exit;;
   esac
done


# function definitions
function loggy {
  # simple logging handler
  # - writes output to the defined log file
  # - outputs to console if 'verbose' requested
  if [[ $DEBUG ]]; then
    echo "$1"
  fi
  echo "$(date +%FT%T%z) bash: $1" >> $LOGFILE
}

function testPyMod {
  # Test if a python module can be loaded by the given binary. Initial intention is for:
  # - testing if the agent module is usable
  # - testing for any modules we would need if we hand off to python for more diagnostics
  # Args 
  #   $1 = python version to use
  #   $2 = module to check
  # Return
  #   0 = module is fine
  #   1 = can't find module (might be present but not for the *given* python)

  PYOUT=$($1 << EOF

import importlib

def check_module(module_name):
  try:
    importlib.import_module(module_name)
    print("The module '%s' exists." % module_name)
    return 0
  except ImportError:
    print("Cannot load '%s'" % module_name)
    return 1
exit (check_module("$2"))
EOF
)
  RETVAL=$?
  loggy "Using $1 to test $2 module: $PYOUT"
  return $RETVAL
}

function help()
{
   # Display help block
   echo "Azure Agent health check script"
   echo
   echo "Syntax: $0 [-h|-v]"
   echo "options:"
   echo "-h     Print this Help."
   echo "-v     Verbose mode."
   echo "-r     Always show the 'bash' report"
   echo
}

function printColorCondition {
# Function to output a colored message, if the current terminal/output supports colors
# Args: state value, a message, and optionally the expected "good" value for 'state'.
#  If the condition matches the expected state, or is 0 by default as that is the 'success'
#   return code for any command, the message will be green.
#  if false, i.e. anything other than the passed good state or 0, then it will be red
#  could add a yellow if we find a good reason, but for now red and green will suffice
# arguments are
# 1 = state value to check
# 2 = string to ouput in color
# 3 = optional 'success' value to substutue for 0 (default when not specified)
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  NC='\033[0m' # No Color, aka reset when we're done coloring the text
  SUCCESS=0 # default 'good' value

  # see if we were passed a success flag
  if [ -n "$3" ] ; then
    SUCCESS=$3
  fi

  if [ $TERM ] ; then
    # echo in color because we're in a terminal
    if [ "$1" == "$SUCCESS" ] ; then
      echo -e $GREEN$2$NC
    else
      echo -e $RED$2$NC
    fi
  else
    # just echo it back out w/o color coding
    echo "$2"
  fi
}
# END function defs

## Start normal processing

# create the log file/directory once
if [ $EUID == 0 ]; then
  if [ ! -d $LOGDIR ]; then
    mkdir -p $LOGDIR
    logger "$0 created $LOGDIR for logging"
    loggy "Creating $LOGDIR - this could indicate larger problems such as no azure bits present"
  fi
else
  echo "Not running as root, logging may fail and some checks will not run"
fi

loggy "$0 version $VMASHVER started by $USER at $STARTTIME"

# do this in the main code body because it doesn't work inside a called function - the function wrapper makes it always false
if [ -t 1 ] ; then
  TERM=true
else
  TERM=false
fi

# distro determination
# Set this from sourcing os-release.  We'll have to be able to distill down all the different 'flavors' and how
#  they refer to themselves, into classes we will evaluate later
case "$ID_LIKE" in
  *fedora*|*centos*)
    DISTRO="redhat"
    if (( $(echo "$VERSION_ID < 8" | bc -l) )); then
      DNF="yum"
    fi
    ;;
  debian)
    DISTRO="debian"
    SERVICE="walinuxagent.service"
    PKG="dpkg"
    ;;
  suse)
    DISTRO="suse"
    ;;
  *)
    # The distro doesn't fall into one of the main families above, so just get us the actual value
    if [[ -z $ID_LIKE ]]; then
      DISTRO=$ID
    else
      DISTRO=$ID_LIKE
    fi
  ;;
esac
loggy "Distribution family found to be $DISTRO"

#### THIS CODE BLOCK IS REDUNDANT
# The base executable for the agent is always waagent, the difference is in how it's called and what python is being
#  called inside the exe... and maybe where it is located
loggy "Checking for agent executable"
EXE=$(which waagent)
if [ -z ${EXE} ] ; then
  # no agent found, maybe change a variable for later reference, but $EXE being 'null' should be good enough
  loggy "No waagent found inside of \$PATH - further tests may be invalid"
else
  loggy "Found waagent at $EXE"
  # pull the top line of the waagent 'executable' out and strip off #! to find out how we call 'python'
  # this probably should move down below, at which point this else block will be just for reporting/logging
  PY=$(head -n1 $EXE | cut -c 3-)
fi
#### END REDUNDANT

# We could either have one big if-fi structure checking distros and all the checks below in the per-distro blocks, or have these 
#  repeated if-fi blocks for the distro detection in each type of check. Pick your poison

# find the systemd unit for the Azure agent, what package owns it, and what repository that package came from
#  this is to catch any strange installations, and possibly the repo will indicate an appliance/custom image
#  - We could wrap this in a 'systemd check', but as of 2024 everything we care about runs systemd
UNITFILE=$(systemctl show $SERVICE -p FragmentPath | cut -d= -f2)
if [[ $UNITFILE ]]; then
  loggy "Agent systemd unit located at $UNITFILE"
  if [ "$(readlink -f $UNITFILE)" = "/dev/null" ]; then
    # sort of short-circuit the package check inf you got here, this is a masked unit and a lot of failures will happen
    OWNER="masked"
    REPO="masked"
  elif [[ $DISTRO == "debian" ]]; then
    OWNER=$($PKG -S $UNITFILE 2> /dev/null | cut -d: -f1)
    # throw away the warning about apt not being a stable interface
    REPO=$(apt list --installed 2> /dev/null| grep $OWNER)
  elif [[ $DISTRO == "suse" ]]; then
    OWNER=$($PKG -q --whatprovides $UNITFILE 2> /dev/null | cut -d: -f1)
    REPO=$(zypper --quiet -s 11 se -i -t package -s $OWNER | grep "^i" | awk '{print $6}')
  else
    # default to distros that use (t)DNF
    OWNER=$($PKG -q --whatprovides $UNITFILE | cut -d: -f1)
    REPO=$($DNF info  $OWNER 2>/dev/null | grep -iE "^(From repo|Repository)" | tr -d '[:blank:]'| cut -d: -f2)
  fi
  loggy "Agent owned by $OWNER and installed from $REPO"

  # Check service/unit status by using the return value from systemctl
  UNITSTAT=$(systemctl is-active $SERVICE)
  UNITSTATRC=$?
  loggy "Unit activity test: $UNITSTAT :: RC:$UNITSTATRC"
  
  # Check python and its origin
  PYPATH=$(systemctl show $SERVICE -q -p ExecStart | tr " " "\n" | grep python | cut -d "=" -f 2 | uniq)
  # check if we retrieved a python path, which may be false if the unit file only calls waagent instead of calling it as an arg to python
  #  This is most common on RH but may happen elsewhere
  if [[ -z $PYPATH ]]; then
    loggy "python unable to be located from unit definition, probably called from within waagent"
    WAPATH=$(systemctl show $SERVICE -q -p ExecStart | tr " " "\n" | grep waagent | cut -d "=" -f 2 | uniq)
    
    if [ -z ${WAPATH} ] ; then
      # this shouldn't be a valid codepath since examining waagent didn't lead a python path
      # but you CAN get here if the service is masked
      loggy "High probability of a masked agent"
      PYSTAT=$((PYSTAT+8))
    else
      # go search the waagent executable (which is a script) for the python package it will call
      # the first line of the waagent "binary" will be the path to whatever python it uses
      PYBIN=$(head -n1 $WAPATH | cut -d "!" -f 2 | tr " " "\n" | grep python)
      loggy "Python :: $PYBIN found in $WAPATH"
      PYPATH=$(which $PYBIN)
      PY=$(readlink -f $PYPATH)
      loggy "Python from reading waagent script :: $PYPATH derives to :: $PY"
    fi
  else
    # python was in the service definition for ExecStart, so use these variables
    loggy "Python called explicitly from the systemd unit :: $PYPATH"
    PY=$(readlink -f $PYPATH)
  fi
  # We should have validated the agent unit exists, so start 
  #  to do some checking for things dependent on the agent package being present

  # WAAgent config directives
  loggy "Checking agent configuration parameters by running 'waagent --show-configuration'"
  if [ -z ${EXE} ] ; then
    # no agent found, maybe change a variable for later, but EXE being 'null' should be good enough
    loggy "skipping config checks, no waagent found"
  else
    # -- there is probably a way to reuse this code and pass in the value we want to check, but not doing that right now
    loggy "Checking extension enablement"
    #  We're just reporting the config values
    EXTENS=$($EXE --show-configuration 2> /dev/null | grep -i 'Extensions.Enabled' | tr '[:upper:]' '[:lower:]'| tr -d '[:space:]' | cut -d = -f 2 )
    EXTENSMSG="enabled" # default
    if [ -z $EXTENS ]; then
      # this shouldn't happen unless waagent wasn't located correctly
      EXTENS="undef"
      EXTENSMSG="undef"
    else
      loggy "Extensions.Enabled config : $EXTENS"
      EXTENSMSG="$EXTENS (actual value)"
    fi
    loggy "Checking AutoUpdate"
    AUTOUP=$($EXE --show-configuration 2> /dev/null | grep -i 'AutoUpdate.Enabled' | tr '[:upper:]' '[:lower:]'| tr -d '[:space:]' | cut -d = -f 2 )
    AUTOUPMSG="enabled" # default
    if [ -z $AUTOUP ]; then
      # this shouldn't happen unless waagent wasn't located correctly
      AUTOUP="undef"
      AUTOUPMSG="undef"
    else
      loggy "AutoUpdate.Enabled config : $AUTOUP"
      AUTOUPMSG="$AUTOUP (actual value)"
    fi
  fi
else
  # this is the "no agent unit" block, so treat everything like a critical failure here
  # move more of the vars above into this 'bad variables' stanza to signal that things are failing
  loggy "Agent systemd unit was not found, strange results may follow"
  OWNER="systemd"
  REPO="undef"
  EXTENS="agent not found"
  EXTENSMSG="agent not found"
  AUTOUP="agent not found"
  AUTOUPMSG="agent not found"
  # set PY/PYBIN in here as a fallback, after the redundancy is cleared above
fi

# quick check and log the version of python
#  this could be done with --version, but then you get other fluff
loggy "Checking $PY version"
PYVERSION=$($PY -c 'import sys; print(str(sys.version_info.major)+"."+str(sys.version_info.minor)+"."+str(sys.version_info.micro))')
IFS='.' read PYMAJ PYMIN PYPATCH <<< "$PYVERSION"
loggy "Python=$PYVERSION"

if [ "$PYMAJ" = "2" ]; then
  # Nothing good will happen if we're calling python2 - distro may be old or python is wrongly pointed
  PYSTAT=$((PYSTAT+16))
  loggy "The referenced python is v2 - either EoL distribution or a misdirected python link"
fi

# now that we should definitively have a python path, find out who owns it.  If this is still empty, just fail, since waagent
# didn't eval out, maybe waagent doesn't even exist??
# PY could be the end-result of dereferencing PYPATH, but we need to know where the PYPATH came 
#   from because that's who waagent calls
loggy "Checking who provides $PYPATH"
if [[ $PYPATH ]]; then
  if [[ $DISTRO == "debian" ]]; then
    PYOWNER=$($PKG -S $PYPATH | cut -d: -f1)
    # throw away the warning about apt not being a stable interface
    PYREPO=$(apt list --installed 2> /dev/null| grep $PYOWNER)
  elif [[ $DISTRO == "suse" ]]; then
    PYOWNER=$($PKG -q --whatprovides $PYPATH | cut -d: -f1)
    PYREPO=$(zypper --quiet -s 11 se -i -t package -s $PYOWNER | grep "^i" | awk '{print $6}')
  elif [[ $DISTRO == "azurelinux" ]]; then
    PYOWNER=$($PKG -q --whatprovides $PYPATH | cut -d: -f1)
    PYREPO=$($DNF info  $PYOWNER 2>/dev/null | grep -i "Repository" | tr -d '[:blank:]'| cut -d: -f2)
  else
    # Maybe everything else is RHEL(like)
    PYOWNER=$($PKG -q --whatprovides $PYPATH | cut -d: -f1)
    PYREPO=$($DNF info  $PYOWNER 2>/dev/null | grep -i "From repo" | tr -d '[:blank:]'| cut -d: -f2)
  fi
else
  PYOWNER="python defintion undef or defaulted - is waagent here?"
  PYREPO="n/a"
fi
loggy "Python owning package : $PYOWNER"
loggy "Package from repository:$PYREPO"

## Python functional checks
# - modules
#   We have *a* python version, as defined in the scripts, so verify if a couple of modules can be imp'd
# 'requests'
if [ $(($PYSTAT & 8 )) -gt 0 ] ; then # this is for "waagent unit probably masked"
  loggy "Skipping all python module tests due to bad agent status"
  PYREQ="skipped"
  PYALA="skipped"
  PYARG="skipped"
else
  loggy "Checking to see if this python can load the modules we require"
  PYREQ=""
  if testPyMod $PYPATH "requests" ; then
    PYREQ="loaded"
  else
    loggy "Failing to load 'requests' module"
    PYREQ="failed"
    PYSTAT=$((PYSTAT+1)) # if we can't load 'requests' then a lot of things are going to break - also this may be an illegitimate python
  fi
  # 'azurelinuxagent.agent'
  PYALA=""
  if  testPyMod $PYPATH  "azurelinuxagent.agent" ; then
    PYALA="loaded"
  else
    loggy "Failing to load 'azurelinuxagent' module"
    PYALA="failed"
    PYSTAT=$((PYSTAT+2)) # if we can't load the agent module then either waagent will fail entirely, or this could be an illegitimate python
  fi
  # argparse - https://docs.python.org/3/library/argparse.html
  if  testPyMod $PYPATH  "argparse" ; then
    PYARG="loaded"
  else
    loggy "Failing to load 'argparse' module - this is not an issue for waagent, but will keep vmassist from working - and likely means python is not consistent"
    PYARG="failed"
    PYSTAT=$((PYSTAT+4)) # if we can't load argparse then we won't be able to spawn the subscript successfully - maybe python is <3.2
  fi
  loggy "finished checking python modules"
fi
# How many pythons (not snakes) are in the 'path'
#  We're just going to count it and log, anything other than 1 is cause for caution, but not necessarily enough to error out
loggy "Counting pythons in /usr/bin"
PYCOUNT=$(find /usr/bin -name python\* -type f | wc -l)
PYCOUNTSTAT=$PYCOUNT
# handle the case where there are no 'real' python bins in /usr/bin, but python3 is a link which eventually points to some sort of 'platform-python', which is OK
if [[ $PYCOUNT == 0 ]]; then
  loggy "Found no real python binaries in /usr/bin"
  DEREFPY=$(readlink -f /usr/bin/python3)
  if [[ $DEREFPY =~ "platform-python" ]]; then
    PYCOUNT=1
    PYCOUNTSTAT="python3 symlinked to platform-python"
    loggy "Alternative state for python3 - symlinked to $DEREFPY which is safe"
  else
    loggy "python status out of an expected state - manually investigate"
    PYCOUNTSTAT="Unexpected python state"
  fi
else
  loggy "Found $PYCOUNT python files in /usr/bin, informational only, see where python3 is pointing"
fi

## CONNECTIVITY CHECKS
# -- These are great candidates for moving 'into' python
### There is possibly a better way to do this using curl - see OneNote
# These tests only work 'as root' so lets check if root and not do any of this if not
if [[ $EUID == 0 ]]; then
  loggy "Checking IMDS access"
  # block to use 'system python' to query the IMDS - move this to the end of the script later.
  # we are using the system's python to test regardless
  IMDSHTTPRC=`/usr/bin/env $PY - <<EOF

import requests

imds_server_base_url = "http://169.254.169.254"
instance_api_version = "2021-02-01"
instance_endpoint = imds_server_base_url + \
    "/metadata/instance?api-version=" + instance_api_version
headers = {'Metadata': 'True'}

try:
  r = requests.get(instance_endpoint, headers=headers, timeout=5)
  print(r.status_code)
  r.raise_for_status()
except requests.exceptions.HTTPError as errh:
  print ("Error")
except requests.exceptions.RetryError as errr:
  print ("MaxRetries")
except requests.exceptions.Timeout as errt:
  print ("Timeout")
except requests.exceptions.ConnectionError as errc:
  print ("ConnectErr")
except requests.exceptions.RequestException as err:
  print ("UnexpectedErr")
EOF
`

  loggy "Checking wireserver access"
  WIREHTTPRC=`/usr/bin/env $PY - <<EOF

import requests

wire_server_base_url = "http://168.63.129.16"
wire_endpoint = wire_server_base_url + "/?comp=versions"
headers = {'Metadata': 'True'}

try:
  r = requests.get(wire_endpoint, headers=headers, timeout=5)
  print(r.status_code)
  r.raise_for_status()
except requests.exceptions.HTTPError as errh:
  print ("Error")
except requests.exceptions.RetryError as errr:
  print ("MaxRetries")
except requests.exceptions.Timeout as errt:
  print ("Timeout")
except requests.exceptions.ConnectionError as errc:
  print ("ConnectErr")
except requests.exceptions.RequestException as err:
  print ("UnexpectedErr")
EOF
`

  # test the "other" wire server port - 
  # this doesn't respond to casual http requests, so for now do a low level nc
  # Since socat is 'new', nc is 'old and deprecated', use them in that order, then fail if neither are here
  # nc -w 1 -z 168.63.129.16 32526
  if [ -f /bin/socat ] ; then
    if ( /bin/socat /dev/null TCP:168.63.129.16:32526,connect-timeout=2 2>/dev/null ) ; then
      loggy "Wireserver:23526 connectivity check: passed"
      WIREEXTPORT="open"
    else
      loggy "Wireserver:23526 connectivity check: failed"
      WIREEXTPORT="fail"
    fi
  elif [ -f /bin/nc ] ; then
    loggy "No socat binary, trying nc"
    if ( nc -w 1 -z 168.63.129.16 32526 ) ; then 
      loggy "Wireserver:23526 connectivity check: passed"
      WIREEXTPORT="open"
    else 
      loggy "Wireserver:23526 connectivity check: failed"
      WIREEXTPORT="fail"
    fi
  else 
    loggy "no socat or nc binary, skipping 32526 test"
    WIREEXTPORT="socat/nc not present - skipped"
  fi
else
  loggy "Skipping wireserver and IMDS checks due to not running as root"
  WIREHTTPRC="Not run as root"
  IMDSHTTPRC="Not run as root"
fi


# Network checks
# STUFF=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/?api-version=2023-07-01")
# echo $STUFF | tr { '\n' | tr , '\n' | tr } '\n' | grep "publicIpAdd" | awk  -F'"' '{print $4}'
# What IPs do we have
# what MAC is defined in Azure
# curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/?api-version=2023-07-01" | jq
# -- this will move into the python sub-script when implemented

# other general system checks
# look for any full filesystems, as a courtesy, and because sometimes agent blows up if /var is too full
FULLFS="none"

# Cryptic command to format the output of df, then parse it, and compare to the defined $FSFULLPCENT
# this will go into the subscript, and move this line into the 'bad python block so that we always get a disk check'
DFOUT=$(df -hl --type ext4 --type xfs --type vfat --type btrfs --type ext3 --output=target,pcent | tail -n+2 | while read path pcent ; do pcent=${pcent%\%}; if [ "$pcent" -ge $FSFULLPCENT ]; then   echo "$path:$pcent"; fi; done)
if [[ $DFOUT ]] ; then
  FULLFS=$DFOUT
fi

# make a log-friendly report, possibly for easy parsing
LOGSTRING="DISTRO=$DISTRO"
LOGSTRING="$LOGSTRING|SERVICE=$SERVICE"
LOGSTRING="$LOGSTRING|SRVSTAT=$UNITSTAT"
LOGSTRING="$LOGSTRING|SRVRC=$UNITSTATRC"
LOGSTRING="$LOGSTRING|UNIT=$UNITSTAT"
LOGSTRING="$LOGSTRING|UNITPKG=$OWNER"
LOGSTRING="$LOGSTRING|REPO=$REPO"
LOGSTRING="$LOGSTRING|PY=$PY"
LOGSTRING="$LOGSTRING|PYVERS=$PYVERSION"
LOGSTRING="$LOGSTRING|PYPKG=$PYOWNER"
LOGSTRING="$LOGSTRING|PYREPO=$PYREPO"
LOGSTRING="$LOGSTRING|PYCOUNT=$PYCOUNT"
LOGSTRING="$LOGSTRING|PYREQ=$PYREQ"
LOGSTRING="$LOGSTRING|PYALA=$PYALA"
LOGSTRING="$LOGSTRING|WIRE=$WIREHTTPRC"
LOGSTRING="$LOGSTRING|WIREEXTPORT=$WIREEXTPORT"
LOGSTRING="$LOGSTRING|IMDS=$IMDSHTTPRC"
LOGSTRING="$LOGSTRING|EXTN=$EXTENS"
LOGSTRING="$LOGSTRING|AUTOUP=$AUTOUP"
LOGSTRING="$LOGSTRING|FULLFS=$FULLFS"
loggy $LOGSTRING

## output our report to the 'console' if in debug, we 'asked' for it by arg, 
#  or if python is bad and we won't be running the python script
if [[ $DEBUG ]] || [[ $BASHREPORT ]] || [[ $PYSTAT -gt 0 ]] ; then
  echo -e "Distro Family:   $DISTRO"
  echo -e "Agent Service:   $SERVICE"
  echo -e "- status:        $(printColorCondition $UNITSTATRC $UNITSTAT)"
  echo -e "- Unit file:     $UNITFILE"
  echo -e "- Unit package:  $OWNER"
  echo -e "- Repo for Unit: $REPO"
  echo -e "python path:     $PY"
  echo -e "- version:       $PYVERSION"
  echo -e "- package:       $PYOWNER"
  echo -e "- repo:          $PYREPO"
  echo -e "- mod reqests:   "$(printColorCondition "$PYREQ" "$PYREQ" "loaded")
  echo -e "- mod waagent:   "$(printColorCondition "$PYALA" "$PYALA" "loaded")
  echo -e "pythons present: "$(printColorCondition $PYCOUNT "$PYCOUNTSTAT" 1)
  echo -e "IMDS HTTP CODE:  $(printColorCondition $IMDSHTTPRC $IMDSHTTPRC 200)"
  echo -e "WIRE HTTP CODE:  $(printColorCondition $WIREHTTPRC $WIREHTTPRC 200)"
  echo -e "WIRE EXTN PORT:  "$(printColorCondition "$WIREEXTPORT" "$WIREEXTPORT" "open")
  # these could either be 'yes|no' or 'true|false'... using the most common defaults for the 'good' string value
  echo -e "Extensions:      "$(printColorCondition $EXTENS "$EXTENSMSG" "true")
  echo -e "AutoUpgrade:     "$(printColorCondition $AUTOUP "$AUTOUPMSG" "true")
  # System checks
  echo -e "Volumes >$FSFULLPCENT%:   "$(printColorCondition "$FULLFS" "$FULLFS" "none")
  echo -e "Please see https://aka.ms/vmassistlinux for guidance on the information in the above output"
fi

### This is where we diverge into the python sub-script.  Many checks can be moved into Python code once we have validated that the python is workable
# if $PYSTAT > 0, environment is in a troubled state
if [ $PYSTAT -gt 0 ]; then
  # python is inconsistent, lets throw an error here and put out our basic summaries at this point.
  loggy "Python checks failed quick-exiting with python status $PYSTAT"
  # Output the logging now, since the python execution will be skipped
  if [ $(($PYSTAT & 8 )) -gt 0 ] ; then # this is for "waagent unit probably masked"
    echo "Appears the waagent service definition is not valid, possibly masked- exiting now"
  else
    echo "Something about the python being called by waagent ($PY) is broken: See if it exists, is part of the distro, or if there was a critical error with waagent.  PYSTAT=$PYSTAT"
  fi
  loggy "Skipping python script due to PYSTAT value:$PYSTAT"
else
  # We'll go call the python sub-script here, since we should be
  #  able to at least 'function' in portable py code
  loggy "Python seems sane, spawning vmassist.py"
  ARGS="$@ "
  # Call vmassist.py with args - 
  # --bash="$LOGSTRING"
  # -d $DEBUG
  # -l $LOGFILE
  # pseudocode:
  BASHARGS="DISTRO=$DISTRO"
  BASHARGS="$BASHARGS|SERVICE=$SERVICE"
#  BASHARGS="$BASHARGS|SRVSTAT=$UNITSTAT"
#  BASHARGS="$BASHARGS|SRVRC=$UNITSTATRC"
  BASHARGS="$BASHARGS|UNIT=$UNITSTAT"
#  BASHARGS="$BASHARGS|UNITPKG=$OWNER"
#  BASHARGS="$BASHARGS|REPO=$REPO"
  BASHARGS="$BASHARGS|PY=$PY"
#  BASHARGS="$BASHARGS|PYVERS=$PYVERSION"
#  BASHARGS="$BASHARGS|PYPKG=$PYOWNER"
#  BASHARGS="$BASHARGS|PYREPO=$PYREPO"
  BASHARGS="$BASHARGS|PYCOUNT=$PYCOUNT"
  BASHARGS="$BASHARGS|PYREQ=$PYREQ"
  BASHARGS="$BASHARGS|PYALA=$PYALA"
#  BASHARGS="$BASHARGS|WIRE=$WIREHTTPRC"
#  BASHARGS="$BASHARGS|WIREEXTPORT=$WIREEXTPORT"
#  BASHARGS="$BASHARGS|IMDS=$IMDSHTTPRC"
#  BASHARGS="$BASHARGS|EXTN=$EXTENS"
#  BASHARGS="$BASHARGS|AUTOUP=$AUTOUP"
#  BASHARGS="$BASHARGS|FULLFS=$FULLFS"
  ARGS="$ARGS --bash=\"$BASHARGS\" --log=$LOGFILE"
  if [[ $TERM ]] ; then
    true
    # do nothing... this should be handled better but !$TERM seems to always be false so we never get colors
  else
    ARGS="$ARGS --noterm"
  fi
  # make sure the python subscript exists, for good measure
  PYSCRIPT=$(dirname $0)"/vmassist.py"
  if test -f $PYSCRIPT; then
    loggy "running $PYSCRIPT with args $ARGS"
    if [[ $DEBUG ]]; then
      echo "running # $PYSCRIPT $ARGS"
    fi
    $PY $PYSCRIPT $ARGS
    loggy "$PYSCRIPT exited"
  else
    loggy "vmassist.py script not found at $PYSCRIPT!! Unable to spawn"
  fi
fi
# this will be 'after' the python script runs too
loggy "$0 finished at $(date --rfc-3339=seconds)"
