use std::{
    collections::HashMap,
    iter::FromIterator,
    sync::{Arc, Mutex},
};

use sciter::Value;

use hbb_common::{
    allow_err,
    config::{LocalConfig, PeerConfig},
    log,
};

#[cfg(not(any(feature = "flutter", feature = "cli")))]
use crate::ui_session_interface::Session;
use crate::{common::get_app_name, ipc, ui_interface::*};

mod cm;
#[cfg(feature = "inline")]
pub mod inline;
pub mod remote;

#[allow(dead_code)]
type Status = (i32, bool, i64, String);

lazy_static::lazy_static! {
    // stupid workaround for https://sciter.com/forums/topic/crash-on-latest-tis-mac-sdk-sometimes/
    static ref STUPID_VALUES: Mutex<Vec<Arc<Vec<Value>>>> = Default::default();
}

#[cfg(not(any(feature = "flutter", feature = "cli")))]
lazy_static::lazy_static! {
    pub static ref CUR_SESSION: Arc<Mutex<Option<Session<remote::SciterHandler>>>> = Default::default();
}

struct UIHostHandler;

pub fn start(args: &mut [String]) {
    #[cfg(target_os = "macos")]
    crate::platform::delegate::show_dock();
    #[cfg(all(target_os = "linux", feature = "inline"))]
    {
        let app_dir = std::env::var("APPDIR").unwrap_or("".to_string());
        let mut so_path = "/usr/share/rustdesk/libsciter-gtk.so".to_owned();
        for (prefix, dir) in [
            ("", "/usr"),
            ("", "/app"),
            (&app_dir, "/usr"),
            (&app_dir, "/app"),
        ]
        .iter()
        {
            let path = format!("{prefix}{dir}/share/rustdesk/libsciter-gtk.so");
            if std::path::Path::new(&path).exists() {
                so_path = path;
                break;
            }
        }
        sciter::set_library(&so_path).ok();
    }
    #[cfg(windows)]
    // Check if there is a sciter.dll nearby.
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            let sciter_dll_path = parent.join("sciter.dll");
            if sciter_dll_path.exists() {
                // Try to set the sciter dll.
                let p = sciter_dll_path.to_string_lossy().to_string();
                log::debug!("Found dll:{}, \n {:?}", p, sciter::set_library(&p));
            }
        }
    }
    // https://github.com/c-smile/sciter-sdk/blob/master/include/sciter-x-types.h
    // https://github.com/rustdesk/rustdesk/issues/132#issuecomment-886069737
    #[cfg(windows)]
    allow_err!(sciter::set_options(sciter::RuntimeOptions::GfxLayer(
        sciter::GFX_LAYER::WARP
    )));
    use sciter::SCRIPT_RUNTIME_FEATURES::*;
    allow_err!(sciter::set_options(sciter::RuntimeOptions::ScriptFeatures(
        ALLOW_FILE_IO as u8 | ALLOW_SOCKET_IO as u8 | ALLOW_EVAL as u8 | ALLOW_SYSINFO as u8
    )));
    let mut frame = sciter::WindowBuilder::main_window().create();
    #[cfg(windows)]
    allow_err!(sciter::set_options(sciter::RuntimeOptions::UxTheming(true)));
    frame.set_title(&crate::get_app_name());
    #[cfg(target_os = "macos")]
    crate::platform::delegate::make_menubar(frame.get_host(), args.is_empty());
    #[cfg(windows)]
    crate::platform::try_set_window_foreground(frame.get_hwnd() as _);
    let page;
    if args.len() > 1 && args[0] == "--play" {
        args[0] = "--connect".to_owned();
        let path: std::path::PathBuf = (&args[1]).into();
        let id = path
            .file_stem()
            .map(|p| p.to_str().unwrap_or(""))
            .unwrap_or("")
            .to_owned();
        args[1] = id;
    }
    if args.is_empty() {
        std::thread::spawn(move || check_zombie());
        crate::common::check_software_update();
        frame.event_handler(UI {});
        frame.sciter_handler(UIHostHandler {});
        page = "index.html";
        // Start pulse audio local server.
        #[cfg(target_os = "linux")]
        std::thread::spawn(crate::ipc::start_pa);
    } else if args[0] == "--install" {
        frame.event_handler(UI {});
        frame.sciter_handler(UIHostHandler {});
        page = "install.html";
    } else if args[0] == "--cm" {
        frame.register_behavior("connection-manager", move || {
            Box::new(cm::SciterConnectionManager::new())
        });
        page = "cm.html";
        *cm::HIDE_CM.lock().unwrap() = crate::ipc::get_config("hide_cm")
            .ok()
            .flatten()
            .unwrap_or_default()
            == "true";
    } else if (args[0] == "--connect"
        || args[0] == "--file-transfer"
        || args[0] == "--port-forward"
        || args[0] == "--rdp")
        && args.len() > 1
    {
        #[cfg(windows)]
        {
            let hw = frame.get_host().get_hwnd();
            crate::platform::windows::enable_lowlevel_keyboard(hw as _);
        }
        let mut iter = args.iter();
        let Some(cmd) = iter.next() else {
            log::error!("Failed to get cmd arg");
            return;
        };
        let cmd = cmd.to_owned();
        let Some(id) = iter.next() else {
            log::error!("Failed to get id arg");
            return;
        };
        let id = id.to_owned();
        let pass = iter.next().unwrap_or(&"".to_owned()).clone();
        let args: Vec<String> = iter.map(|x| x.clone()).collect();
        frame.set_title(&id);
        frame.register_behavior("native-remote", move || {
            let handler =
                remote::SciterSession::new(cmd.clone(), id.clone(), pass.clone(), args.clone());
            #[cfg(not(any(feature = "flutter", feature = "cli")))]
            {
                *CUR_SESSION.lock().unwrap() = Some(handler.inner());
            }
            Box::new(handler)
        });
        page = "remote.html";
    } else {
        log::error!("Wrong command: {:?}", args);
        return;
    }
    #[cfg(feature = "inline")]
    {
        let html = if page == "index.html" {
            inline::get_index()
        } else if page == "cm.html" {
            inline::get_cm()
        } else if page == "install.html" {
            inline::get_install()
        } else {
            inline::get_remote()
        };
        frame.load_html(html.as_bytes(), Some(page));
    }
    #[cfg(not(feature = "inline"))]
    frame.load_file(&format!(
        "file://{}/src/ui/{}",
        std::env::current_dir()
            .map(|c| c.display().to_string())
            .unwrap_or("".to_owned()),
        page
    ));
    let hide_cm = *cm::HIDE_CM.lock().unwrap();
    if !args.is_empty() && args[0] == "--cm" && hide_cm {
        // run_app calls expand(show) + run_loop, we use collapse(hide) + run_loop instead to create a hidden window
        frame.collapse(true);
        frame.run_loop();
        return;
    }
    frame.run_app();
}

struct UI {}

impl UI {
    fn recent_sessions_updated(&self) -> bool {
        recent_sessions_updated()
    }

    fn get_id(&self) -> String {
        ipc::get_id()
    }

    fn temporary_password(&mut self) -> String {
        temporary_password()
    }

    fn update_temporary_password(&self) {
        update_temporary_password()
    }

    fn permanent_password(&self) -> String {
        permanent_password()
    }

    fn set_permanent_password(&self, password: String) {
        set_permanent_password(password);
    }

    fn get_remote_id(&mut self) -> String {
        LocalConfig::get_remote_id()
    }

    fn set_remote_id(&mut self, id: String) {
        LocalConfig::set_remote_id(&id);
    }

    fn goto_install(&mut self) {
        goto_install();
    }

    fn install_me(&mut self, _options: String, _path: String) {
        install_me(_options, _path, false, false);
    }

    fn update_me(&self, _path: String) {
        update_me(_path);
    }

    fn run_without_install(&self) {
        run_without_install();
    }

    fn show_run_without_install(&self) -> bool {
        show_run_without_install()
    }

    fn get_license(&self) -> String {
        get_license()
    }

    fn get_option(&self, key: String) -> String {
        get_option(key)
    }

    fn get_local_option(&self, key: String) -> String {
        get_local_option(key)
    }

    fn set_local_option(&self, key: String, value: String) {
        set_local_option(key, value);
    }

    fn peer_has_password(&self, id: String) -> bool {
        peer_has_password(id)
    }

    fn forget_password(&self, id: String) {
        forget_password(id)
    }

    fn get_peer_option(&self, id: String, name: String) -> String {
        get_peer_option(id, name)
    }

    fn set_peer_option(&self, id: String, name: String, value: String) {
        set_peer_option(id, name, value)
    }

    fn using_public_server(&self) -> bool {
        crate::using_public_server()
    }

    fn is_incoming_only(&self) -> bool {
        hbb_common::config::is_incoming_only()
    }

    pub fn is_outgoing_only(&self) -> bool {
        hbb_common::config::is_outgoing_only()
    }

    pub fn is_custom_client(&self) -> bool {
        crate::common::is_custom_client()
    }

    pub fn is_disable_settings(&self) -> bool {
        hbb_common::config::is_disable_settings()
    }

    pub fn is_disable_account(&self) -> bool {
        hbb_common::config::is_disable_account()
    }

    pub fn is_disable_installation(&self) -> bool {
        hbb_common::config::is_disable_installation()
    }

    pub fn is_disable_ab(&self) -> bool {
        hbb_common::config::is_disable_ab()
    }

    fn get_options(&self) -> Value {
        let hashmap: HashMap<String, String> =
            serde_json::from_str(&get_options()).unwrap_or_default();
        let mut m = Value::map();
        for (k, v) in hashmap {
            m.set_item(k, v);
        }
        m
    }

    fn test_if_valid_server(&self, host: String, test_with_proxy: bool) -> String {
        test_if_valid_server(host, test_with_proxy)
    }

    fn get_sound_inputs(&self) -> Value {
        Value::from_iter(get_sound_inputs())
    }

    fn set_options(&self, v: Value) {
        let mut m = HashMap::new();
        for (k, v) in v.items() {
            if let Some(k) = k.as_string() {
                if let Some(v) = v.as_string() {
                    if !v.is_empty() {
                        m.insert(k, v);
                    }
                }
            }
        }
        set_options(m);
    }

    fn set_option(&self, key: String, value: String) {
        set_option(key, value);
    }

    fn install_path(&mut self) -> String {
        install_path()
    }

    fn install_options(&self) -> String {
        install_options()
    }

    fn get_socks(&self) -> Value {
        Value::from_iter(get_socks())
    }

    fn set_socks(&self, proxy: String, username: String, password: String) {
        set_socks(proxy, username, password)
    }

    fn is_installed(&self) -> bool {
        is_installed()
    }

    fn is_root(&self) -> bool {
        is_root()
    }

    fn is_release(&self) -> bool {
        #[cfg(not(debug_assertions))]
        return true;
        #[cfg(debug_assertions)]
        return false;
    }

    fn is_share_rdp(&self) -> bool {
        is_share_rdp()
    }

    fn set_share_rdp(&self, _enable: bool) {
        set_share_rdp(_enable);
    }

    fn is_installed_lower_version(&self) -> bool {
        is_installed_lower_version()
    }

    fn closing(&mut self, x: i32, y: i32, w: i32, h: i32) {
        crate::server::input_service::fix_key_down_timeout_at_exit();
        LocalConfig::set_size(x, y, w, h);
    }

    fn get_size(&mut self) -> Value {
        let s = LocalConfig::get_size();
        let mut v = Vec::new();
        v.push(s.0);
        v.push(s.1);
        v.push(s.2);
        v.push(s.3);
        Value::from_iter(v)
    }

    fn get_mouse_time(&self) -> f64 {
        get_mouse_time()
    }

    fn check_mouse_time(&self) {
        check_mouse_time()
    }

    fn get_connect_status(&mut self) -> Value {
        let mut v = Value::array(0);
        let x = get_connect_status();
        v.push(x.status_num);
        v.push(x.key_confirmed);
        v.push(x.id);
        v
    }

    #[inline]
    fn get_peer_value(id: String, p: PeerConfig) -> Value {
        let values = vec![
            id,
            p.info.username.clone(),
            p.info.hostname.clone(),
            p.info.platform.clone(),
            p.options.get("alias").unwrap_or(&"".to_owned()).to_owned(),
        ];
        Value::from_iter(values)
    }

    fn get_peer(&self, id: String) -> Value {
        let c = get_peer(id.clone());
        Self::get_peer_value(id, c)
    }

    fn get_fav(&self) -> Value {
        Value::from_iter(get_fav())
    }

    fn store_fav(&self, fav: Value) {
        let mut tmp = vec![];
        fav.values().for_each(|v| {
            if let Some(v) = v.as_string() {
                if !v.is_empty() {
                    tmp.push(v);
                }
            }
        });
        store_fav(tmp);
    }

    fn get_recent_sessions(&mut self) -> Value {
        // to-do: limit number of recent sessions, and remove old peer file
        let peers: Vec<Value> = PeerConfig::peers(None)
            .drain(..)
            .map(|p| Self::get_peer_value(p.0, p.2))
            .collect();
        Value::from_iter(peers)
    }

    fn get_icon(&mut self) -> String {
        get_icon()
    }

    fn remove_peer(&mut self, id: String) {
        PeerConfig::remove(&id);
    }

    fn remove_discovered(&mut self, id: String) {
        remove_discovered(id);
    }

    fn send_wol(&mut self, id: String) {
        crate::lan::send_wol(id)
    }

    fn new_remote(&mut self, id: String, remote_type: String, force_relay: bool) {
        new_remote(id, remote_type, force_relay)
    }

    fn is_process_trusted(&mut self, _prompt: bool) -> bool {
        is_process_trusted(_prompt)
    }

    fn is_can_screen_recording(&mut self, _prompt: bool) -> bool {
        is_can_screen_recording(_prompt)
    }

    fn is_installed_daemon(&mut self, _prompt: bool) -> bool {
        is_installed_daemon(_prompt)
    }

    fn get_error(&mut self) -> String {
        get_error()
    }

    fn is_login_wayland(&mut self) -> bool {
        is_login_wayland()
    }

    fn current_is_wayland(&mut self) -> bool {
        current_is_wayland()
    }

    fn get_software_update_url(&self) -> String {
        crate::SOFTWARE_UPDATE_URL.lock().unwrap().clone()
    }

    fn get_new_version(&self) -> String {
        get_new_version()
    }

    fn get_version(&self) -> String {
        get_version()
    }

    fn get_fingerprint(&self) -> String {
        get_fingerprint()
    }

    fn get_app_name(&self) -> String {
        get_app_name()
    }

    fn get_software_ext(&self) -> String {
        #[cfg(windows)]
        let p = "exe";
        #[cfg(target_os = "macos")]
        let p = "dmg";
        #[cfg(target_os = "linux")]
        let p = "deb";
        p.to_owned()
    }

    fn get_software_store_path(&self) -> String {
        let mut p = std::env::temp_dir();
        let name = crate::SOFTWARE_UPDATE_URL
            .lock()
            .unwrap()
            .split("/")
            .last()
            .map(|x| x.to_owned())
            .unwrap_or(crate::get_app_name());
        p.push(name);
        format!("{}.{}", p.to_string_lossy(), self.get_software_ext())
    }

    fn create_shortcut(&self, _id: String) {
        #[cfg(windows)]
        create_shortcut(_id)
    }

    fn discover(&self) {
        std::thread::spawn(move || {
            allow_err!(crate::lan::discover());
        });
    }

    fn get_lan_peers(&self) -> String {
        // let peers = get_lan_peers()
        //     .into_iter()
        //     .map(|mut peer| {
        //         (
        //             peer.remove("id").unwrap_or_default(),
        //             peer.remove("username").unwrap_or_default(),
        //             peer.remove("hostname").unwrap_or_default(),
        //             peer.remove("platform").unwrap_or_default(),
        //         )
        //     })
        //     .collect::<Vec<(String, String, String, String)>>();
        serde_json::to_string(&get_lan_peers()).unwrap_or_default()
    }

    fn get_uuid(&self) -> String {
        get_uuid()
    }

    fn open_url(&self, url: String) {
        #[cfg(windows)]
        let p = "explorer";
        #[cfg(target_os = "macos")]
        let p = "open";
        #[cfg(target_os = "linux")]
        let p = if std::path::Path::new("/usr/bin/firefox").exists() {
            "firefox"
        } else {
            "xdg-open"
        };
        allow_err!(std::process::Command::new(p).arg(url).spawn());
    }

    fn change_id(&self, id: String) {
        reset_async_job_status();
        let old_id = self.get_id();
        change_id_shared(id, old_id);
    }

    fn http_request(&self, url: String, method: String, body: Option<String>, header: String) {
        http_request(url, method, body, header)
    }

    fn post_request(&self, url: String, body: String, header: String) {
        post_request(url, body, header)
    }

    fn is_ok_change_id(&self) -> bool {
        hbb_common::machine_uid::get().is_ok()
    }

    fn get_async_job_status(&self) -> String {
        get_async_job_status()
    }

    fn get_http_status(&self, url: String) -> Option<String> {
        get_async_http_status(url)
    }

    fn t(&self, name: String) -> String {
        crate::client::translate(name)
    }

    fn is_xfce(&self) -> bool {
        crate::platform::is_xfce()
    }

    fn get_api_server(&self) -> String {
        get_api_server()
    }

    fn has_hwcodec(&self) -> bool {
        has_hwcodec()
    }

    fn has_vram(&self) -> bool {
        has_vram()
    }

    fn get_langs(&self) -> String {
        get_langs()
    }

    fn video_save_directory(&self, root: bool) -> String {
        video_save_directory(root)
    }

    fn handle_relay_id(&self, id: String) -> String {
        handle_relay_id(&id).to_owned()
    }

    fn get_login_device_info(&self) -> String {
        get_login_device_info_json()
    }

    fn support_remove_wallpaper(&self) -> bool {
        support_remove_wallpaper()
    }

    fn has_valid_2fa(&self) -> bool {
        has_valid_2fa()
    }

    fn generate2fa(&self) -> String {
        generate2fa()
    }

    pub fn verify2fa(&self, code: String) -> bool {
        verify2fa(code)
    }

    fn verify_login(&self, raw: String, id: String) -> bool {
        crate::verify_login(&raw, &id)
    }

    fn generate_2fa_img_src(&self, data: String) -> String {
        let v = qrcode_generator::to_png_to_vec(data, qrcode_generator::QrCodeEcc::Low, 128)
            .unwrap_or_default();
        let s = hbb_common::sodiumoxide::base64::encode(
            v,
            hbb_common::sodiumoxide::base64::Variant::Original,
        );
        format!("data:image/png;base64,{s}")
    }

    pub fn check_hwcodec(&self) {
        check_hwcodec()
    }

    fn is_option_fixed(&self, key: String) -> bool {
        crate::ui_interface::is_option_fixed(&key)
    }

    fn get_builtin_option(&self, key: String) -> String {
        crate::ui_interface::get_builtin_option(&key)
    }

    fn is_remote_modify_enabled_by_control_permissions(&self) -> String {
        match crate::ui_interface::is_remote_modify_enabled_by_control_permissions() {
            Some(true) => "true",
            Some(false) => "false",
            None => "",
        }
        .to_string()
    }
}

impl sciter::EventHandler for UI {
    sciter::dispatch_script_call! {
        fn t(String);
        fn get_api_server();
        fn is_xfce();
        fn using_public_server();
        fn is_custom_client();
        fn is_outgoing_only();
        fn is_incoming_only();
        fn is_disable_settings();
        fn is_disable_account();
        fn is_disable_installation();
        fn is_disable_ab();
        fn get_id();
        fn temporary_password();
        fn update_temporary_password();
        fn permanent_password();
        fn set_permanent_password(String);
        fn get_remote_id();
        fn set_remote_id(String);
        fn closing(i32, i32, i32, i32);
        fn get_size();
        fn new_remote(String, String, bool);
        fn send_wol(String);
        fn remove_peer(String);
        fn remove_discovered(String);
        fn get_connect_status();
        fn get_mouse_time();
        fn check_mouse_time();
        fn get_recent_sessions();
        fn get_peer(String);
        fn get_fav();
        fn store_fav(Value);
        fn recent_sessions_updated();
        fn get_icon();
        fn install_me(String, String);
        fn is_installed();
        fn is_root();
        fn is_release();
        fn set_socks(String, String, String);
        fn get_socks();
        fn is_share_rdp();
        fn set_share_rdp(bool);
        fn is_installed_lower_version();
        fn install_path();
        fn install_options();
        fn goto_install();
        fn is_process_trusted(bool);
        fn is_can_screen_recording(bool);
        fn is_installed_daemon(bool);
        fn get_error();
        fn is_login_wayland();
        fn current_is_wayland();
        fn get_options();
        fn get_option(String);
        fn get_local_option(String);
        fn set_local_option(String, String);
        fn get_peer_option(String, String);
        fn peer_has_password(String);
        fn forget_password(String);
        fn set_peer_option(String, String, String);
        fn get_license();
        fn test_if_valid_server(String, bool);
        fn get_sound_inputs();
        fn set_options(Value);
        fn set_option(String, String);
        fn get_software_update_url();
        fn get_new_version();
        fn get_version();
        fn get_fingerprint();
        fn update_me(String);
        fn show_run_without_install();
        fn run_without_install();
        fn get_app_name();
        fn get_software_store_path();
        fn get_software_ext();
        fn open_url(String);
        fn change_id(String);
        fn get_async_job_status();
        fn post_request(String, String, String);
        fn is_ok_change_id();
        fn create_shortcut(String);
        fn discover();
        fn get_lan_peers();
        fn get_uuid();
        fn has_hwcodec();
        fn has_vram();
        fn get_langs();
        fn video_save_directory(bool);
        fn handle_relay_id(String);
        fn get_login_device_info();
        fn support_remove_wallpaper();
        fn has_valid_2fa();
        fn generate2fa();
        fn generate_2fa_img_src(String);
        fn verify2fa(String);
        fn check_hwcodec();
        fn verify_login(String, String);
        fn is_option_fixed(String);
        fn get_builtin_option(String);
        fn is_remote_modify_enabled_by_control_permissions();
    }
}

impl sciter::host::HostHandler for UIHostHandler {
    fn on_graphics_critical_failure(&mut self) {
        log::error!("Critical rendering error: e.g. DirectX gfx driver error. Most probably bad gfx drivers.");
    }
}

#[cfg(not(target_os = "linux"))]
fn get_sound_inputs() -> Vec<String> {
    let mut out = Vec::new();
    use cpal::traits::{DeviceTrait, HostTrait};
    let host = cpal::default_host();
    if let Ok(devices) = host.devices() {
        for device in devices {
            if device.default_input_config().is_err() {
                continue;
            }
            if let Ok(name) = device.name() {
                out.push(name);
            }
        }
    }
    out
}

#[cfg(target_os = "linux")]
fn get_sound_inputs() -> Vec<String> {
    crate::platform::linux::get_pa_sources()
        .drain(..)
        .map(|x| x.1)
        .collect()
}

// sacrifice some memory
pub fn value_crash_workaround(values: &[Value]) -> Arc<Vec<Value>> {
    let persist = Arc::new(values.to_vec());
    STUPID_VALUES.lock().unwrap().push(persist.clone());
    persist
}

pub fn get_icon() -> String {
    // 128x128
    #[cfg(target_os = "macos")]
    // 128x128 on 160x160 canvas, then shrink to 128, mac looks better with padding
    {
        "data:image/png;base64,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".into()
    }
    #[cfg(not(target_os = "macos"))] // 128x128 no padding
    {
        "data:image/png;base64,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".into()
    }
}