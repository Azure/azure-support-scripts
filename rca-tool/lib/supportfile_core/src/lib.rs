pub mod parsers;

/// Cache a compiled `Regex` at the call site so it's only built once per
/// process. Returns `&'static Regex`. Each call-site location gets its own
/// `OnceLock`. Use this in place of `Regex::new(LITERAL).unwrap()` in any
/// hot parser path -- benchmark showed >300 per-call recompiles costing
/// 8-15s per archive on large sosreports.
#[macro_export]
macro_rules! cached_regex {
    ($pat:expr) => {{
        static RE: ::std::sync::OnceLock<::regex::Regex> = ::std::sync::OnceLock::new();
        RE.get_or_init(|| ::regex::Regex::new($pat).expect("invalid regex literal"))
    }};
}

pub use parsers::automation::*;
pub use parsers::azure::*;
pub use parsers::cluster::*;
pub use parsers::debugfs::*;
pub use parsers::events::*;
pub use parsers::network_interfaces::*;
pub use parsers::networking::*;
pub use parsers::packages::*;
pub use parsers::services::*;
pub use parsers::storage::*;
pub use parsers::unix::*;
pub use parsers::vmcore::*;
