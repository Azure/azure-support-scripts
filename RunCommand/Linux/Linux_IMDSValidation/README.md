
# Azure VM IMDS Attestation Certificate Chain Validator (Linux)

This bash script validates the Azure Instance Metadata Service (IMDS) attestation certificate chain on Linux VMs. It identifies exactly which certificate is missing, detects the OCSP intermediate your VM uses, checks the trust store, tests connectivity to certificate download endpoints, and provides distro-specific fix commands.

## How It Works

The script runs 7 phases:

1. **IMDS Reachability** — Confirms `169.254.169.254` is reachable from the guest OS
2. **Attestation Fetch** — Retrieves the attested document from IMDS and extracts the signing certificate from the PKCS#7 envelope
3. **Chain Validation** — Validates the certificate chain against the system trust store using `openssl verify`
4. **OCSP Detection** — Automatically detects which OCSP intermediate (02-16) your VM is using
5. **Store Inventory** — Checks the trust store for DigiCert Root G2, Microsoft TLS RSA Root G2, and the detected OCSP intermediate
6. **Connectivity** — Tests TCP connectivity to AIA, CRL, and OCSP endpoints
7. **Summary** — Provides distro-specific fix commands (Ubuntu/Debian, RHEL/CentOS/Mariner, SUSE)

## Certificate Chain

IMDS attestation uses a 4-level certificate chain:

```
DigiCert Global Root G2 (Root CA)
  └── Microsoft TLS RSA Root G2 (cross-signed intermediate, NOT a root)
        └── Microsoft TLS G2 RSA CA OCSP xx (OCSP responder intermediate)
              └── CN=metadata.azure.com (leaf — from IMDS attested endpoint)
```

> **Note:** Azure rotates OCSP intermediates (numbered 02 through 16). The script automatically detects which one your VM is using.

## Supported Distributions

| Distribution | Cert Path | Update Command | Tested |
|---|---|---|---|
| Ubuntu / Debian | `/usr/local/share/ca-certificates/` | `update-ca-certificates` | Ubuntu 22.04 ✅ |
| RHEL / CentOS / Oracle Linux / Azure Linux | `/etc/pki/ca-trust/source/anchors/` | `update-ca-trust` | RHEL 9.7 ✅ |
| SUSE / openSUSE | `/usr/share/pki/trust/anchors/` | `update-ca-certificates` | SUSE 15 SP6 ✅ |

## Prerequisites

- Root/sudo privileges
- `openssl` (installed by default on all Azure Linux images)
- `python3` (for PKCS#7 signature extraction)
- `curl` (for IMDS and connectivity checks)
- Must be executed within an Azure VM

## Usage

Run the script via Azure Run Command:

### Azure CLI

```bash
az vm run-command invoke \
    --resource-group <resource-group> \
    --name <vm-name> \
    --command-id RunShellScript \
    --scripts @Linux_IMDSValidation.sh
```

With auto-fix (downloads missing certs, installs, updates trust store, re-validates):

```bash
az vm run-command invoke \\
    --resource-group <resource-group> \\
    --name <vm-name> \\
    --command-id RunShellScript \\
    --scripts @Linux_IMDSValidation.sh \\
    --parameters "--autofix"
```

### Download and run locally

```bash
# Diagnostic only (default)
curl -sL https://raw.githubusercontent.com/Azure/azure-support-scripts/master/RunCommand/Linux/Linux_IMDSValidation/Linux_IMDSValidation.sh | sudo bash

# With auto-fix
curl -sL https://raw.githubusercontent.com/Azure/azure-support-scripts/master/RunCommand/Linux/Linux_IMDSValidation/Linux_IMDSValidation.sh | sudo bash -s -- --autofix
```

### Run from within the VM

```bash
chmod +x Linux_IMDSValidation.sh
sudo ./Linux_IMDSValidation.sh
```

## Important: DER to PEM Conversion

Certificate downloads from Microsoft are in **DER format**. Linux trust stores require **PEM format**. The script's fix commands include the conversion step (`openssl x509 -inform DER`). If you install certificates manually, always convert first:

```bash
openssl x509 -in certificate.der -inform DER -out certificate.crt
```

## References

- [Azure Instance Metadata Service (IMDS)](https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service)
- [IMDS Certificate Chain Issues (Linux)](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/linux-vm-imds-certissues)
- [IMDS Certificate Chain Issues (Windows)](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-vm-imds-certissues)
- [Azure Certificate Authority Details](https://learn.microsoft.com/azure/security/fundamentals/azure-ca-details?tabs=certificate-authority-chains)

## Liability

As described in the [MIT license](../../../LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback

We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues
