mod ai;
mod fs_commands;
mod terminal;

pub fn run() {
    let args: Vec<String> = std::env::args().collect();
    let launch = fs_commands::launch_file_from_args(&args);

    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, argv, _cwd| {
            use tauri::Emitter;
            if let Some(path) = fs_commands::launch_file_from_args(&argv) {
                let _ = app.emit("open-file", serde_json::json!({ "path": path }));
            }
        }))
        .plugin(tauri_plugin_dialog::init())
        .manage(fs_commands::WatcherState::default())
        .manage(fs_commands::LaunchFile(std::sync::Mutex::new(launch)))
        .manage(terminal::TerminalState::default())
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
            fs_commands::get_last_vault,
            fs_commands::set_last_vault,
            fs_commands::export_pdf,
            fs_commands::open_path,
            fs_commands::open_url,
            fs_commands::read_image,
            fs_commands::resolve_doc_link,
            fs_commands::set_api_key,
            fs_commands::delete_api_key,
            ai::ai_chat,
            terminal::terminal_open,
            terminal::terminal_input,
            terminal::terminal_resize,
            terminal::terminal_close,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
