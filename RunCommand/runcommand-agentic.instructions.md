---
description: "Agentic authoring standard for Run Command scripts. Use when creating or updating any script under RunCommand/Windows or RunCommand/Linux. Enforces run-command-safe behavior, scenario-specific checks, mock profiles, and actionable output."
applyTo: "RunCommand/**"
---

# Run Command Agentic Instructions

## Mission

Create scripts that reduce first-contact diagnostic time. Avoid generic baseline checks unless they are a small part of a scenario-focused script.

## Required File Set

Every script folder must contain:

1. `<Script_Name>.ps1`
2. `mock_config_sample.json`
3. `README.md`

## Run Command Constraints (Mandatory)

1. PowerShell 5.1 compatible for Windows scripts.
2. No interactive prompts (`Read-Host`, confirmations, menus).
3. No dependency on Az module in guest context.
4. Output must fit Run Command return limits (compact table-first output).
5. Script must be read-only unless the script name explicitly indicates remediation.

## Output Contract (Mandatory)

Each script output must include:

1. Title line: `=== <Script Title> ===`
2. Fixed-width status table with `Check` + `Status` columns.
3. Section separators using `-- <Section> --`.
4. `-- More Info --` section with at least one row pointing to next-step guidance.
5. Final summary line: `=== RESULT: N OK / M FAIL / K WARN ===`

## Quality Gates (Promotion)

Use tiers for script maturity:

- Tier 0: Baseline placeholder only.
- Tier 1: Scenario-aware checks, weak thresholds.
- Tier 2: Action-driving checks with deterministic thresholds.
- Tier 3: Escalation-ready with strong symptom-to-remediation mapping.

Only Tier 2+ should be considered production recommended.

### Tier 2 minimum requirements

1. 5-8 scenario-specific probes.
2. At least 2 deterministic FAIL conditions.
3. At least 2 deterministic WARN conditions.
4. Explicit "likely cause" and "next action" in output or final rows.
5. README links mapped directly to each major FAIL/WARN class.

## Mocking Standard

`mock_config_sample.json` must include at least 3 test profiles:

1. `healthy`
2. `degraded`
3. `broken`

If a script uses a single mock profile initially, mark README as `Tier 0` or `Tier 1` and list missing profiles under "Maturity Gaps".

## README Standard (Mandatory)

README must include:

1. What It Does
2. How To Run
3. Mock/offline command with `-MockConfig .\mock_config_sample.json`
4. Mock Output Example
5. Learn References (`learn.microsoft.com` links)
6. Interpretation Guide (condition -> likely cause -> next step)
7. Maturity tier (`Tier 0-3`) and known gaps

## Agentic Authoring Workflow

When adding scripts with agentic tools:

1. Start with scenario intent (`symptom`, `bucket`, `decision intent`).
2. Implement probes with deterministic thresholds.
3. Add mock profiles that exercise all status classes.
4. Add More Info row(s) in script output.
5. Add README interpretation + Learn references.
6. Run a safety pass:
   - no PS7-only syntax for Windows scripts
   - no Az dependency for in-guest scripts
   - no interactive prompts
7. Mark script tier in README and list gaps if below Tier 2.

## Anti-Patterns (Do Not Ship)

1. "Baseline only" scripts with no scenario-specific probes.
2. Scripts that output only environment facts without decision guidance.
3. README with no mock output or no Learn references.
4. Thresholds that are implied but not encoded.
5. Scripts that require manual interpretation with no suggested next action.
