# Overview
This script validates the repo servers connectivity and provides recommendation for the fix based on the error message.

1. Executes yum clean all and yum check-update commands.
2. Captures the output and error from yum check-update.
3. If no errors observed, then prints that repo connectivity is successful.
4. If any errors are observed validates the error with the defined conditions and provides recommendation for the fix.

# Supported OS Images

This version of the script currently supports only Redhat VMs for now(rhe6, rhel7 and 8 non-byos VMs which are deployed from Azure market place image).
## Usage
Execute the below commands on Redhat VM for script execution.<br>
    **`#mkdir /tmp/rhui && cd /tmp/rhui`**<br>
    **`#wget https://github.com/Azure/azure-support-scripts/archive/refs/heads/master.zip && unzip master.zip 'azure-support-scripts-master/Linux_scripts/RHUI_repo_validation_scripts/*' && rm -f master.zip && cd azure-support-scripts-master/Linux_scripts/RHUI_repo_validation_scripts`**<br>
    **`#python repo_check.py`** or **`#python3 repo_check.py`** based on python version available on the VM.
