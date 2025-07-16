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


import argparse
import os
import sys
import socket
import requests
import logging
import subprocess
import re
# for os-release (initially)
import csv
import pathlib
# network checking
import socket
import json
# For talking to the wire server and decoding responses
import http.client
from xml.etree import ElementTree

### COMMAND LINE ARGUMENT HANDLING
parser = argparse.ArgumentParser(
    description="stuff"
)
parser.add_argument('-b', '--bash', required=True, type=str)
parser.add_argument('-r', '--report', action='store_true') # this is just to 'catch' a bash-side parameter, we don't use it
parser.add_argument('-d', '--debug', action='store_true')
parser.add_argument('-v', '--verbose', action='count', default=0)
parser.add_argument('-l', '--log', type=str, required=False, default='/var/log/azure/'+os.path.basename(__file__)+'.log')
parser.add_argument('-t', '--noterm', action='store_true') # mainly used for coloring output
args=parser.parse_args()
# TODO: implement using verbosity level
if ( args.debug ):
  if ( args.verbose == 0 ):
    args.verbose = 1

# example bash value:
# bash="DISTRO=debian|SERVICE=walinuxagent.service|UNIT=active|PY=/usr/bin/python3.8|PYCOUNT=1|PYREQ=loaded|PYALA=loaded"
bashArgs = dict(inStr.split('=') for inStr in args.bash.split("|"))
# any value can be extracted with 
#   bashArgs.get('NAME', "DefaultString")
#  ex:
#   bashArgs.get('PY',"N/A")
### END COMMAND LINE ARGUMENT HANDLING
### UTILS
#### UTIL VARs and OBJs
vmaPyVersion="1.0.1"

logger = logging.getLogger(__name__)
logging.basicConfig(format='%(asctime)s py %(levelname)s %(message)s', filename=args.log, level=logging.DEBUG)
# start logging as soon as possible
logger.info("Python script version "+vmaPyVersion+" started:"+os.path.basename(__file__))
# add the 'to the console' flag to the logger
if ( args.verbose > 0 ):
  logging.getLogger().addHandler(logging.StreamHandler(sys.stdout))
  logger.info("Debug on")
#### END UTIL VARS
#### UTIL FUNCTIONS
def colorPrint(color, strIn):
  retVal=""
  if ( args.noterm ):
    retVal=strIn
  else:
    retVal=color+"{} \033[00m".format(strIn)
#        print(color+"{} \033[00m".format(strIn))
  return retVal
def cRed(strIn): return colorPrint("\033[91m", strIn)
def cGreen(strIn): return colorPrint("\033[92m", strIn)
def cYellow(strIn): return colorPrint("\033[93m", strIn)
def cBlue(strIn): return colorPrint("\033[94m", strIn)
def cBlack(strIn): return colorPrint("\033[98m", strIn)
def colorString(strIn, redVal="dead", greenVal="active", yellowVal="inactive"):
  # force these into strs
  strIn = str(strIn)
  redVal = str(redVal)
  greenVal = str(greenVal)
  yellowVal = str(yellowVal)
  # ordered so that errors come first, then warnings and eventually "I guess it's OK"
  if redVal.lower() in strIn.lower():
    return cRed(strIn)
  elif yellowVal.lower() in strIn.lower():
    return cYellow(strIn)
  elif greenVal.lower() in strIn.lower():
    return cGreen(strIn)
  else:
    return cBlack(strIn)

#### END UTIL FUNCS
### END UTILS
### MAIN CODE
#### Global vars setup
fullPercent=90
wireIP="168.63.129.16"
imdsIP="169.254.169.254"
# debug percentage
if ( args.verbose > 0 ):
  fullPercent=20
# parse out os-release and put the values into a dict

path = pathlib.Path("/etc/os-release")
with open(path) as stream:
  reader = csv.reader(filter(lambda line: line.strip(), stream), delimiter="=")
  os_release = dict(reader)
osrID=os_release.get("ID_LIKE", os_release.get("ID"))
osMajS,osMinS=os_release.get("VERSION_ID").split(".")
osMaj=int(osMajS)
osMin=int(osMinS)

# TODO: Add a family / major version check for 'supported' and "doesn't work" checks
# TODO: perhaps add a best-effort flag, wrap things that might not work in 'best effort' mode
# -- weird versions - OEL, Alma, Rocky

# holding dicts for all the different things we will valiate
bins={}
services={}
checks={}
findings={}
# took out the part to put some default findings in, delete them if we find something bad

#### END Global vars
#### Main logic functions
def validateBin(binPathIn):
  # usage: pass in a binary to check, the following will be determined
  #  - absolute path (dereference links)
  #  - provided by what package
  #  - what repo provides the package
  #  - version for the package or binary if possible
  # output object:
  # load up os-release into a dict for later reference
  logger.info("Validating " + binPathIn)
  # we need to store the passed value in case of exception with the dereferenced path
  binPath=binPathIn
  realBin=os.path.realpath(binPath)
  if ( binPath != realBin ):
    logger.info(f"Link found: {binPath} points to {realBin}, verify outputs if this returns empty data")
    binPath=realBin
  thisBin={"exe":binPathIn}
 
  if (osrID == "debian"):
    noPkg=False # extra exception flag, using pure try/excepts is difficult to follow
    try:
      # Find what package owns the binary
      thisBin["pkg"]=subprocess.check_output("dpkg -S " + binPath, shell=True, stderr=subprocess.DEVNULL).decode().strip().split(":")[0]
    except:
      logger.info(f"issue validating {binPath}, reverting to original path: {binPathIn}")
      try:
        thisBin["pkg"]=subprocess.check_output("dpkg -S " + binPathIn, shell=True, stderr=subprocess.DEVNULL).decode().strip().split(":")[0]
      except subprocess.CalledProcessError as e:
        logger.info(f"All attempts to validate {binPathIn} have failed. Likely a rogue file: {e.output}")
        noPkg=True
    if not noPkg:
      # find what repository the package came from
      try:
        aptOut=subprocess.check_output("apt-cache show --no-all-versions " + thisBin["pkg"] , shell=True, stderr=subprocess.DEVNULL).decode().strip()
        thisBin["repo"]=re.search("Origin.*",aptOut).group()
      except subprocess.CalledProcessError as e:
        # we didn't get a match, probably a manual install (dkpg) or installed from source
        logger.info(f"package {thisBin['pkg']} does not appear to have come from a repository")
        thisBin["repo"]="no repo"
    else: 
      # binary not found or may be source installed (no pkg)
      thisBin["pkg"]=f"no file or owning pkg for {binPathIn}"
      thisBin["repo"]="n/a"
  # catch more options for ID in os-release since RHEL10 adds some variabilty
  elif ( "fedora" in osrID or "centos" in osrID ):
    try:
      rpm=subprocess.check_output("rpm -q --whatprovides " + binPath, shell=True, stderr=subprocess.DEVNULL).decode().strip()
      thisBin["pkg"]=rpm
      try:
        # expand on this to make the call to 'dnf'
        #dnfOut=subprocess.check_output("dnf info " + rpm, shell=True, stderr=subprocess.DEVNULL).decode().strip()
        result=subprocess.run(["dnf","info",rpm], stdout=subprocess.PIPE, stderr=subprocess.PIPE,check=True)
      except subprocess.CalledProcessError as e:
        # we didn't get a match, probably a manual install (rpm), built from source, or a general DNF failure
        thisBin["repo"]=f"repo search failed: {e.stderr.decode()}"
      else:
        dnfOut=result.stdout.decode().strip()
        # Repo line should look like "From repo   : [reponame]" so clean it up
        m = re.search(r"(From repo.*|Repository.*)",dnfOut).group().strip().split(":")[1].strip()
        if ( not m ):
          m = f"No repo found for {binPath}"
        thisBin["repo"]=m
    except subprocess.CalledProcessError as e:
      thisBin["pkg"]=f"no file or owning pkg: {e.output}"
      thisBin["repo"]="n/a"
  elif ( osrID == "suse"):
    try:
      rpm=subprocess.check_output('rpm -q --queryformat %{NAME} --whatprovides ' + binPath, shell=True, stderr=subprocess.DEVNULL).decode()
      thisBin["pkg"]=rpm
      try:
        # options:
        zyppOut=subprocess.check_output("zypper --quiet --no-refresh info " + rpm, shell=True, stderr=subprocess.DEVNULL).decode().strip()
        thisBin["repo"]=re.search("Repository.*",zyppOut).group().split(":")[1].strip()
      except:
        # we didn't get a match, probably a manual install (rpm) or from source
        thisBin["repo"]="not from a repo"
    except subprocess.CalledProcessError as e:
      thisBin["pkg"]="no file or owning pkg: " + e
      thisBin["repo"]="n/a"
  elif ( osrID == "mariner" or osrID == "azurelinux"):
    try:
      rpm=subprocess.check_output('rpm -q --queryformat %{NAME} --whatprovides ' + binPath, shell=True).decode()
      thisBin["pkg"]=rpm
      try:
        # options:
        zyppOut=subprocess.check_output("tdnf --installed info " + rpm, shell=True).decode().strip()
        thisBin["repo"]=re.search("Repo.*",zyppOut).group().split(":")[1].strip()
      except:
        # we didn't get a match, probably a manual install (rpm) or from source
        thisBin["repo"]="not from a repo"
    except subprocess.CalledProcessError as e:
      thisBin["pkg"]="no file or owning pkg: " + e
      thisBin["repo"]="n/a"
  else:
    print("Unable to determine OS family from os-release")
    thisBin["pkg"]="packaging system unknown"
    thisBin["repo"]="n/a"
  logString = binPath + " owned by package '" + thisBin["pkg"] + "' from repo '" + thisBin["repo"] + "'"
  logger.info(logString)
  bins[binPathIn]=thisBin
def checkService(unitName, package=False):
  # take in a unit file and check status, enabled, etc.
  # output object:

  logger.info("Service/Unit check " + unitName)

  thisSvc={"svc":unitName}
  unitStat=0          # default service status return, we'll set this based on the 'systemctl status' RC
  thisSvc["status"]="undef" # this will get changed somewhere
  # First off, let us check if the unit even exists
  try:
    throwawayVal=subprocess.check_output(f"systemctl status {unitName}", shell=True)
    #0 program is running or service is OK <<= default value of unitStat
    #1 program is dead and /var/run pid file exists
    #2 program is dead and /var/lock lock file exists
    #3 program is not running
    #4 program or service status is unknown
    #5-99  reserved for future LSB use
    #100-149   reserved for distribution use
    #150-199   reserved for application use
    #200-254   reserved
  except subprocess.CalledProcessError as sysctlErr:
    # we will be referencing this return code later, assuming it's not 4 - see table above
    unitStat=sysctlErr.returncode
    if ( unitStat == 4 ):
      thisSvc["status"]="nonExistantService"
    else:
      logger.info(f"Service {unitName} status returned unexpected value: {sysctlErr.output} with text: {sysctlErr.output}")
  # Unit was determined to exist (not rc=4), so lets validate the service status and maybe some other files
  if ( unitStat < 4 ):
    # Process the configured, active and substate for the service.  Active/Sub could be inactive(dead) in an interactive console
    #  This can be done from systemctl show [service] --property=[UnitFileState|ActiveState|SubState]
    config=subprocess.check_output(f"systemctl show {unitName} --property=UnitFileState",shell=True).decode().strip().split("=")[1]
    active=subprocess.check_output(f"systemctl show {unitName} --property=ActiveState",shell=True).decode().strip().split("=")[1]
    sub=subprocess.check_output(f"systemctl show {unitName} --property=SubState",shell=True).decode().strip().split("=")[1]
    thisSvc["config"]=config
    # make the 'status' look like the output of `systemctl status`
    thisSvc["status"]=f"{active}({sub})"

    # more integrety checks based on digging into the files
    thisSvc["path"]=subprocess.check_output(f"systemctl show {unitName} -p FragmentPath", shell=True).decode().strip().split("=")[1]
    # Which python does the service call?
    # # dive into the file in 'path' and logic out what python is being called for validations
    # who owns it... maybe?
    if ( package ):
      # We need to process the owner and path of the unit if (package) was set by the caller
      logger.info(f"Checking owners for unit: {unitName} using validateBins")
      # No need to re-code all this, just call validateBin(binName)
      validateBin(thisSvc["path"])
      thisSvc["pkg"]=bins[thisSvc["path"]]['pkg']
      thisSvc["repo"]=bins[thisSvc["path"]]['repo']
      # get rid of this extra entry in bins caused by calling validateBins()
      del bins[thisSvc["path"]]
    else:
      logger.info(f"package details for {unitName} not requested, skipping")
      pass
  else:
    #set some defaults when the unit wasn't here
    pass

  unitFile=subprocess.check_output(f"systemctl show {unitName} -p FragmentPath", shell=True).decode().strip().split("=")[1]
  logString = unitName + " unit file found at " + thisSvc["path"] + "owned by package '" + thisSvc["pkg"] + "from repo: " + thisSvc["repo"]
  logger.info(logString)
  services[unitName]=thisSvc
  
def checkHTTPURL(urlIn):
  checkURL = urlIn
  headers = {'Metadata': 'True'}
  returnString=""
  try:
    r = requests.get(checkURL, headers=headers, timeout=5)
    returnString=r.status_code
    r.raise_for_status()
  except requests.exceptions.HTTPError as errh:
    returnString=f"Error:{r.status_code}"
  except requests.exceptions.RetryError as errr:
    returnString=f"MaxRetries"
  except requests.exceptions.Timeout as errt:
    returnString=f"Timeout"
  except requests.exceptions.ConnectionError as errc:
    returnString=f"ConnectErr"
  except requests.exceptions.RequestException as err:
    returnString=f"UnexpectedErr"
  return returnString
def isOpen(ip, port):
  # return true/false if the remote port is/isn't listening, only takes an IP, no DNS is done
  # using connect_ex would give us the error code for analysis, but we're just going for true/false here
  s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
  s.settimeout(2)
  try:
    is_open = s.connect((ip, int(port))) == 0 # True if open, False if not
    if is_open:
      s.shutdown(socket.SHUT_RDWR)
    return True
  except Exception:
    is_open = False
  s.close()
  return is_open

def getInterfaces():
  # Get all interfaces present in the system except for loopback, return as a dict
  # -- May have an issue with multiple VIPs on a NIC
  ipOut = subprocess.run(['ip', '-j', 'address', 'show'], stdout=subprocess.PIPE)
  intJSON = json.loads(ipOut.stdout.decode('utf-8'))
  
  addresses = {}
  for iface in intJSON:
    iface_name = iface.get('ifname')
    if iface_name != "lo":
      addresses[iface_name] = {}
      addresses[iface_name]['mac'] = iface.get('address')
      for addr_info in iface.get('addr_info', []):
        if addr_info.get('family') == 'inet':  # Only IPv4 addresses
          addresses[iface_name]['ip'] = addr_info.get('local')
  return addresses
# TODO:: repackage this search function as a generic re: search, and call it with the defined re for MAC addresses
def searchDirForMAC(dirToSearch, returnDict, okMAC):
  # return all MACs found defined in some config file in the passed in directory
  #   We'll add each file, and the MAC(s) found in there, to the passed in dict
  # accept an 'ok' MAC definition, because it would be ok for cloud-init managed
  #   configs to have a mac defined - CI will reset the configs if the mac changes
  # Define a MAC address regex pattern (e.g., 00:1A:2B:3C:4D:5E or 00-1A-2B-3C-4D-5E)
  mac_pattern = re.compile(r'([0-9a-f]{2}(?::[0-9a-f]{2}){5})', re.IGNORECASE)
  # Walk through all files in the directory
  for root, _, files in os.walk(dirToSearch):
    # loop through all files in the dirToSearch
    for file_name in files:
      file_path = os.path.join(root, file_name)
      # Check if it's a regular file (skip links, sockets, pipes, etc.)
      if os.path.isfile(file_path):
        try:
          with open(file_path, 'r') as file:
            content = file.read()
            # Find all MAC addresses in the file
            mac_addresses = mac_pattern.findall(content)
            # If MAC addresses are found, and not the passed in okMAC, add them to the dictionary
            # mac_addresses as returned from findall will be an array of string(s)
            if ( mac_addresses and (okMAC not in mac_addresses) ):
              returnDict[file_path] = mac_addresses
        except (UnicodeDecodeError, PermissionError):
          # Skip files that can't be read due to encoding or permission issues
          # just create the exception code block, but we won't be using it
          pass
              
def searchDirForString(dirToSearch, returnDict, string):
  for root, _, files in os.walk(dirToSearch):
    # loop through all files in the dirToSearch
    for file_name in files:
      file_path = os.path.join(root, file_name)
      # Check if it's a regular file (skip links, sockets, pipes, etc.)
      if os.path.isfile(file_path):
        try:
          # Create a holding space for any/all matched text
          defLines=""
          # Open this file and search for the string
          with open(file_path, 'r') as file:
            for line_number, line in enumerate(file, start=1):
              # store the line number and line in the return string
              if string in line:
                # after the first occurrance add a newline every time we find a line
                if (defLines):
                  defLines = f"{defLines}\n"
                defLines = f"{defLines}{line_number}: {line.strip()}"
          # if we found anything create the file entry in the dict with all lines
          if ( defLines ):
            returnDict[file_path] = defLines
        except (UnicodeDecodeError, PermissionError):
          # Skip files that can't be read due to encoding or permission issues
          # just create the exception code block, but we won't be using it
          pass

#### END main logic funcs

#### START main processing flow

# ToDo list from bash logstring: (delete when completed)
# LOGSTRING="$LOGSTRING|SERVICE=$SERVICE"
# LOGSTRING="$LOGSTRING|PY=$PY"
# LOGSTRING="$LOGSTRING|PYVERS=$PYVERSION"
# LOGSTRING="$LOGSTRING|PYCOUNT=$PYCOUNT"
# LOGSTRING="$LOGSTRING|PYREQ=$PYREQ"
# LOGSTRING="$LOGSTRING|PYALA=$PYALA"

logger.info("args were "+str(parser.parse_args()))
# log anything we've determined above 
logger.info(f"OS family determined as {osrID}")
logger.info(f"OS Major Version={osMaj}")
logger.info(f"OS Minor Version={osMin}")
osOld = False
osFamOK = True
if ( osrID == "fedora" ):
  if ( osMaj < 8 ):
    osOld = True
elif ( osrID == "suse" ):
  if ( osMaj < 15 ):
    osOld = True
elif ( osrID == "debian" ):
  if ( osMaj < 20 ):
    osOld = True
elif ( osrID == "azurelinux" ):
  if ( osMaj < 3 ):
    osOld = True
else:
  osFamOK = False

if ( osOld ):
    logger.warning(f"OS family detected as {osrID} with major version of {osMaj} - this OS is too old too be reliably tested")
    findings['osSup']={'description': 'OS is Old', 'status': f"OS Family:{osrID} with Major Release:{osMaj} is too old to be reliably tested"}
if ( not osFamOK):
    logger.warning(f"Unsupported OS family detected:{osrID}")
    findings['osSup']={'description': 'OS family is minimally or completely untested', 'status': f"OS Family:{osrID}"}


# We'll use the 'bash' arguments from the bash wrapper to seed this script
waaServiceIn=bashArgs.get('SERVICE', "waagent.service") # this may differ per-distro, but offer a default
pythonIn=bashArgs.get('PY', "/usr/bin/python3")
waaBin=subprocess.check_output("which waagent", shell=True, stderr=subprocess.DEVNULL).decode().strip()
logger.info(f"using waagent location {waaBin}")


# look through the os.environ object for any mention of a variable with 'proxy' in the name
osEnv=dict(os.environ)
proxyVars = {key: osEnv[key] for key in osEnv if "proxy" in key.lower()}
# create a check and if needed a finding
if proxyVars:
  logger.info(f"proxy definition found in env: {proxyVars}")
  findings['proxy']={'description': 'ProxyCheck', 'status': f"Found proxy environment vars:\n{proxyVars}"}
  checks['proxy']={"check":"proxy", "value":proxyVars}
else:
  logger.info(f"No proxies found in env")
  checks['proxy']={"check":"proxy", "value":"None Found"}

# Check services and binaries
checkService(waaServiceIn, package=True)
# Check SSHD, Debian based distros started naming it ssh and launching on connect, sometime before Ubuntu 24.04
# TODO: make this version dependent - ubuntu 24.04+ uses JIT activation of sshd
if ( osrID == "debian" ):
  checkService("ssh.service", package=True)
else:
  checkService("sshd.service", package=True)

validateBin(pythonIn)
# PoC for right now to show what we can do, also because changing SSL can cause problems for extensions talking outside wire/IMDS
validateBin("/usr/bin/openssl")
validateBin(waaBin) # just to create another easy-to-check test
# Lets pull the version out of the 'normal' --version output string, for manual comparisons
waaVerOut=subprocess.check_output(f"{waaBin} --version", shell=True, stderr=subprocess.DEVNULL).decode().strip().lower().split('\n')
# if the output changes format we'll have to recode this block
# expected output:
#['walinuxagent-2.7.0.6 running on redhat 8.10',
# 'python: 3.6.8',
# 'goal state agent: 2.7.0.6']
waaVer = "0.0.0.0"
waaGoalVer = "0.0.0.0"
for line in waaVerOut:
  # process the version out of string #1 or #3 above - with an optional 4th v.v.v.v section since some versions only have 3
  verSearch = re.search(r'\d+\.\d+\.\d+(\.\d+)?', line)
  if ( verSearch ):
    if "walinuxagent" in line:
      waaVer = verSearch.group(0)
    elif "goal" in line:
      waaGoalVer = verSearch.group(0)
# log the check
checks["waaVersion"]={
    'description': 'Agent component versions',
    'check': 'waaVersion',
    'value': f"WAA:{waaVer}, Goal:{waaGoalVer}",
    'type': 'config'
    }
logger.info(f"Found agent:{waaVer} and extension handler: {waaGoalVer}")
# if the versions match, it's a 'finding' - these will only match if autoUpg is false or the package is VERY new so likely from source
if waaVer == waaGoalVer:
  logger.info(f"PA and Goal match version {waaVer} - this is probably bad!")
  findings['waaVers']={'description': 'Agent/Goal versions', 'status': f"Agent version and goal state match = {waaVer} - this is unlikely"}

## turn service/bins checks into 'checks' and 'findings'
### Binaries
#### string for the console report
binReportString=""
for binName in bins:
  checks[bins[binName]['exe']] = {'check': bins[binName]['exe'],
                                  'description': f"Binary check of {bins[binName]['exe']}",
                                  'value': f"Package:{bins[binName]['pkg']}, source:{bins[binName]['repo']}"
                                  }
  # check for alarms in the binaries and create findings as needed
  # - is the path include questionable areas - local, home, opt - these aren't "normal"
  if ( re.search("local", bins[binName]['exe']) or 
       re.search("opt", bins[binName]['exe']) or
       re.search("home", bins[binName]['exe'])):
    # this is bad, create a findings from this check
    findings[f"bp:{bins[binName]['exe']}"]={
      'description': f"binpath:{bins[binName]['exe']}",
      'status': "Path includes questionable directories",
      'type': "bin"
    }
    logger.warning(f"Checking path: {bins[binName]['exe']} found in a non-standard location")
    binReportString+=f"{cYellow(bins[binName]['exe'])} => check location\n"
  # - is the repository uncommon
  repoBad=False
  if osrID == "debian":
    # check if the repository is expected, this should usually say "Origin: Ubuntu"
    # We are blissfully ignoring *actual* Debian - which itself would be a cause for concern
    if ( not re.search(r"Origin: Ubuntu", bins[binName]['repo'])):
      repoBad=True
  elif ( osrID == "fedora" or osrID == "azurelinux" ) : 
    # Check if the 'repo' field includes the error indicator 'fail', or check if the repository name 
    #   is either @System or anaconda (initial install for RHEL or AL), or includes 'rhui' or 'azurelinux',
    #   or appstream - which is ok-ish
    if ( re.search("fail", bins[binName]['repo']) 
         or not (re.search(r"@System", bins[binName]['repo']) or
                 re.search("anaconda", bins[binName]['repo']) or
                 re.search("rhui", bins[binName]['repo']) or
                 re.search("AppStream", bins[binName]['repo']) or
                 re.search("azurelinux", bins[binName]['repo'])
             )):
      repoBad=True
  elif osrID == "suse":
    # check if the repository includes 'SLE-Module' or 'SUSE'
    if ( not re.search(r"SLE-Module", bins[binName]['repo'])):
      repoBad=True
  # all distro-specific checks finished, report if needed
  if ( repoBad ):
    findings[f"bs:{bins[binName]['exe']}"]={
      'description': f"binsource:{bins[binName]['exe']}",
      'status': f"Binary came from unusual source: {bins[binName]['repo']}",
      'type': "bin"
    }
    logger.warning(f"Checking {bins[binName]['exe']} found to be sourced from the repo {bins[binName]['repo']}")
    binReportString+=f"{bins[binName]['exe']} => {cRed(bins[binName]['repo'])} - verify repository\n"
if (len(binReportString) == 0 ):
  binReportString=cGreen("-- No issues with checked binaries")
  logger.info("No concerns found with binary checks")
### Services/Units
svcReportString=""
for svcName in services:
  if ( not re.search("running", services[svcName]['status']) ):
    findings[f"ss:{services[svcName]['svc']}"]={
      'description': f"service:{services[svcName]['svc']}",
      'status': f"Service not in 'running' state: {services[svcName]['status']}",
      'type': "svc"
    }
    logger.warning(f"Checking {services[svcName]['svc']} found in state {services[svcName]['status']}")
    svcReportString+=f"{services[svcName]['svc']} => {cRed(services[svcName]['status'])} - check logs\n"
  if ( not re.search("enabled", services[svcName]['config']) ):
    findings[f"sc:{services[svcName]['svc']}"]={
      'description': f"service:{services[svcName]['svc']}",
      'status': f"Service not enabled: {services[svcName]['config']}",
      'type': "svc"
    }
    logger.warning(f"Checking {services[svcName]['svc']} not enabled: {services[svcName]['config']}")
    svcReportString+=f"{services[svcName]['svc']} => {cRed(services[svcName]['config'])} - check config\n"
if (len(svcReportString) == 0 ):
  svcReportString=cGreen("-- No issues with checked services")
  logger.info("No concerns found with service checks")

## Early version report code
  # print(f"Analysis of unit : {services[svcName]['svc']}:")
  # print(f"  Owning pkg     : {services[svcName]['pkg']}" )
  # print(f"  Repo for pkg   : {services[svcName]['repo']}" )
  # print( "  run state      : "+colorString(services[svcName]['status'], redVal="dead", greenVal="active"))
  # print( "  config state   : "+colorString(services[svcName]['config'], redVal="disabled", greenVal="enabled"))

# Connectivity checks
## Wire server
wireCheck=checkHTTPURL(f"http://{wireIP}/?comp=versions")
thisCheck={"check":"wire 80", "value":wireCheck}
checks['wire']=thisCheck
if wireCheck != 200:
  findings['wire80']={
    'description': 'WireServer:80',
    'status': wireCheck,
    'type': "conn"
  }
  logger.warning(f"Wire server port 80 check returned {wireCheck} - check connectivity")
else:
  logger.info(f"Wire server port 80 check returned OK({wireCheck})")
# temp variable clean up, this shouldn't remove the item  in the 'checks' dict, just the temp object
del(thisCheck)
## Wire server "extension" port
wireExt=isOpen(wireIP,32526)
thisCheck={"check":"wire 23526", "value":wireExt}
checks['wireExt']=thisCheck
if not wireExt :
  findings['wire23526']={
    'description': 'WireServer:32526',
    'status': wireExt,
    'type': "conn"
  }
  logger.warning(f"Wire server extension port (32526) test returned {wireExt} - check connectivity")
else:
  logger.info(f"Wire server extension port (32526) returned OK({wireExt})")
# temp variable clean up, this shouldn't remove the item  in the 'checks' dict, just the temp object
del(thisCheck)

## IMDS
imdsCheck=checkHTTPURL(f"http://{imdsIP}/metadata/instance?api-version=2021-02-01")
thisCheck={"check":"imds 443", "value":imdsCheck}
checks['imds']=thisCheck
if imdsCheck != 200:
  findings['imds']={
    'description': 'IMDS',
    'status': imdsCheck,
    'type': "conn"
  }
  logger.warning(f"IMDS port 80 check returned {imdsCheck} - check connectivity")
else:
  logger.info(f"IMDS port 80 check returned OK({imdsCheck})")
# temp variable clean up, this shouldn't remove the item  in the 'checks' dict, just the temp object
del(thisCheck)

# Secondary test for ext. handler version/auto upgrade
# if the wire port state is 200(OK), query the wireserver for the latest goalstate (ext. handler) and check against the current goal state 
if wireCheck == 200:
  try:
    # We only use these modules in here - so far
    import xml.etree.ElementTree as ET
    from urllib.parse import urlparse
    # get the best API version *from the wire server
    endpoint="/?comp=versions"
    conn = http.client.HTTPConnection(wireIP)
    headers = {
      "Accept": "application/xml",  # Requesting XML response
      "User-Agent": "VM assist"  # Optional, helps identify the client
    }
    conn.request("GET", endpoint, headers=headers)
    response = conn.getresponse()
    xmlResp=response.read()
    apiVers=ET.fromstring(xmlResp).find("./Preferred/Version").text
    
    # Find the URLs for the different bits of the goal state
    endpoint="/machine/?comp=goalstate"
    headers = {
      "x-ms-version": apiVers,
      "Accept": "application/xml",  # Requesting XML response
      "User-Agent": "PythonTestHarness"  # Optional, helps identify the client
    }
    conn.request("GET", endpoint, headers=headers)
    response = conn.getresponse()
    xmlResp=response.read().decode()
    extConfURL=ET.fromstring(xmlResp).find("./Container/RoleInstanceList/RoleInstance/Configuration/ExtensionsConfig").text
    
    parsedURL=urlparse(extConfURL)
    endpoint = parsedURL.path + "?" + parsedURL.query
    conn.request("GET", endpoint, headers=headers)
    response = conn.getresponse()
    xmlResp=response.read().decode()
    wireGSVersion=ET.fromstring(xmlResp).find("./GuestAgentExtension/GAFamilies/GAFamily/Version").text
    
    if wireGSVersion != waaGoalVer:
      findings['waaUpgStat']={'status': f"not up to date - Local:{waaGoalVer} Wire:{wireGSVersion}", 'description':"GoalState version mismatch to wireserver"}
  except:
    findings['waaUpgStat']={'status': "failed during testing", 'description':f"GoalState version on VM ({waaGoalVer}) does not match wire server({wireGSVersion})"}
  finally:
    checks['waaUpgStat']={"check":"GoalVersion", "description":"Checking Goal State version against wire server", "value":wireGSVersion}
else:
  # flag that we skipped wireserver capability checks due to failing connectivity checks
  findings['waaUpgStat']={'status': "skipped", 'description':"Did not check GoalState version on wire server"}
  
  
# OS/config checks
## Agent config
waaConfigOut=subprocess.check_output(f"{waaBin} --show-configuration", shell=True, stderr=subprocess.DEVNULL).decode().strip().split('\n')
waaConfig={}
# put all output from the config command into a KVP
for line in waaConfigOut:
  key, value = line.split('=', 1)
  waaConfig[key.strip()] = value.strip()
checks['waaExt']={"check":"WAA Extension", "value":waaConfig['Extensions.Enabled']}
if ( checks['waaExt']['value'] != 'True' ):
  findings['waaExt']={'status': checks['waaExt']['value'], 'description':"Extensions are disabled in WAA config"}
  logger.warning(f"Extensions potentially disabled: {checks['waaExt']['value']}")
else:
  logger.info(f"Extensions enabled in waagent config {checks['waaExt']['value']}")
checks['waaUpg']={"check":"WAA AutoUpgrade", "value":waaConfig['AutoUpdate.Enabled']}
if ( checks['waaUpg']['value'] != 'True' ):
  findings['waaUpg']={'status': checks['waaUpg']['value'], 'description':"Agent extension handler auto-upgrade is disabled in WAA config"}
  logger.warning(f"Agent(ext handler) auto-update possibly disabled: {checks['waaUpg']['value']}")
else:
  logger.info(f"Agent(ext handler) auto-update enabled in waagent config {checks['waaUpg']['value']}")

# Checks against disks and objects
## results of disk space checks
### seed checks with a 'no problems' message, we'll reset it when we find one
checks['fullFS']={"check":"fullFS", "description": f"filesystem util over {fullPercent}%", "none":f"No filesystems over {fullPercent}% util"}
diskFind=""
## find the device 'id' for checking if the extension directory is 'noexec'
vlwaDev=os.stat("/var/lib/waagent").st_dev

mounts=[]

# only check these filesystem types ext4,xfs,vfat,btrfs,ext3
findmnt=subprocess.check_output("findmnt --evaluate -nb -o TARGET,SOURCE,FSTYPE,OPTIONS,USE% --pairs -t=ext2,ext3,ext4,btrfs,xfs,vfat", shell=True, stderr=subprocess.DEVNULL).decode().strip().split("\n")

for fm in findmnt:
  pairs = fm.split()
  dictTemp={}
  for pair in pairs:
    key, value = pair.split('=',1)
    dictTemp[key] = value.strip('"%')
  mounts.append(dictTemp)

# this was initially done in psutils:
#  mounts = psutil.disk_partitions()
#  but was found that certain distros do not include psutils in their marketplace images, so re-wrote with generic python code
for m in mounts:
  logger.info(f"Checking {m['SOURCE']} mounted at {m['TARGET']}")
  # the following hack brought to you by SLES, where USE% is instead USE_PCT
  pcent=0
  if ( 'USE%' in m ):
    pcent = m['USE%']
  elif ( 'USE_PCT' in m ):
    pcent = m['USE_PCT']

  if int(pcent) >= fullPercent:
    logger.warning(f"Filesystem utilization for {m['TARGET']} is over {fullPercent}: {pcent}")
    # delete the 'default empty set' wording in 'checks' for fullFS, because we found a disk over the util threshold
    if 'none' in checks["fullFS"]:
      checks['fullFS']={'check': 'fullFS', 'description':f'Look for filesystems utilized more than {fullPercent}','value':'see findings for details'}
      findings['fullFS']={}
    # Add each full filesystem to the list
    if 'status' in findings['fullFS']:
      findings['fullFS']['status'] = f"{findings['fullFS']['status']}, {m['TARGET']}:{pcent}"
    else:
      findings['fullFS']={'description': f"Filesystems over{fullPercent}",
                           'status': f"{m['TARGET']}:{pcent}",
                           'type':'os'
      }
  # check if this mount (m) is the one holding /var/lib/waagent, if so we will  want to check to see if the mount options include 'noexec'
  if ( os.stat(m['TARGET']).st_dev == vlwaDev ):
    logger.info(f"Found /var/lib/waagent based in filesystem {m['TARGET']} on device {m['SOURCE']}, checking mount options")
    # create the 'checks' data describing this
    checks['noexec']={
      'description': f"Checking mount options for noexec on {m['SOURCE']}",
      'check': 'noexec',
      'value': m['TARGET']
    }
    # add the 'findings' data if it's bad
    if (re.search("noexec", m['OPTIONS'])):
      # Found noexec so flag it
      logger.error(f"mountpoint {m['TARGET']} mounted with 'noexec'")
      findings['noexec']={
        'description':"Found /var/lib/waagent with noexec bit set",
        'status':True
      }

## Networking
# Get a list of all the interfaces and addresses
ints=(getInterfaces())
# Since there's no reliable way to check whether eth0 is static or dhcp, look through the
#   normal networking directories for the eth0 IP address. 
#   If we've found any files holding the IP currently on eth0, that's a problem

### Checks for defined MAC addresses or IPs - pertinent if someone hard coded configs
# set dummy addresses for the search
eth0MAC="de:ad:be:ef:4a:11"
eth0IP="128.0.128.255"
# If eth0 was found, store the MAC for checking for defined MAC addresses in files
if ( 'eth0' in ints ):
  eth0MAC = ints['eth0']['mac']
  eth0IP = ints['eth0']['ip']
  logger.info(f"Found {eth0MAC} on eth0, using this for config checks")
else:
  # if there is no eth0 defined, we're probably going to have some large issues with checks and possibly in 
  #   the system state, so be sure to log it.  Also create a 'finding'
  logger.error(f"Could not find a definition for eth0 - is networking sound?")
  findings['noETH0']={
    'description':"Could not locate an active eth0",
    'status': f"eth0 - MAC:{eth0MAC}|IP{eth0IP}",
    'type': 'os'
  }
filesWithIP={}
# we could check all of /etc, but that can be a lot and catch unrelated service configs, so look in the 
#   usual network dirs
searchDirForString("/etc/sysconfig", filesWithIP, eth0IP)
searchDirForString("/etc/netplan", filesWithIP, eth0IP)
if ( filesWithIP ):
  checks['IPs']={"check":"Static IP addresses", "value":"IP found in files- see findings"}
  fileString=""
  for foundFile in filesWithIP: 
    # if the "second time through" add a ", " seperator
    if (fileString):
      fileString=f"{fileString}, "
    fileString=f"{fileString}{foundFile}"
  # create the 'findings' entry
  findings['staticIP']={'description': 'eth0 IP found in files', 'status': fileString}
  logger.warning(f"Found eth0 IP:{eth0IP} defined in a config file, could be static - check findings report")
else:
  checks['IPs']={"check":"Static IP addresses", "value":"No IP addresses found in configs"}
  logger.info(f"Did not find IP configured on eth0 listed in any config files")

filesWithMACs={}
# We can't search for /etc because certain SSL configs have "MAC looking strings", so check these two 
#   directories, which should cover all common distros
searchDirForMAC("/etc/sysconfig", filesWithMACs,eth0MAC)
searchDirForMAC("/etc/netplan", filesWithMACs,eth0MAC)
if ( filesWithMACs ):
  checks['MACs']={"check":"MAC addresses", "value":"MACs found - see findings"}
  fileString=""
  for foundFile in filesWithMACs: 
    # if the "second time through" add a ", " seperator
    if (fileString):
      fileString=f"{fileString}, "
    fileString=f"{fileString}{foundFile}=>{filesWithMACs[foundFile][0]}"
  # create the 'findings' entry
  findings['badMAC']={'description': 'MACs found', 'status': fileString}
  logger.warning(f"Found eth0 MAC:{eth0MAC} defined in a config file - check findings report")
else:
  checks['MACs']={"check":"MAC addresses", "value":"No MAC addresses found in configs"}
  logger.info(f"Did not find MAC on eth0 listed in any config files")

# END ALL CHECKS

# START OUTPUT
print("------ vmassist.py results ------")
print(f"Please see {cBlue('https://aka.ms/vmassistlinux')} for guidance on the information in the above output")
print(f"OS family        : {osrID}")
# things we will always report on:
## WAA service
### => services[waaServiceIn]
#rint(f"OS family        : {osrID}")
print(f"Agent service    : {services[waaServiceIn]['svc']}")
print(f"=> status        : {colorString(services[waaServiceIn]['status'])}")
print(f"=> config state  : {colorString(services[waaServiceIn]['config'], redVal='disabled', greenVal='enabled')}")
print(f"=> source pkg    : {services[waaServiceIn]['pkg']}")
print(f"=> repository    : {services[waaServiceIn]['repo']}")
print(f"Agent version from running {waaBin} --version")
print(f"=> Main version  : {waaVer}")
print(f"=> Goal state    : {colorString(waaGoalVer,redVal=waaVer,greenVal=wireGSVersion)}")

#checkService(waaServiceIn, package=True)
# => {'walinuxagent.service': {'svc': 'walinuxagent.service', 'status': 'active(running)', 'config': 'enabled', 'path': '/usr/lib/systemd/system/walinuxagent.service', 'pkg': 'walinuxagent', 'repo': 'Origin: Ubuntu'}}
print(f"Wire Server")
print(f"  port 80        : {colorString(checks['wire']['value'], redVal='404', yellowVal='timeout', greenVal='200')}")
print(f"  port 32526     : {colorString(checks['wireExt']['value'], redVal='false', greenVal='true')}")
print(f"IMDS             : {colorString(checks['imds']['value'], redVal='404', yellowVal='timeout', greenVal='200')}")

# Always print out something about disk, use the default 'no problems' object, otherwise show what we found
if 'none' in checks["fullFS"]:
  print(f"Disk util > {fullPercent}%  : {checks['fullFS']['none']}")
else:
  print(f"Disk util > {fullPercent}%  : {findings['fullFS']['status']}")

# TODO: clean up and verify color on all core checks - wire server, waagent status
# TODO: optionally output all 'checks' objects
# Output the pre-determined binary findings
print("- Binary check results:")
print(binReportString)
print("- Service check results:")
print(svcReportString)
# TODO: parse findings list
print("- Findings from all checks:")
if ( findings ):
  print(cYellow("-- All Findings (may duplicate Service and Binary checks) ---"))
  for find in findings:
    print(f"--- {findings[find]['description']} : {findings[find]['status']}")
  print(cYellow("-- END Findings ---"))
else:
  print(cGreen("-- No notable findings!"))

# TODO: add the core checks not covered in findings, bins, and services, to the logs
### Log the raw data - don't send to the console
logger.info("--- verbose output of data structures ---")
logger.info("----- Binary check data structure:")
logger.info(str(bins))
logger.info("----- Service checks data structure:")
logger.info(str(services))
logger.info("----- All \"checks\" data structure:")
logger.info(str(checks))
logger.info("----- All \"findings\" data structure:")
logger.info(str(findings))
logger.info("--- END data structures ---")

# # DEBUG
# # semi-debug, looks good for now until we get the checks and findings presentation built up
if ( args.verbose > 0 ):
  print("--- Verbose binary check output")
  for binName in bins:
    print(f"Analysis of      : {bins[binName]['exe']}:")
    print(f"  Owning pkg     : {bins[binName]['pkg']}" )
    print(f"  Repo for pkg   : {bins[binName]['repo']}" )
  print("--- Verbose service check output")
  for svcName in services:
    print(f"Analysis of unit : {services[svcName]['svc']}:")
    print(f"  Owning pkg     : {services[svcName]['pkg']}" )
    print(f"  Repo for pkg   : {services[svcName]['repo']}" )
    print( "  run state      : "+colorString(services[svcName]['status'], redVal="dead", greenVal="active"))
    print( "  config state   : "+colorString(services[svcName]['config'], redVal="disabled", greenVal="enabled"))
  print("--- END Verbose output")
# END DEBUG

print("------ END vmassist.py output ------")
logger.info("Python ended")
#if ( args.debug ):
# print("------------ DATA STRUCTURE DUMP ------------")
# # For development testing, These are the last pprint calls
# from pprint import pprint
# print("bins")
# pprint(bins)
# print("services")
# pprint(services)
# print("findings")
# pprint(findings)
# print("checks")
# pprint(checks)
# print("args")
# pprint(args)
# print("---------- END DATA STRUCTURE DUMP ----------")
