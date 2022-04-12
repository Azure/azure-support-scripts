
<<<<<<< HEAD

Overview
This script validates the repo servers connectivity and provides recommendation for the fix based on the error message.

Executes yum clean all and yum check-update commands.
Captures the output and error from yum check-update.
If no errors observed, then prints that repo connectivity is successful.
If any errors are observed validates the error with the defined conditions and provides recommendation for the fix.
Supported OS Images
This version of the script currently supports only Redhat VMs for now(both rhel7 and 8).

Usage
cd /tmp on the Redhat VM

Download the zip file using wget https://github.com/dibaskar/repo_validation_scripts/archive/refs/heads/main.zip on VM or paste the URL directly in browser which downloads the zip file to your local machine and then zip file can be manually copied to VM for execution.

python repo_check.py or python3 repo_check.py based on python version available on the VM.
