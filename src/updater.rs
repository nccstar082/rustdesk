use crate::{common::do_check_software_update, hbbs_http::create_http_client_with_url};
use hbb_common::{bail, config, log, ResultType};
use std::{
    io::Write,
    path::PathBuf,
    sync::{
        atomic::{AtomicUsize, Ordering},
        mpsc::{channel, Receiver, Sender},
        Mutex,
    },
    time::{Duration, Instant},
};

enum UpdateMsg {
    CheckUpdate,
    Exit,
}

lazy_static::lazy_static! {
    static ref TX_MSG : Mutex<Sender<UpdateMsg>> = Mutex::new(start_auto_update_check());
}

static CONTROLLING_SESSION_COUNT: AtomicUsize = AtomicUsize::new(0);

const DUR_ONE_DAY: Duration = Duration::from_secs(60 * 60 * 24);

pub fn update_controlling_session_count(count: usize) {
    CONTROLLING_SESSION_COUNT.store(count, Ordering::SeqCst);
}

#[allow(dead_code)]
pub fn start_auto_update() {
    let _sender = TX_MSG.lock().unwrap();
}

#[allow(dead_code)]
pub fn manually_check_update() -> ResultType<()> {
    let sender = TX_MSG.lock().unwrap();
    sender.send(UpdateMsg::CheckUpdate)?;
    Ok(())
}

#[allow(dead_code)]
pub fn stop_auto_update() {
    let sender = TX_MSG.lock().unwrap();
    sender.send(UpdateMsg::Exit).unwrap_or_default();
}

#[inline]
fn has_no_active_conns() -> bool {
    let conns = crate::Connection::alive_conns();
    conns.is_empty() && has_no_controlling_conns()
}

#[cfg(any(not(target_os = "windows"), feature = "flutter"))]
fn has_no_controlling_conns() -> bool {
    CONTROLLING_SESSION_COUNT.load(Ordering::SeqCst) == 0
}

#[cfg(not(any(not(target_os = "windows"), feature = "flutter")))]
fn has_no_controlling_conns() -> bool {
    let app_exe = format!("{}.exe", crate::get_app_name().to_lowercase());
    for arg in [
        "--connect",
        "--play",
        "--file-transfer",
        "--view-camera",
        "--port-forward",
        "--rdp",
    ] {
        if !crate::platform::get_pids_of_process_with_first_arg(&app_exe, arg).is_empty() {
            return false;
        }
    }
    true
}

fn start_auto_update_check() -> Sender<UpdateMsg> {
    let (tx, rx) = channel();
    std::thread::spawn(move || start_auto_update_check_(rx));
    return tx;
}

fn start_auto_update_check_(rx_msg: Receiver<UpdateMsg>) {
    std::thread::sleep(Duration::from_secs(30));
    if let Err(e) = check_update(false) {
        log::error!("Error checking for updates: {}", e);
    }

    const MIN_INTERVAL: Duration = Duration::from_secs(60 * 10);
    const RETRY_INTERVAL: Duration = Duration::from_secs(60 * 30);
    let mut last_check_time = Instant::now();
    let mut check_interval = DUR_ONE_DAY;
    loop {
        let recv_res = rx_msg.recv_timeout(check_interval);
        match &recv_res {
            Ok(UpdateMsg::CheckUpdate) | Err(_) => {
                if last_check_time.elapsed() < MIN_INTERVAL {
                    // log::debug!("Update check skipped due to minimum interval.");
                    continue;
                }
                // Don't check update if there are alive connections.
                if !has_no_active_conns() {
                    check_interval = RETRY_INTERVAL;
                    continue;
                }
                if let Err(e) = check_update(matches!(recv_res, Ok(UpdateMsg::CheckUpdate))) {
                    log::error!("Error checking for updates: {}", e);
                    check_interval = RETRY_INTERVAL;
                } else {
                    last_check_time = Instant::now();
                    check_interval = DUR_ONE_DAY;
                }
            }
            Ok(UpdateMsg::Exit) => break,
        }
    }
}

fn check_update(manually: bool) -> ResultType<()> {
    #[cfg(target_os = "windows")]
    let is_msi = crate::platform::is_msi_installed()?;
    if !(manually || config::Config::get_bool_option(config::keys::OPTION_ALLOW_AUTO_UPDATE)) {
        return Ok(());
    }
    if !do_check_software_update().is_ok() {
        // ignore
        return Ok(());
    }

    let update_url = crate::common::SOFTWARE_UPDATE_URL.lock().unwrap().clone();
    let update_version = crate::common::SOFTWARE_UPDATE_VERSION.lock().unwrap().clone();
    let update_exe = crate::common::SOFTWARE_UPDATE_EXE.lock().unwrap().clone();
    if update_url.is_empty() {
        log::debug!("No update available.");
    } else {
        // 处理URL，确保不会生成重复的路径片段
        let mut download_url = if update_url.contains("tag") {
            update_url.replace("tag", "download")
        } else {
            update_url.clone()
        };
        // 优先使用JSON中的版本号，如果为空则从URL中提取
        let version = if !update_version.is_empty() {
            update_version.clone()
        } else {
            // 从URL中提取版本号，确保只获取版本号而不是完整文件名
            let parts: Vec<&str> = download_url.split('/').collect();
            if parts.len() > 2 {
                // 检查倒数第二个路径段是否是版本号
                let candidate = parts[parts.len() - 2];
                // 检查是否符合版本号格式（x.x.x）
                if candidate.matches('.').count() >= 1 {
                    candidate.to_string()
                } else {
                    // 如果不符合，尝试从最后一个路径段中提取
                    let last_segment = parts[parts.len() - 1];
                    if last_segment.starts_with("rustdesk-") {
                        let mut version_part = last_segment.trim_start_matches("rustdesk-");
                        version_part = version_part.split('-').next().unwrap_or(version_part);
                        // 保留完整的版本号（已经通过split('-')移除了平台和架构信息）
                        version_part.to_string()
                    } else {
                        last_segment.to_string()
                    }
                }
            } else {
                download_url.split('/').last().unwrap_or_default().to_string()
            }
        };
        let download_url = if !update_exe.is_empty() {
            // 如果JSON中提供了exe文件名
            let exe_filename = update_exe.split('/').last().unwrap_or(&update_exe);
            
            // 检查download_url是否已经是一个完整的文件URL
            if download_url.ends_with(".exe") || download_url.ends_with(".msi") {
                // 如果download_url已经包含完整文件名，直接使用
                download_url
            } else {
                // 否则，确保download_url以斜杠结尾，然后追加文件名
                let base_url = if download_url.ends_with('/') {
                    download_url.clone()
                } else {
                    format!("{}/", download_url)
                };
                format!("{}{}", base_url, exe_filename)
            }
        } else {
            // 检查download_url是否已经是一个完整的文件URL
            if download_url.ends_with(".exe") || download_url.ends_with(".msi") {
                // 如果已经包含完整文件名，直接使用
                download_url
            } else {
                // 否则，构建完整的文件名
                #[cfg(all(target_os = "windows", feature = "flutter"))]
                let extension = if is_msi { "msi" } else { "exe" };
                #[cfg(all(target_os = "windows", not(feature = "flutter")))]
                let extension = "exe";
                #[cfg(not(target_os = "windows"))]
                let extension = "tar.gz";
                
                // 检查最后一个路径段是否是版本号
                let segments: Vec<&str> = download_url.split('/').collect();
                let last_segment = segments.last().unwrap_or(&"");
                
                // 构建文件名
                let filename = if last_segment.matches('.').count() >= 1 {
                    // 如果最后一个路径段看起来像版本号，直接使用
                    format!("rustdesk-{}-x86_64.{}", last_segment, extension)
                } else {
                    // 否则使用从JSON或URL中提取的版本号
                    format!("rustdesk-{}-x86_64.{}", version, extension)
                };
                
                // 确保download_url以斜杠结尾，然后追加文件名
                let base_url = if download_url.ends_with('/') {
                    download_url.clone()
                } else {
                    format!("{}/", download_url)
                };
                format!("{}{}", base_url, filename)
            }
        };
        log::debug!("New version available: {}", &version);
        let client = create_http_client_with_url(&download_url);
        let Some(file_path) = get_download_file_from_url(&download_url) else {
            bail!("Failed to get the file path from the URL: {}", download_url);
        };
        let mut is_file_exists = false;
        if file_path.exists() {
            // Check if the file size is the same as the server file size
            // If the file size is the same, we don't need to download it again.
            let file_size = std::fs::metadata(&file_path)?.len();
            let response = client.head(&download_url).send()?;
            if !response.status().is_success() {
                bail!("Failed to get the file size: {}", response.status());
            }
            let total_size = response
                .headers()
                .get(reqwest::header::CONTENT_LENGTH)
                .and_then(|ct_len| ct_len.to_str().ok())
                .and_then(|ct_len| ct_len.parse::<u64>().ok());
            let Some(total_size) = total_size else {
                bail!("Failed to get content length");
            };
            if file_size == total_size {
                is_file_exists = true;
            } else {
                std::fs::remove_file(&file_path)?;
            }
        }
        if !is_file_exists {
            let response = client.get(&download_url).send()?;
            if !response.status().is_success() {
                bail!(
                    "Failed to download the new version file: {}",
                    response.status()
                );
            }
            let file_data = response.bytes()?;
            let mut file = std::fs::File::create(&file_path)?;
            file.write_all(&file_data)?;
        }
        // We have checked if the `conns`` is empty before, but we need to check again.
        // No need to care about the downloaded file here, because it's rare case that the `conns` are empty
        // before the download, but not empty after the download.
        if has_no_active_conns() {
            #[cfg(target_os = "windows")]
            update_new_version(is_msi, &version, &file_path);
        }
    }
    Ok(())
}

#[cfg(target_os = "windows")]
fn update_new_version(is_msi: bool, version: &str, file_path: &PathBuf) {
    log::debug!(
        "New version is downloaded, update begin, is msi: {is_msi}, version: {version}, file: {:?}",
        file_path.to_str()
    );
    if let Some(p) = file_path.to_str() {
        if let Some(session_id) = crate::platform::get_current_process_session_id() {
            if is_msi {
                match crate::platform::update_me_msi(p, true) {
                    Ok(_) => {
                        log::debug!("New version \"{}\" updated.", version);
                    }
                    Err(e) => {
                        log::error!(
                            "Failed to install the new msi version  \"{}\": {}",
                            version,
                            e
                        );
                    }
                }
            } else {
                match crate::platform::launch_privileged_process(
                    session_id,
                    &format!("{} --update", p),
                ) {
                    Ok(h) => {
                        if h.is_null() {
                            log::error!("Failed to update to the new version: {}", version);
                        }
                    }
                    Err(e) => {
                        log::error!("Failed to run the new version: {}", e);
                    }
                }
            }
        } else {
            log::error!(
                "Failed to get the current process session id, Error {}",
                std::io::Error::last_os_error()
            );
        }
    } else {
        // unreachable!()
        log::error!(
            "Failed to convert the file path to string: {}",
            file_path.display()
        );
    }
}

pub fn get_download_file_from_url(url: &str) -> Option<PathBuf> {
    // 清理URL，移除重复的文件名部分
    let mut filename = url.split('/').last()?.to_string();
    
    // 检查并修复各种可能的重复文件名情况
    // 1. 修复重复的rustdesk前缀
    while filename.contains("rustdesk-rustdesk-") {
        filename = filename.replace("rustdesk-rustdesk-", "rustdesk-");
    }
    
    // 2. 修复重复的.exe后缀
    while filename.contains(".exe.exe") {
        filename = filename.replace(".exe.exe", ".exe");
    }
    
    // 3. 修复重复的.msi后缀
    while filename.contains(".msi.msi") {
        filename = filename.replace(".msi.msi", ".msi");
    }
    
    // 4. 修复重复的-x86_64.exe组合
    while filename.contains("-x86_64.exe-x86_64.exe") {
        filename = filename.replace("-x86_64.exe-x86_64.exe", "-x86_64.exe");
    }
    
    // 5. 修复重复的-x86_64.msi组合
    while filename.contains("-x86_64.msi-x86_64.msi") {
        filename = filename.replace("-x86_64.msi-x86_64.msi", "-x86_64.msi");
    }
    
    // 6. 修复重复的架构信息
    while filename.contains("-x86_64-x86_64-") {
        filename = filename.replace("-x86_64-x86_64-", "-x86_64-");
    }
    
    #[cfg(target_os = "android")]
    {
        // 在Android上，将更新文件存储在外部存储的Download目录中
        // 这样系统安装程序可以访问它
        let mut path = PathBuf::new();
        if let Some(external_storage) = std::env::var_os("EXTERNAL_STORAGE") {
            path.push(external_storage);
            path.push("Download");
            path.push(filename);
            return Some(path);
        }
    }
    // 其他平台使用系统临时目录
    Some(std::env::temp_dir().join(filename))
}
