#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use librustdesk::*;

#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
fn main() {
    if !common::global_init() {
        eprintln!("Global initialization failed.");
        return;
    }
    common::test_rendezvous_server();
    common::test_nat_type();
    common::global_clean();
}

#[cfg(not(any(
    target_os = "android",
    target_os = "ios",
    feature = "cli",
    feature = "flutter"
)))]
fn main() {
    #[cfg(all(windows, not(feature = "inline")))]
    unsafe {
        winapi::um::shellscalingapi::SetProcessDpiAwareness(2);
    }
    if let Some(args) = crate::core_main::core_main().as_mut() {
        ui::start(args);
    }
    common::global_clean();
}

#[cfg(feature = "cli")]
#[tokio::main(flavor = "current_thread")]
async fn main() {
    if !common::global_init() {
        return;
    }

    use clap::{Arg, Command};
    use hbb_common::{config::LocalConfig, log, env_logger::*};

    // initialize logger
    init_from_env(Env::default().filter_or(DEFAULT_FILTER_ENV, "info"));

    let matches = Command::new("rustdesk")
        .version(crate::VERSION)
        .author("Purslane Ltd <info@rustdesk.com>")
        .about("RustDesk command line tool")
        .arg(
            Arg::new("port-forward")
                .short('p')
                .long("port-forward")
                .num_args(1)
                .help("Format: remote-id:local-port:remote-port[:remote-host]"),
        )
        .arg(
            Arg::new("connect")
                .short('c')
                .long("connect")
                .num_args(1)
                .help("Test only, specify REMOTE_ID"),
        )
        .arg(
            Arg::new("key")
                .short('k')
                .long("key")
                .num_args(1)
                .help("Specify KEY"),
        )
        .arg(
            Arg::new("server")
                .short('s')
                .long("server")
                .num_args(0)
                .help("Start server"),
        )
        .get_matches();

    // Common setup
    common::test_rendezvous_server();
    common::test_nat_type();

    if let Some(p) = matches.get_one::<String>("port-forward") {
        let options: Vec<&str> = p.split(':').collect();
        if options.len() < 3 {
            log::error!("Wrong port-forward options");
            return;
        }

        let local_port = match options[1].parse::<i32>() {
            Ok(v) => v,
            Err(_) => {
                log::error!("Wrong local-port");
                return;
            }
        };

        let remote_port = match options[2].parse::<i32>() {
            Ok(v) => v,
            Err(_) => {
                log::error!("Wrong remote-port");
                return;
            }
        };

        let remote_host = if options.len() > 3 {
            options[3].to_owned()
        } else {
            "localhost".to_owned()
        };

        let key = matches.get_one::<String>("key").map(|s| s.to_owned()).unwrap_or_default();
        let token = LocalConfig::get_option("access_token");

        crate::cli::start_one_port_forward(
            options[0].to_owned(),
            local_port,
            remote_host,
            remote_port,
            key,
            token,
        );
      
    } else if let Some(connect_id) = matches.get_one::<String>("connect") {
        let key = matches.get_one::<String>("key").map(|s| s.to_owned()).unwrap_or_default();
        let token = LocalConfig::get_option("access_token");
        crate::cli::connect_test(connect_id, key, token);
    } else if matches.contains_id("server") {
        log::info!("id={}", hbb_common::config::Config::get_id());
        crate::start_server(true, false);
    }

    common::global_clean();
}
