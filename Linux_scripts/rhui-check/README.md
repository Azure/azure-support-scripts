# RHUI Check Script

## Overview

This script validates server configuration and connectivity to the RHUI Servers provided by Azure to the PAYG RHEL images.
Instead of performing an end-to-end conectivity test, the rhui-check.py performs individual validations of the different components required to have a successful communication 
to the RHUI servers. Among other things, here are some of the individual tests the script performs.

- Validates the Client Certificate.
- RHUI rpm consistency.
- Consistency between EUS and non-EUS repository configuration and their requirements.
- Connectivity to the RHUI Repositories.
- SSL connectivity to the RHUI repositories.
- Focuses exclusively in the RHUI repositories.

## Supported Environments

The script was built to successfully run on plain vanilla RHEL7.9 and later PAYG images, but it will work on custom images with the Azure Hybrid Benefit enabled as well.

## Usage

### RHEL 7.x

```bash
curl -sL https://raw.githubusercontent.com/Azure/azure-support-scripts/refs/heads/master/Linux_scripts/rhui-check/rhui-check.py | sudo python2 -
```

Or download and transfer the script to the instance:
https://raw.githubusercontent.com/Azure/azure-support-scripts/refs/heads/master/Linux_scripts/rhui-check/rhui-check.py

Then run:

```
sudo python2 ./rhui-check.py 
```

### RHEL 8.x, RHEL 9.x and above

```
curl -sL https://raw.githubusercontent.com/Azure/azure-support-scripts/refs/heads/master/Linux_scripts/rhui-check/rhui-check.py | sudo python3 -
```

Or download and transfer the script to the instance:
https://raw.githubusercontent.com/Azure/azure-support-scripts/refs/heads/master/Linux_scripts/rhui-check/rhui-check.py

Then run:

```
sudo python3 ./rhui-check.py 
```

>[!NOTE]
>**Replace python3 with `/usr/libexec/platform-python` if the python3 command is not found.**
