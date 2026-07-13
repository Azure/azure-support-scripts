
# Azure VM IMDS Attestation Certificate Chain Validator

This PowerShell script validates the Azure Instance Metadata Service (IMDS) attestation certificate chain on Azure VMs. It identifies exactly which certificate is missing or misconfigured, checks certificate stores, and tests connectivity to certificate download endpoints.

## How It Works

The script runs 6 phases:

1. **IMDS Reachability** — Confirms `169.254.169.254:80` is reachable from the guest OS
2. **Attestation Fetch** — Retrieves the attested document from IMDS and extracts the signing certificate
3. **Chain Validation** — Builds the X509 certificate chain and walks **each element** to identify the exact failure point (not just the leaf cert's issuer)
4. **Store Inventory** — Checks all IMDS-relevant certificates are in the correct stores, flags misplaced or disallowed certs
5. **Connectivity** — Tests TCP port 80 to AIA, CRL, and OCSP endpoints required for certificate validation
6. **Summary** — Provides actionable fix steps with specific download URLs for missing certificates

## Certificate Chain (as of Jan 2026)

IMDS attestation uses a 4-level certificate chain:

```
DigiCert Global Root G2 (DF3C24F9...)
  └── Microsoft TLS RSA Root G2 (B5EE89E7...) ← cross-signed intermediate, NOT a root
        └── Microsoft TLS G2 RSA CA OCSP 04 (DA6D0400...) ← OCSP responder intermediate
              └── CN=metadata.azure.com (leaf — from IMDS attested endpoint)
```

> **Note:** "Microsoft TLS RSA Root G2" is a cross-signed intermediate issued by DigiCert Global Root G2, despite its name suggesting it is a root CA. The `-xsign` suffix in its download URL confirms this.

## Features

- **Per-element chain walk** — Identifies exactly which certificate in the chain is causing the failure
- **Known cert lookup** — Maps each cert to its expected store, type, and download URL
- **Store inventory** — Checks correct store placement and warns about certs in wrong stores or the Disallowed store
- **AIA/CRL/OCSP connectivity** — Tests all endpoints needed for certificate download and validation
- **Actionable output** — Specific download URLs and fix steps, not just generic "go to this page"
- **AutoFix mode** — Optional `-AutoFix` switch downloads and installs missing certificates, re-validates, and clears the activation watermark

## Prerequisites

- PowerShell 5.1 or later
- Administrator privileges
- Must be executed within an Azure VM (accesses the instance metadata endpoint)

## Usage

Run the script in PowerShell **within an Azure VM**:

```powershell
Set-ExecutionPolicy Bypass -Force
.\Windows_IMDSValidation.ps1
```

With auto-fix (downloads missing certs, installs, re-validates, runs fclip.exe):

```powershell
.\Windows_IMDSValidation.ps1 -AutoFix
```

Or via Azure Run Command:
- Azure Portal → VM → Operations → Run Command → Select `Windows_IMDSValidation`

## Interpreting Results

| Phase 4 Output | Meaning | Action |
|---|---|---|
| `[OK]` | Certificate found in correct store | None needed |
| `[MISS]` | Certificate not found | Download and install from the URL shown, or use `-AutoFix` |
| `[WARN] Found in WRONG store` | Cert exists but in incorrect store | Move to the correct store |
| `[WARN] DISALLOWED store` | Cert is explicitly blocked | Remove from Disallowed store |

### Common Scenario: "Certificate not found" but cert was installed

If you installed a certificate but the script still reports a chain failure, the **next certificate up the chain** may be missing. For example, installing the OCSP intermediate (DA6D) without the cross-signed intermediate above it (B5EE) will still fail.

## Important: Auto-Download Behavior

Windows `X509Chain.Build()` will automatically attempt to download missing intermediate certificates via AIA (Authority Information Access) extensions. This means:
- A **PASS** result doesn't guarantee certificates are permanently installed — they may have been fetched at runtime
- If AIA endpoints are blocked, the chain build will fail even if the cert was previously auto-downloaded

## References

- [Azure Instance Metadata Service (IMDS)](https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service)
- [Azure Certificate Authority Details](https://learn.microsoft.com/azure/security/fundamentals/azure-ca-details?tabs=certificate-authority-chains)
- [IMDS Cert Issues Troubleshooting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-vm-imds-certissues)
- [IMDS Connection Issues Troubleshooting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-vm-imds-connection)
- [IMDS Verification Tool](https://aka.ms/AzVmIMDSValidation)

## Liability
As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues
