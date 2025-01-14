# Health check script for Azure Agent on Linux - waagent
VMassist is a combination of bash and python scripts intended to be used to diagnose issues with the Azure agent in a Linux VM, and some limited related issues with the general health of the VM.

Output is intended to be viewed in the serial console and provide pointers to solve some well-known issues, as well as certain deviations from best practice which can affect VM availability.

## Prerequisites
In order for this tool to be of value, the VM does need to be booting completely to a functional OS with a normal bash shell.  It is possible that this tool may function in single user mode or a chroot/rescue VM environment, but this scenario is untested.

There are two components of the script
- A "wrapper" script written with bash shell tools and methods. This script does minimal OS checking and primarily identifies if the python environment called by the Azure agent is usable.  This script will generally execute silently and call the python script if no serious conditions are found during the basic checks.  In the situation where serious concerns are found, the python script will not be called and this script will output pertinent findings for action.  The 'bash mode' report can be forced to always output, even when the python script is called, by executing with the `-r` argument.
- A python script which will perform some of the same checks as the bash script, but also will do more complex checks and reporting.

## Usage
The vmassist scripts must be run as root.  Either enter a root shell using a command such as `sudo -i` or prepend `sudo` to each command listed in this readme.  Downloads can be run as any user however the "bootstrap" script runs the script and as such requires root permissions.

### automatic download and run
- run\
   `bash <(curl -sL https://raw.githubusercontent.com/pagienge/walinuxagenthealth/main/bootstrap-vmassist.sh)`

### manual download
- download the two scripts individually to the current directory\
   `wget https://github.com/pagienge/VMassist/raw/main/vmassist.sh`\
   `wget https://github.com/pagienge/VMassist/raw/main/vmassist.py`

- add executable permissions\
`chmod vmassist.sh`
- Run the script\
`./vmassist.sh`

### Running VMassist
- Running `bootstrap-vmassist.sh` as above will download and run the diagnostic script from `/tmp/vmassist`
- After downloading by any method, run the `vmassist.sh` from the path reported in the output of `bootstrap-vmassist.sh` as root, or through sudo.  The script can be run as many times as necessary without downloading again

### syntax
Syntax: vmassist.sh [-h|v|b]
- options:
   -h     Print this Help.
   -v     Verbose output mode.  May be issued up to 3 times for more verbosity (not completely implemented)
   -r     Always output the bash summary before spawning the python script

### Analyzing output
The output from the script should be a serial console friendly report of well known issues, along with a link to current documentation on both interpreting the output and references for fixing identified issues.

Log output is created in `/var/log/azure`, using filenames staring with `vmassist`

### Issues running VMassist
#### Seems to hang forever
There are conditions where the scripts may not produce output at all and seem to hang without causing system load.  This may be due to the underlying package manager expecting interaction from a prompt, specifically on newer VMs.  If this is encountered, run a package manager command from the command line and watch for prompts.  Examples:
- dnf repolist
- zypper ref
- apt-get update

Once any prompts or issues with the package managers are cleared, re-run the script with `vmassist.sh`
