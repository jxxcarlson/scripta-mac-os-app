mod fs_commands;

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(fs_commands::WatcherState::default())
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
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
