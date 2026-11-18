//! Composable generators for SAP HANA `indexserver_*.trc` trace fixtures.
//!
//! Instead of pasting multi-kilobyte real traces into the repo, each detector's
//! input is built from small, parameterized line builders. The asserted tokens
//! (savepoint version `609685`, contended object `SAPHANADB:ADR2`, OOM host
//! `vmltmdbuspd01`, merge `rc = 2465`, …) live in exactly one place, and the
//! `#[cfg(test)]` round-trip tests below feed the output through the real
//! `supportfile` parsers so a format drift fails `cargo test` immediately —
//! the failure mode that previously slipped through to CI.

/// Standard HANA trace-line header:
/// `[<thread>]{<conn>}[<txn>] <ts> <sev> <component> <src>(<ln>) : <msg>`
fn header(ts: &str, sev: char, component: &str, src: &str, msg: &str) -> String {
    format!("[1527771]{{-1}}[-1/-1] {ts} {sev} {component} {src} : {msg}")
}

// ---------------------------------------------------------------------------
// Savepoints fixture (hana_test-savepoints.zip)
// ---------------------------------------------------------------------------

fn periodic_savepoint(ts: &str, version: u64) -> String {
    let msg = format!(
        "Savepoint current savepoint version: {version}, restart redo log position: 0x33cb84d9ca6, \
         next savepoint version: {}, last snapshot SP version: 609683",
        version + 1
    );
    header(ts, 'i', "Savepoint", "SavepointImpl.cpp(03481)", &msg)
}

fn replication_snapshot(ts: &str, version: u64) -> String {
    let msg = format!(
        "Snapshot current savepoint version: {version}, restart redo log position: 0x33cb9c4b4fb, \
         next savepoint version: {}, last snapshot SP version: {version}, kind: Replication",
        version + 1
    );
    header(ts, 'i', "Savepoint", "SavepointImpl.cpp(03481)", &msg)
}

fn slow_callback(ts: &str, took_ms: u64) -> String {
    let msg =
        format!("Callback PersistenceSessionSavepointCallback::spBeginRestart() took {took_ms}ms.");
    header(ts, 'w', "Savepoint", "SavepointImpl.cpp(05733)", &msg)
}

/// Build the savepoints trace: periodic savepoints (starting at version
/// `609685`), a couple of replication snapshots, and one real slow-callback
/// warning (`took 12384ms` → "stalled for 12.4s").
pub fn savepoints_trace() -> String {
    let mut lines: Vec<String> = Vec::new();

    let periodic = [
        ("2026-06-03 19:54:09.350130", 609685u64),
        ("2026-06-03 19:59:12.402952", 609686),
        ("2026-06-03 20:09:07.268164", 609689),
        ("2026-06-03 20:14:11.000354", 609690),
    ];
    for (ts, v) in periodic {
        lines.push(periodic_savepoint(ts, v));
    }

    let snapshots = [
        ("2026-06-03 20:04:04.157061", 609687u64),
        ("2026-06-03 20:19:06.936939", 609691),
    ];
    for (ts, v) in snapshots {
        lines.push(replication_snapshot(ts, v));
    }

    lines.push(slow_callback("2026-06-04 21:44:46.620914", 12384));

    let mut out = lines.join("\n");
    out.push('\n');
    out
}

// ---------------------------------------------------------------------------
// Trace-events fixture (hana_test-trace-events.zip): deadlocks / OOM / merge
// ---------------------------------------------------------------------------

/// A `Lock`/`WaitGraph.cc` deadlock record: a header line followed by the
/// indented `Deadlock detected` cycle with a victim and one more participant.
fn deadlock_block(ts: &str, object: &str) -> String {
    let head = format!("[1528819]{{303164}}[1551/16004765485] {ts} e Lock WaitGraph.cc(00250) : ");
    let victim = format!(
        "    [(victim) CONNID=303164, SESSIONID=303164, CLIENT_HOST=VMLTMAPUSPD07, \
         CLIENT_IP=10.105.10.76, CLIENT_PID=1467392, APPUSER = ZWLATMTMS, DBUSER=SAPHANADB, \
         ID=1551, TYPE=USER, STATE=ACTIVE, LOCK_TYPE=RECORD_LOCK, OBJECT_ID=29593135, \
         OBJECT_NAME={object}, STMT_HASH=259829e7fca4f2c336f63a2447378053, \
         STMT=UPDATE \"ADR2\" SET \"COUNTRY\" = ? WHERE \"CLIENT\" = ?]"
    );
    let other = format!(
        "    [CONNID=302171, SESSIONID=302171, CLIENT_HOST=VMLTMAPUSPD03, CLIENT_IP=10.105.10.53, \
         CLIENT_PID=1405775, APPUSER = ZWLATMTMS, DBUSER=SAPHANADB, ID=586, TYPE=USER, \
         STATE=ACTIVE, LOCK_TYPE=RECORD_LOCK, OBJECT_ID=29593135, OBJECT_NAME={object}, \
         STMT_HASH=259829e7fca4f2c336f63a2447378053, \
         STMT=UPDATE \"ADR2\" SET \"COUNTRY\" = ? WHERE \"CLIENT\" = ?]"
    );
    format!("{head}\n  Deadlock detected\n   - Deadlock cycle\n{victim}\n{other}\n")
}

/// An `OUT OF MEMORY occurred` block from the `Memory` component, including the
/// IPMM short-info line that carries the global allocation limit.
fn oom_block(ts: &str, host: &str) -> String {
    let head = header(
        ts,
        'e',
        "Memory",
        "mmReportMemoryProblems.cpp(02088)",
        "OUT OF MEMORY occurred.",
    );
    format!(
        "{head}\n\
         MemoryType: NearDRAM\n\
         Host: {host}\n\
         Executable: hdbindexserver\n\
         PID: 1312305\n\
         Failed to allocate 64mb (67108864b).\n\
         Allocation failure type: GLOBAL_ALLOCATION_LIMIT\n\
         IPMM NearDRAM short info:\n\
         GLOBAL_ALLOCATION_LIMIT (GAL) = 3.62tb (3983937077248b), SHARED_MEMORY = 50.62gb (54358601728b)\n"
    )
}

fn merge_error(ts: &str, table: &str, table_id: u64) -> String {
    let msg = format!(
        "Error in local merge: not enough merge tokens for delta merge or optimize compression : \
         table = {table} (t {table_id}), merge motivation = AutoMerge, rc = 2465"
    );
    format!("[2564393]{{-1}}[-1/9223372036854775806] {ts} e delta_merge CsTableMerge.cpp(02527) : {msg}")
}

/// Build the trace-events trace: several deadlock cycles on `SAPHANADB:ADR2`,
/// one OOM block on `vmltmdbuspd01`, and a batch of `rc = 2465` merge failures.
pub fn trace_events_trace() -> String {
    let mut out = String::new();

    for ts in [
        "2026-06-01 13:41:24.116632",
        "2026-06-01 13:50:38.351886",
        "2026-06-01 13:50:41.862160",
    ] {
        out.push_str(&deadlock_block(ts, "SAPHANADB:ADR2"));
    }

    out.push_str(&oom_block("2026-06-04 17:32:51.297072", "vmltmdbuspd01"));

    for (table, id) in [
        ("T31::SAPHANADB:/1DH/ML000000006", 551461u64),
        ("T31::SAPHANADB:/1DH/ML00000000A", 562676),
        ("T31::SAPHANADB:BGRFC_I_RUNNABLE", 16785),
    ] {
        out.push_str(&merge_error("2026-06-04 22:20:41.349323", table, id));
        out.push('\n');
    }

    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use supportfile::{
        parse_hana_deadlocks, parse_hana_merge_errors, parse_hana_oom, parse_hana_savepoints,
    };

    const TRC: &str = "T31 HANA Logs/indexserver_test.trc";

    #[test]
    fn savepoints_fixture_round_trips_through_the_parser() {
        let r = parse_hana_savepoints(&savepoints_trace(), TRC);
        assert!(r.found, "savepoints detected");
        assert!(r.count >= 2, "periodic savepoints: {}", r.count);
        assert!(r.snapshot_count >= 1, "snapshot savepoints: {}", r.snapshot_count);
        assert!(
            r.savepoints.iter().any(|s| s.savepoint_version == Some(609685)),
            "savepoint version 609685 present"
        );
        assert!(
            r.warnings.iter().any(|w| {
                w.r#type == "hana_savepoint_slow_callback" && w.message.contains("12.4s")
            }),
            "slow-callback warning rendered as 12.4s"
        );
    }

    #[test]
    fn trace_events_fixture_round_trips_through_the_parser() {
        let trc = trace_events_trace();

        let d = parse_hana_deadlocks(&trc, TRC);
        assert!(d.found && d.count >= 1, "deadlocks detected: {}", d.count);
        assert!(
            d.top_objects.iter().any(|c| c.name == "SAPHANADB:ADR2"),
            "contended object SAPHANADB:ADR2"
        );

        let o = parse_hana_oom(&trc, TRC);
        assert!(o.found && o.count >= 1, "oom detected: {}", o.count);
        assert_eq!(o.events[0].host.as_deref(), Some("vmltmdbuspd01"));
        assert_eq!(o.events[0].failure_type.as_deref(), Some("GLOBAL_ALLOCATION_LIMIT"));

        let m = parse_hana_merge_errors(&trc, TRC);
        assert!(m.found, "merge errors detected");
        assert!(
            m.token_exhaustion_count >= 1,
            "merge-token exhaustion (rc=2465): {}",
            m.token_exhaustion_count
        );
    }
}
