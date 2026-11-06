use std::process::ExitCode;

use crate::exit;

pub fn run() -> ExitCode {
    let cwd = match std::env::current_dir() {
        Ok(d) => d,
        Err(e) => {
            log::error!("cannot get current directory: {e}");
            return exit::FAILURE;
        }
    };
    match west_core::topdir::topdir(&cwd) {
        Ok(p) => {
            // v1 printed `PurePath(topdir).as_posix()`: forward slashes
            // on every platform. Scripts splice this into git commands
            // and manifest paths, both of which prefer `/`.
            let s = p.to_string_lossy();
            println!(
                "{}",
                if cfg!(windows) {
                    s.replace('\\', "/")
                } else {
                    s.into_owned()
                }
            );
            exit::SUCCESS
        }
        Err(e) => {
            log::error!("{e}");
            exit::FAILURE
        }
    }
}
