: <<'COMMENT'
Azure/azure-support-scripts

Copyright (c) Microsoft Corporation
All rights reserved. 

MIT License
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the ""Software""), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED *AS IS*, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
COMMENT

#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/azure-provisioning.log"
ENDPOINT="http://168.63.129.16/provisioning/health"
IMDS_URL="http://169.254.169.254/metadata/instance/compute/name?api-version=2019-06-01&format=text"

MAX_ATTEMPTS=5
SLEEP_SECONDS=5

# Redirect all stdout and stderr to log
mkdir -p "$(dirname "$LOGFILE")"
exec >> "$LOGFILE" 2>&1

echo "===== Azure provisioning health script started: $(date -Is) ====="

# ---------------------------
# Set hostname from IMDS
# ---------------------------
echo "Fetching VM name from IMDS..."
vm_name="$(curl -sS --noproxy '*' -H "Metadata:true" --connect-timeout 1 --max-time 2 "$IMDS_URL" || true)"

if [ -z "${vm_name:-}" ]; then
  echo "WARNING: IMDS returned empty VM name. Hostname not changed."
else
  echo "Setting hostname to '$vm_name'..."
  if command -v hostnamectl >/dev/null 2>&1; then
    hostnamectl set-hostname "$vm_name" && echo "Hostname successfully set to '$vm_name'" || echo "ERROR: Failed to set hostname to '$vm_name'"
  else
    echo "$vm_name" > /etc/hostname && hostname "$vm_name" || echo "ERROR: Failed to set hostname to '$vm_name'"
  fi
fi

# ---------------------------
# Post provisioning health (JSON)
# /provisioning/health expects:
#   - header: x-ms-guest-agent-name
#   - JSON payload
# Success commonly returns HTTP 201 per example. [1](https://github.com/Azure/azure-init/issues/186)
# ---------------------------
attempt=1
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
  echo "Posting provisioning health state=Ready (attempt $attempt/$MAX_ATTEMPTS)"

  # Use -v only if you want verbose logs; keeping it off by default is cleaner.
  # Add it back if needed.
  if curl -sS --noproxy '*' \
      -X POST \
      -H "x-ms-guest-agent-name: NoPA/1.0" \
      -H "Content-Type: application/json" \
      --data '{ "state": "Ready" }' \
      "$ENDPOINT" ; then
    echo "Provisioning health successfully reported to Azure"
    echo "===== Script completed successfully: $(date -Is) ====="
    exit 0
  fi

  rc=$?
  echo "Provisioning health POST failed (rc=$rc), retrying in ${SLEEP_SECONDS}s..."
  sleep "$SLEEP_SECONDS"
  attempt=$((attempt + 1))
done

echo "ERROR: Failed to report provisioning health after ${MAX_ATTEMPTS} attempts"
echo "===== Script failed: $(date -Is) ====="
exit 1
``
