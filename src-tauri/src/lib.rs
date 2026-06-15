mod fs_commands;

pub fn run() {
    let args: Vec<String> = std::env::args().collect();
    let launch = fs_commands::launch_file_from_args(&args);

    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(fs_commands::WatcherState::default())
        .manage(fs_commands::LaunchFile(std::sync::Mutex::new(launch)))
        .invoke_handler(tauri::generate_handler![
            fs_commands::list_workspace,
            fs_commands::pick_workspace,
            fs_commands::read_file,
            fs_commands::write_file,
            fs_commands::create_dir,
            fs_commands::create_file,
            fs_commands::rename,
            fs_commands::delete,
            fs_commands::watch_workspace,
            fs_commands::export_save,
            fs_commands::take_launch_file,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
