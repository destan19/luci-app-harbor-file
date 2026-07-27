module("luci.controller.harbor_file", package.seeall)

local unpack = table.unpack or unpack
_ = require("luci.i18n").translate

local common_directory_entries = {
    { name = "Documents", path_name = "documents", icon = "documents" },
    { name = "Pictures", path_name = "pictures", icon = "pictures" },
    { name = "Videos", path_name = "videos", icon = "videos" },
    { name = "Music", path_name = "music", icon = "music" },
    { name = "Downloads", path_name = "downloads", icon = "downloads" }
}

local hidden_mounts = {
    ["/rom"] = true,
    ["/overlay"] = true,
    ["/dev"] = true
}

local system_folder_roots = {
    "/bin",
    "/sbin",
    "/proc",
    "/dev",
    "/usr/bin",
    "/usr/sbin",
    "/usr/lib",
    "/usr/lib64",
    "/sys",
    "/lib64",
    "/overlay",
    "/rom"
}

local image_mime_map = {
    png = "image/png",
    jpg = "image/jpeg",
    jpeg = "image/jpeg",
    gif = "image/gif",
    bmp = "image/bmp",
    webp = "image/webp",
    svg = "image/svg+xml",
    ico = "image/x-icon",
    avif = "image/avif"
}

local text_ext_map = {
    txt = true,
    log = true,
    conf = true,
    cfg = true,
    ini = true,
    json = true,
    xml = true,
    csv = true,
    lua = true,
    sh = true,
    md = true,
    yaml = true,
    yml = true,
    html = true,
    htm = true,
    css = true,
    js = true
}

local video_mime_map = {
    mp4 = "video/mp4",
    webm = "video/webm",
    ogg = "video/ogg",
    ogv = "video/ogg",
    mov = "video/quicktime",
    m4v = "video/x-m4v",
    mkv = "video/x-matroska",
    avi = "video/x-msvideo"
}

local pdf_mime_map = {
    pdf = "application/pdf"
}

local package_ext_map = {
    ipk = {
        installer = "opkg",
        display_type = "IPK Package"
    },
    apk = {
        installer = "apk",
        display_type = "APK Package"
    }
}

local package_index_cache_roots = {
    opkg = {
        "/tmp/opkg-lists",
        "/var/opkg-lists"
    },
    apk = {
        "/var/cache/apk",
        "/etc/apk/cache",
        "/var/lib/apk"
    }
}

local opkg_required_feed_groups = {
    { "base" },
    { "luci" },
    { "packages" },
    { "routing", "routting" },
    { "telephony" }
}

local max_text_size = 524288
local default_binary_read_kb = 16
local max_binary_read_kb = 16
local max_binary_read_size = max_binary_read_kb * 1024
local operation_space_margin = 50 * 1024 * 1024
local upload_safety_margin = operation_space_margin
local thumbnail_memory_margin = 20 * 1024
local insufficient_space_message = "available space is less than 50MB, operation is not allowed"
local video_log_file = "/tmp/harbor_file_video.log"
local package_install_state_file = "/tmp/harbor_file_package_install_state.json"
local package_install_log_file = "/tmp/harbor_file_package_install.log"
local package_install_log_limit = 131072
local thumbnail_task_state_file = "/tmp/harbor_file_thumbnail_state.json"
local thumbnail_task_log_file = "/tmp/harbor_file_thumbnail.log"
local thumbnail_task_log_limit = 65536
local thumbnail_size = 128
local thumbnail_cache_version = "contain-v2"
local preference_defaults = {
    view_mode = 1,
    allow_system_operations = 0,
    show_hidden_files = 0,
    home_dir = "/tmp/root",
    enable_thumbnails = 0
}
local valid_view_mode_values = {
    [0] = true,
    [1] = true,
    [2] = true,
    [3] = true,
    [4] = true,
    [5] = true
}
local valid_boolean_values = {
    [0] = true,
    [1] = true
}
local find_executable
local is_hidden_file_name

function index()
	local nixio_fs = require "nixio.fs"
    local fwx_dir = nixio_fs.stat("/etc/fwxd")
    if fwx_dir and fwx_dir.type == "dir" then
        entry({"admin", "fwx_harbor_file"}, template("harbor_file/index"), _("File management"), 16).dependent = true
    else
        entry({"admin", "harbor_file"}, alias("admin", "system", "harbor_file"), nil).leaf = true
        entry({"admin", "system", "harbor_file"}, template("harbor_file/index"), _("Harbor File"), 90).dependent = true
    end
    entry({"admin", "local_fs", "navigation"}, call("api_navigation"), nil).leaf = true
    entry({"admin", "local_fs", "terminal_info"}, call("api_terminal_info"), nil).leaf = true
    entry({"admin", "local_fs", "preferences"}, call("api_preferences"), nil).leaf = true
    entry({"admin", "local_fs", "save_preferences"}, call("api_save_preferences"), nil).leaf = true
    entry({"admin", "local_fs", "list"}, call("api_list"), nil).leaf = true
    entry({"admin", "local_fs", "download"}, call("api_download"), nil).leaf = true
    entry({"admin", "local_fs", "read_text"}, call("api_read_text"), nil).leaf = true
    entry({"admin", "local_fs", "read_binary"}, call("api_read_binary"), nil).leaf = true
    entry({"admin", "local_fs", "save_text"}, call("api_save_text"), nil).leaf = true
    entry({"admin", "local_fs", "image"}, call("api_image"), nil).leaf = true
    entry({"admin", "local_fs", "thumbnail"}, call("api_thumbnail"), nil).leaf = true
    entry({"admin", "local_fs", "thumbnail_generate_start"}, call("api_thumbnail_generate_start"), nil).leaf = true
    entry({"admin", "local_fs", "thumbnail_generate_status"}, call("api_thumbnail_generate_status"), nil).leaf = true
    entry({"admin", "local_fs", "thumbnail_tool_install_start"}, call("api_thumbnail_tool_install_start"), nil).leaf = true
    entry({"admin", "local_fs", "pdf"}, call("api_pdf"), nil).leaf = true
    entry({"admin", "local_fs", "video"}, call("api_video"), nil).leaf = true
    entry({"admin", "local_fs", "video_log"}, call("api_video_log"), nil).leaf = true
    entry({"admin", "local_fs", "upload_check"}, call("api_upload_check"), nil).leaf = true
    entry({"admin", "local_fs", "upload"}, call("api_upload"), nil).leaf = true
    entry({"admin", "local_fs", "create_directory"}, call("api_create_directory"), nil).leaf = true
    entry({"admin", "local_fs", "create_file"}, call("api_create_file"), nil).leaf = true
    entry({"admin", "local_fs", "rename"}, call("api_rename"), nil).leaf = true
    entry({"admin", "local_fs", "delete"}, call("api_delete"), nil).leaf = true
    entry({"admin", "local_fs", "copy"}, call("api_copy"), nil).leaf = true
    entry({"admin", "local_fs", "move"}, call("api_move"), nil).leaf = true
    entry({"admin", "local_fs", "batch_copy"}, call("api_batch_copy"), nil).leaf = true
    entry({"admin", "local_fs", "batch_move"}, call("api_batch_move"), nil).leaf = true
    entry({"admin", "local_fs", "batch_delete"}, call("api_batch_delete"), nil).leaf = true
    entry({"admin", "local_fs", "package_install_start"}, call("api_package_install_start"), nil).leaf = true
    entry({"admin", "local_fs", "package_install_status"}, call("api_package_install_status"), nil).leaf = true
end

local function write_json(data)
    local jsonc = require "luci.jsonc"
    luci.http.prepare_content("application/json")
    luci.http.write(jsonc.stringify(data))
end

local function set_status(code, reason)
    if luci.http.status then
        luci.http.status(code, reason)
    else
        luci.http.header("Status", tostring(code) .. " " .. tostring(reason or ""))
    end
end

local function write_json_status(code, reason, data)
    set_status(code, reason)
    write_json(data)
end

local function write_plain_status(code, reason, message)
    set_status(code, reason)
    luci.http.prepare_content("text/plain")
    luci.http.write(message)
end

local function video_now_ms()
    local nixio = require "nixio"
    local seconds, microseconds = nixio.gettimeofday()
    return (tonumber(seconds) or 0) * 1000 + math.floor((tonumber(microseconds) or 0) / 1000)
end

local function clean_log_value(value)
    return tostring(value or ""):gsub("[%z\1-\31\127]", "?"):sub(1, 512)
end

local function current_timestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

local function read_json_file(path)
    local nixio_fs = require "nixio.fs"
    local jsonc = require "luci.jsonc"
    local content = nixio_fs.readfile(path)
    if not content or content == "" then
        return nil
    end
    local data = jsonc.parse(content)
    return type(data) == "table" and data or nil
end

local function write_json_file(path, data)
    local nixio_fs = require "nixio.fs"
    local jsonc = require "luci.jsonc"
    local content = jsonc.stringify(data)
    if not content then
        return false
    end
    return nixio_fs.writefile(path, content)
end

local function hb_log(log_path, message)
    local nixio_fs = require "nixio.fs"
    local stat = nixio_fs.stat(log_path)
    if stat and (stat.size or 0) >= 262144 then
        nixio_fs.unlink(log_path .. ".1")
        os.rename(log_path, log_path .. ".1")
    end
    local fd = io.open(log_path, "a")
    if fd then
        fd:write(string.format("[%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), tostring(message or "")))
        fd:close()
    end
end

local function truncate_log_text(content, limit)
    if not content or content == "" then
        return ""
    end
    if #content <= limit then
        return content
    end
    return "... truncated ...\n" .. content:sub(#content - limit + 1)
end

local function read_log_file(path, limit)
    local nixio_fs = require "nixio.fs"
    return truncate_log_text(nixio_fs.readfile(path) or "", limit or package_install_log_limit)
end

local function shell_quote(value)
    local text = tostring(value or "")
    return "'" .. text:gsub("'", [['"'"']]) .. "'"
end

local function describe_http_environment()
    local ok, environment = pcall(luci.http.getenv)
    if not ok or type(environment) ~= "table" then
        return "env_table=" .. (ok and type(environment) or "error")
    end
    local keys = {}
    local ranges = {}
    for key, value in pairs(environment) do
        local name = tostring(key)
        table.insert(keys, name)
        if name:upper():find("RANGE", 1, true) then
            table.insert(ranges, name .. "=" .. clean_log_value(value))
        end
    end
    table.sort(keys)
    table.sort(ranges)
    return "range_values=" .. table.concat(ranges, ",") .. " env_keys=" .. table.concat(keys, ",")
end

local function normalize_path(path)
    if type(path) ~= "string" or path == "" or path:sub(1, 1) ~= "/" then
        return nil
    end

    local parts = {}
    for segment in path:gmatch("[^/]+") do
        if segment == ".." then
            if #parts == 0 then
                return nil
            end
            table.remove(parts)
        elseif segment ~= "." and segment ~= "" then
            table.insert(parts, segment)
        end
    end

    if #parts == 0 then
        return "/"
    end

    return "/" .. table.concat(parts, "/")
end

local function parent_path(path)
    if not path or path == "/" then
        return "/"
    end

    local parent = path:match("(.+)/[^/]+$")
    if not parent or parent == "" then
        return "/"
    end

    return parent
end

local function join_path(base, name)
    if base == "/" then
        return "/" .. name
    end
    return base .. "/" .. name
end

local function get_ext(name)
    local base_name = name and name:match("([^/]+)$") or nil
    local ext = base_name and base_name:match("%.([^.]+)$") or nil
    return ext and ext:lower() or ""
end

local function is_child_path(path, root)
    return path == root or path:sub(1, #root + 1) == root .. "/"
end

local function normalize_preference_number(value, default_value, valid_values)
    local number = tonumber(value)
    if not number then
        return default_value
    end
    number = math.floor(number)
    if valid_values and not valid_values[number] then
        return default_value
    end
    return number
end

local function normalize_home_dir(value)
    local normalized = normalize_path(value)
    if not normalized then
        return preference_defaults.home_dir
    end
    return normalized
end

local function mkdir_p(path)
    local nixio_fs = require "nixio.fs"
    local normalized = normalize_path(path)
    if not normalized then
        return false
    end
    if normalized == "/" then
        return true
    end
    local existing = nixio_fs.stat(normalized)
    if existing then
        return existing.type == "dir"
    end

    local current = ""
    for part in normalized:gmatch("[^/]+") do
        current = current .. "/" .. part
        local stat = nixio_fs.stat(current)
        if stat then
            if stat.type ~= "dir" then
                return false
            end
        elseif not nixio_fs.mkdir(current) then
            return false
        end
    end
    return true
end

local function build_quick_access(preferences)
    local nixio_fs = require "nixio.fs"
    local i18n = require "luci.i18n"
    local home_dir = normalize_home_dir(preferences and preferences.home_dir)
    local quick_access = {}

    mkdir_p(home_dir)
    for _, item in ipairs(common_directory_entries) do
        local path = normalize_path(join_path(home_dir, item.path_name))
        if path then
            mkdir_p(path)
            table.insert(quick_access, {
                name = i18n.translate(item.name),
                path = path,
                icon = item.icon,
                exists = nixio_fs.stat(path) ~= nil
            })
        end
    end

    return quick_access
end

local function normalize_port_number(value, default_value)
    local number = tonumber(value)
    if not number then
        return default_value
    end
    number = math.floor(number)
    if number < 1 or number > 65535 then
        return default_value
    end
    return number
end

local function to_boolean(value)
    local text = tostring(value or ""):lower()
    return text == "1" or text == "true" or text == "yes" or text == "on"
end

local function ensure_preference_section()
    local uci = require("luci.model.uci").cursor()
    if uci:get("harbor_file", "main") == nil then
        uci:section("harbor_file", "settings", "main", {})
    end
end

local function read_preference_value(option)
    local uci = require("luci.model.uci").cursor()
    local ok, value = pcall(function()
        return uci:get("harbor_file", "main", option)
    end)
    return ok and value or nil
end

local function read_preferences()
    return {
        view_mode = normalize_preference_number(
            read_preference_value("view_mode"),
            preference_defaults.view_mode,
            valid_view_mode_values
        ),
        allow_system_operations = normalize_preference_number(
            read_preference_value("allow_system_operations"),
            preference_defaults.allow_system_operations,
            valid_boolean_values
        ),
        show_hidden_files = normalize_preference_number(
            read_preference_value("show_hidden_files"),
            preference_defaults.show_hidden_files,
            valid_boolean_values
        ),
        home_dir = normalize_home_dir(read_preference_value("home_dir")),
        enable_thumbnails = normalize_preference_number(
            read_preference_value("enable_thumbnails"),
            preference_defaults.enable_thumbnails,
            valid_boolean_values
        )
    }
end

local function save_preferences(view_mode, allow_system_operations, show_hidden_files, home_dir, enable_thumbnails)
    local uci = require("luci.model.uci").cursor()
    if uci:get("harbor_file", "main") == nil then
        uci:section("harbor_file", "settings", "main", {})
    end
    uci:set("harbor_file", "main", "view_mode", tostring(view_mode))
    uci:set("harbor_file", "main", "allow_system_operations", tostring(allow_system_operations))
    uci:set("harbor_file", "main", "show_hidden_files", tostring(show_hidden_files))
    uci:set("harbor_file", "main", "home_dir", normalize_home_dir(home_dir))
    uci:set("harbor_file", "main", "enable_thumbnails", tostring(enable_thumbnails))
    return uci:commit("harbor_file")
end

local function is_system_path(path)
    local normalized = normalize_path(path)
    if not normalized then
        return false
    end
    for _, root in ipairs(system_folder_roots) do
        if is_child_path(normalized, root) then
            return true
        end
    end
    return false
end

local function system_operations_allowed()
    return read_preferences().allow_system_operations == 1
end

local function read_ttyd_config()
    local uci = require("luci.model.uci").cursor()
    local config = nil
    pcall(function()
        uci:foreach("ttyd", "ttyd", function(section)
            config = section
            return false
        end)
    end)
    return config or {}
end

local function read_ttyd_info()
    local nixio_fs = require "nixio.fs"
    local config = read_ttyd_config()
    local executable = find_executable("ttyd")
    local init_script = nixio_fs.stat("/etc/init.d/ttyd")
    local config_file = nixio_fs.stat("/etc/config/ttyd")
    local url_override = config.url or config.path or ""
    local installed = executable ~= nil or init_script ~= nil or config_file ~= nil

    return {
        available = installed,
        port = normalize_port_number(config.port, 7681),
        ssl = to_boolean(config.ssl) and 1 or 0,
        url = type(url_override) == "string" and url_override or "",
        command = tostring(config.command or "/bin/login"),
        interface = tostring(config.interface or ""),
        installed = installed and 1 or 0
    }
end

local function deny_system_operation()
    write_json_status(403, "Forbidden", { code = 1, message = _("System folder operations are disabled") })
    return false
end

local function get_package_type(name)
    local ext = get_ext(name)
    return package_ext_map[ext] and ext or nil
end

local function classify_preview(path, name)
    local ext = get_ext(name)
    if image_mime_map[ext] then
        return "image"
    end
    if text_ext_map[ext] then
        return "text"
    end
    if video_mime_map[ext] then
        return "video"
    end
    if pdf_mime_map[ext] then
        return "pdf"
    end
    if package_ext_map[ext] then
        return "package"
    end
    if ext == "" and is_child_path(path, "/etc") then
        return "text"
    end
    return "none"
end

find_executable = function(name)
    local nixio_fs = require "nixio.fs"
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local search_paths = {}
    local seen = {}
    for entry in tostring(luci.http.getenv("PATH") or "/usr/sbin:/usr/bin:/sbin:/bin"):gmatch("[^:]+") do
        if not seen[entry] then
            table.insert(search_paths, entry)
            seen[entry] = true
        end
    end
    for _, entry in ipairs({ "/usr/sbin", "/usr/bin", "/sbin", "/bin" }) do
        if not seen[entry] then
            table.insert(search_paths, entry)
            seen[entry] = true
        end
    end
    for _, base in ipairs(search_paths) do
        local path = join_path(base, name)
        if nixio_fs.access(path, "x") then
            return path
        end
    end
    return nil
end

local function collect_thumbnail_images(path, show_hidden_files)
    local nixio_fs = require "nixio.fs"
    local normalized = normalize_path(path)
    local stat = normalized and nixio_fs.stat(normalized) or nil
    if not normalized or not stat or stat.type ~= "dir" then
        return nil, "invalid directory"
    end

    local iterator = nixio_fs.dir(normalized)
    if not iterator then
        return nil, "read directory failed"
    end

    local images = {}
    for name in iterator do
        if show_hidden_files == 1 or not is_hidden_file_name(name) then
            local item_path = normalize_path(join_path(normalized, name))
            local item_stat = item_path and nixio_fs.stat(item_path) or nil
            if item_stat and item_stat.type == "reg" and classify_preview(item_path, name) == "image" then
                table.insert(images, {
                    name = name,
                    path = item_path,
                    size = item_stat.size or 0,
                    mtime = item_stat.mtime or 0
                })
            end
        end
    end

    table.sort(images, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return images
end

local function validate_package_file(path)
    local nixio_fs = require "nixio.fs"
    local normalized = normalize_path(path)
    local stat = normalized and nixio_fs.lstat(normalized) or nil
    local package_type = normalized and get_package_type(normalized) or nil
    if not normalized or not stat or stat.type ~= "reg" or not package_type then
        return nil, nil, _("Invalid package file")
    end
    return normalized, package_type, nil
end

local function get_available_memory_kb()
    local fd = io.open("/proc/meminfo", "r")
    if not fd then
        return nil
    end
    local available, free, buffers, cached
    for line in fd:lines() do
        local key, value = line:match("^(%S+):%s*(%d+)")
        if key == "MemAvailable" then
            available = tonumber(value)
            break
        elseif key == "MemFree" then
            free = tonumber(value)
        elseif key == "Buffers" then
            buffers = tonumber(value)
        elseif key == "Cached" then
            cached = tonumber(value)
        end
    end
    fd:close()
    return available or (free and (free + (buffers or 0) + (cached or 0))) or nil
end

local function task_process_running(pid)
    local nixio_fs = require "nixio.fs"
    local number = tonumber(pid)
    if not number or number <= 0 then
        return false
    end
    return nixio_fs.stat("/proc/" .. tostring(math.floor(number))) ~= nil
end

local function read_package_install_state()
    local state = read_json_file(package_install_state_file)
    if not state then
        return nil
    end
    if (state.state == "pending" or state.state == "running") and not task_process_running(state.pid) then
        state.state = "failed"
        state.done = true
        state.success = false
        state.message = _("Install task ended unexpectedly")
        state.finished_at = state.finished_at or current_timestamp()
        state.exit_code = state.exit_code or -1
        write_json_file(package_install_state_file, state)
    end
    return state
end

local function write_package_install_state(state)
    return write_json_file(package_install_state_file, state)
end

local function build_package_install_response(state)
    return {
        task_id = state.task_id,
        state = state.state,
        done = state.done == true,
        success = state.success == true,
        message = state.message or "",
        exit_code = state.exit_code,
        package_type = state.package_type,
        installer = state.installer,
        path = state.path,
        package_name = state.package_name,
        started_at = state.started_at,
        finished_at = state.finished_at,
        log = read_log_file(package_install_log_file, package_install_log_limit)
    }
end

local function create_package_install_task(path, package_type)
    local task_id = string.format("%s-%d", tostring(math.floor(video_now_ms() or 0)), math.floor(os.time() % 100000))
    return {
        task_id = task_id,
        state = "pending",
        done = false,
        success = false,
        message = _("Preparing package install"),
        exit_code = nil,
        package_type = package_type,
        installer = package_ext_map[package_type].installer,
        path = path,
        started_at = current_timestamp(),
        finished_at = nil,
        pid = nil
    }
end

local function detect_package_installer()
    if find_executable("opkg") then
        return "opkg"
    end
    if find_executable("apk") then
        return "apk"
    end
    return nil
end

local function create_repository_install_task(package_name, installer)
    local task_id = string.format("%s-%d", tostring(math.floor(video_now_ms() or 0)), math.floor(os.time() % 100000))
    return {
        task_id = task_id,
        state = "pending",
        done = false,
        success = false,
        message = _("Preparing package install"),
        exit_code = nil,
        package_type = "repository",
        installer = installer,
        path = "",
        package_name = package_name,
        started_at = current_timestamp(),
        finished_at = nil,
        pid = nil
    }
end

local function build_package_install_command(task)
    local executable = find_executable(task.installer)
    if not executable then
        return nil, nil, _("Installer command not found")
    end
    if task.package_name and task.package_name ~= "" then
        if task.installer == "apk" then
            return executable, { "add", "--allow-untrusted", task.package_name }, nil
        end
        return executable, { "install", task.package_name }, nil
    end
    if task.package_type == "apk" then
        return executable, { "add", "--allow-untrusted", task.path }, nil
    end
    return executable, { "install", task.path }, nil
end

local function build_package_index_update_command(task)
    local executable = find_executable(task.installer)
    if not executable then
        return nil, nil, _("Installer command not found")
    end
    if task.installer == "apk" then
        return executable, { "update", "--allow-untrusted" }, nil
    end
    return executable, { "update" }, nil
end

local function command_to_shell(executable, args)
    local parts = { shell_quote(executable) }
    for _, arg in ipairs(args or {}) do
        table.insert(parts, shell_quote(arg))
    end
    return table.concat(parts, " ")
end

local function parse_execute_result(...)
    local values = { ... }
    if #values >= 3 then
        local ok = values[1]
        local how = values[2]
        local code = tonumber(values[3]) or -1
        if ok == true and how == "exit" and code == 0 then
            return 0
        end
        return code
    end
    if #values >= 1 then
        local code = values[1]
        if type(code) == "number" then
            if code > 255 then
                return math.floor(code / 256)
            end
            return code
        end
        if code == true then
            return 0
        end
    end
    return -1
end

local function run_logged_command(executable, args, log_path)
    local command = command_to_shell(executable, args) .. " >> " .. shell_quote(log_path) .. " 2>&1"
    return parse_execute_result(os.execute(command))
end

local function hex32(value)
    local number = math.floor(tonumber(value) or 0)
    local chars = "0123456789abcdef"
    local result = {}
    for index = 8, 1, -1 do
        local digit = number % 16
        result[index] = chars:sub(digit + 1, digit + 1)
        number = math.floor(number / 16)
    end
    return table.concat(result, "")
end

local function stable_hash(value)
    local text = tostring(value or "")
    local hash_a = 5381
    local hash_b = 2166136261
    for index = 1, #text do
        local byte = text:byte(index)
        hash_a = (hash_a * 33 + byte) % 4294967296
        hash_b = (hash_b * 65599 + byte) % 4294967296
    end
    return hex32(hash_a) .. hex32(hash_b)
end

local function thumbnail_cache_dir(preferences)
    local home_dir = normalize_home_dir(preferences and preferences.home_dir)
    return normalize_path(join_path(join_path(home_dir, ".cache"), "pictures"))
end

local function thumbnail_cache_key(path, stat)
    local size = stat and tonumber(stat.size) or 0
    local mtime = stat and tonumber(stat.mtime) or 0
    return stable_hash(table.concat({ normalize_path(path) or "", tostring(size), tostring(mtime), tostring(thumbnail_size), thumbnail_cache_version }, "|"))
end

local function thumbnail_cache_path(path, stat, preferences)
    local cache_dir = thumbnail_cache_dir(preferences)
    if not cache_dir then
        return nil
    end
    return join_path(cache_dir, thumbnail_cache_key(path, stat) .. ".jpg")
end

local function thumbnail_available(path, stat, preferences)
    local nixio_fs = require "nixio.fs"
    local cache_path = thumbnail_cache_path(path, stat, preferences)
    return cache_path and nixio_fs.stat(cache_path) ~= nil or false
end

local function detect_apk_package_name(path)
    local quoted_path = shell_quote(path)
    local process = io.popen("tar -xOf " .. quoted_path .. " .PKGINFO 2>/dev/null", "r")
    if process then
        local content = process:read("*a") or ""
        process:close()
        local pkgname = content:match("\npkgname%s*=%s*([^\n\r]+)") or content:match("^pkgname%s*=%s*([^\n\r]+)")
        if pkgname and pkgname ~= "" then
            return pkgname:gsub("%s+$", "")
        end
    end

    local base_name = tostring(path or ""):match("([^/]+)$") or ""
    local package_name = base_name:match("^(.+)_([^_]+)_([^_]+)%.apk$")
    if package_name and package_name ~= "" then
        return package_name
    end
    package_name = base_name:match("^(.+)%-%d[%w%.%+%-%_~]*%.apk$")
    if package_name and package_name ~= "" then
        return package_name
    end
    return base_name:gsub("%.apk$", "")
end

local function apk_package_installed(path)
    local executable = find_executable("apk")
    local package_name = detect_apk_package_name(path)
    if not executable or not package_name or package_name == "" then
        return false
    end
    local command = command_to_shell(executable, { "info", "-e", package_name }) .. " >/dev/null 2>&1"
    return parse_execute_result(os.execute(command)) == 0
end

local function has_package_index_cache(installer)
    local nixio_fs = require "nixio.fs"
    local roots = package_index_cache_roots[installer]
    if type(roots) ~= "table" then
        return false
    end

    for _, root in ipairs(roots) do
        local stat = nixio_fs.stat(root)
        if stat and stat.type == "dir" then
            local matched_groups = {}
            local iterator = nixio_fs.dir(root)
            if iterator then
                for name in iterator do
                    if name ~= "." and name ~= ".." then
                        local path = join_path(root, name)
                        local file_stat = nixio_fs.stat(path)
                        if file_stat and file_stat.type == "reg" and (file_stat.size or 0) > 0 then
                            if installer == "opkg" then
                                local lower_name = name:lower()
                                for index, aliases in ipairs(opkg_required_feed_groups) do
                                    if not matched_groups[index] then
                                        for _, alias in ipairs(aliases) do
                                            if lower_name:find(alias, 1, true) then
                                                matched_groups[index] = true
                                                break
                                            end
                                        end
                                    end
                                end
                            end
                            if installer ~= "opkg" and (name:match("^APKINDEX") or name:match("%.adb$") or name:match("%.tar%.gz$")) then
                                return true
                            end
                        end
                    end
                end
            end
            if installer == "opkg" then
                local complete = true
                for index = 1, #opkg_required_feed_groups do
                    if not matched_groups[index] then
                        complete = false
                        break
                    end
                end
                if complete then
                    return true
                end
            end
        end
    end
    return false
end

local function run_package_install_task(task)
    local nixio_fs = require "nixio.fs"
    local nixio = require "nixio"
    local executable, args, cmd_err = build_package_install_command(task)
    if not executable then
        task.state = "failed"
        task.done = true
        task.success = false
        task.message = cmd_err
        task.exit_code = -1
        task.finished_at = current_timestamp()
        write_package_install_state(task)
        return
    end

    nixio_fs.writefile(package_install_log_file, "")
    hb_log(package_install_log_file, "Start " .. task.installer .. " install: " .. (task.package_name or task.path))
    task.state = "running"
    task.message = _("Checking package index")
    task.pid = nixio.getpid()
    write_package_install_state(task)
    hb_log(package_install_log_file, "Checking package index state")
    if not has_package_index_cache(task.installer) then
        local update_executable, update_args, update_err = build_package_index_update_command(task)
        if not update_executable then
            task.state = "failed"
            task.done = true
            task.success = false
            task.message = update_err
            task.exit_code = -1
            task.finished_at = current_timestamp()
            write_package_install_state(task)
            return
        end
        hb_log(package_install_log_file, "Package index is not ready, running update")
        task.message = _("Updating package index")
        write_package_install_state(task)
        local update_exit_code = run_logged_command(update_executable, update_args, package_install_log_file)
        if update_exit_code ~= 0 then
            hb_log(package_install_log_file, "Package index update failed with code " .. tostring(update_exit_code))
            task.state = "failed"
            task.done = true
            task.success = false
            task.message = _("Package index update failed")
            task.exit_code = update_exit_code
            task.finished_at = current_timestamp()
            write_package_install_state(task)
            return
        end
        hb_log(package_install_log_file, "Package index updated successfully")
    else
        hb_log(package_install_log_file, "Package index is ready")
    end

    task.message = _("Installing package")
    write_package_install_state(task)
    local exit_code = run_logged_command(executable, args, package_install_log_file)
    local success = exit_code == 0
    local warning_success = false
    if not success and task.package_type == "apk" and apk_package_installed(task.path) then
        warning_success = true
        success = true
        hb_log(package_install_log_file, "apk reported non-zero exit code but target package is installed; treating as success with warnings")
    end
    hb_log(package_install_log_file, success and "Install finished successfully" or ("Install failed with code " .. tostring(exit_code)))

    task.state = success and "success" or "failed"
    task.done = true
    task.success = success
    task.message = success and (warning_success and _("Package installed with warnings") or _("Package installed successfully")) or _("Package installation failed")
    task.exit_code = exit_code
    task.finished_at = current_timestamp()
    write_package_install_state(task)
end

local function start_package_install_task(task)
    local nixio = require "nixio"
    local pid = nixio.fork()
    if not pid or pid < 0 then
        return nil, "fork package task failed"
    end
    if pid == 0 then
        pcall(nixio.setsid)
        local ok, err = pcall(run_package_install_task, task)
        if not ok then
            task.state = "failed"
            task.done = true
            task.success = false
            task.message = _("Package installation failed")
            task.exit_code = -1
            task.finished_at = current_timestamp()
            hb_log(package_install_log_file, "install runtime error: " .. tostring(err))
            write_package_install_state(task)
        end
        os.exit(0)
    end
    task.pid = pid
    task.state = "running"
    task.message = _("Installing package")
    write_package_install_state(task)
    return pid, nil
end

local function read_thumbnail_task_state()
    local state = read_json_file(thumbnail_task_state_file)
    if not state then
        return nil
    end
    if state.state == "running" and not task_process_running(state.pid) then
        state.state = "failed"
        state.done = true
        state.success = false
        state.message = _("Thumbnail generation ended unexpectedly")
        state.finished_at = state.finished_at or current_timestamp()
        write_json_file(thumbnail_task_state_file, state)
    elseif state.state == "pending" then
        local stale = true
        local started = state.started_at
        if started then
            local y, m, d, H, M, S = started:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
            if y then
                local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d),
                    hour = tonumber(H), min = tonumber(M), sec = tonumber(S) })
                stale = os.difftime(os.time(), t) > 30
            end
        end
        if stale then
            state.state = "failed"
            state.done = true
            state.success = false
            state.message = _("Thumbnail generation ended unexpectedly")
            state.finished_at = state.finished_at or current_timestamp()
            write_json_file(thumbnail_task_state_file, state)
        end
    end
    return state
end

local function write_thumbnail_task_state(state)
    return write_json_file(thumbnail_task_state_file, state)
end

local function build_thumbnail_task_response(state)
    return {
        task_id = state.task_id,
        state = state.state,
        done = state.done == true,
        success = state.success == true,
        message = state.message or "",
        path = state.path,
        total = tonumber(state.total) or 0,
        processed = tonumber(state.processed) or 0,
        success_count = tonumber(state.success_count) or 0,
        failed_count = tonumber(state.failed_count) or 0,
        cached_count = tonumber(state.cached_count) or 0,
        current_file = state.current_file or "",
        started_at = state.started_at,
        finished_at = state.finished_at,
        log = read_log_file(thumbnail_task_log_file, thumbnail_task_log_limit)
    }
end

local function create_thumbnail_task(path, preferences, total)
    local task_id = "thumb-" .. tostring(math.floor(video_now_ms() or 0)) .. "-" .. tostring(math.floor(os.time() % 100000))
    return {
        task_id = task_id,
        state = "pending",
        done = false,
        success = false,
        message = _("Preparing thumbnails"),
        path = path,
        home_dir = preferences.home_dir,
        show_hidden_files = preferences.show_hidden_files,
        total = total or 0,
        processed = 0,
        success_count = 0,
        failed_count = 0,
        cached_count = 0,
        current_file = "",
        pid = nil,
        started_at = current_timestamp(),
        finished_at = nil
    }
end

local function build_thumbnail_command(gm_path, source_path, target_path)
    local hint = tostring(thumbnail_size * 2) .. "x" .. tostring(thumbnail_size * 2)
    local gm_args = {
        "convert",
        "-size", hint,
        source_path,
        "-auto-orient",
        "-thumbnail",
        tostring(thumbnail_size) .. "x" .. tostring(thumbnail_size) .. ">",
        "-background",
        "white",
        "-flatten",
        "+profile", "*",
        "-quality", "80",
        target_path
    }
    local nice_path = find_executable("nice")
    if nice_path then
        return nice_path, { "-n", "10", gm_path, unpack(gm_args) }
    end
    return gm_path, gm_args
end

local function run_thumbnail_task(task)
    local nixio_fs = require "nixio.fs"
    local gm_path = find_executable("gm")
    if not gm_path then
        task.state = "failed"
        task.done = true
        task.success = false
        task.message = _("GraphicsMagick command not found")
        task.finished_at = current_timestamp()
        write_thumbnail_task_state(task)
        hb_log(thumbnail_task_log_file, "gm command not found")
        return
    end

    local preferences = {
        home_dir = task.home_dir,
        show_hidden_files = task.show_hidden_files
    }
    local cache_dir = thumbnail_cache_dir(preferences)
    if not cache_dir or not mkdir_p(cache_dir) then
        task.state = "failed"
        task.done = true
        task.success = false
        task.message = _("Thumbnail cache directory is not writable")
        task.finished_at = current_timestamp()
        write_thumbnail_task_state(task)
        hb_log(thumbnail_task_log_file, "cache directory is not writable")
        return
    end

    local images, err = collect_thumbnail_images(task.path, task.show_hidden_files)
    if not images then
        task.state = "failed"
        task.done = true
        task.success = false
        task.message = err or _("Thumbnail generation failed")
        task.finished_at = current_timestamp()
        write_thumbnail_task_state(task)
        hb_log(thumbnail_task_log_file, task.message)
        return
    end

    task.state = "running"
    task.message = _("Generating thumbnails")
    task.total = #images
    write_thumbnail_task_state(task)
    hb_log(thumbnail_task_log_file, "Start thumbnail generation: " .. task.path)

    for _, item in ipairs(images) do
        local stat = nixio_fs.stat(item.path)
        local cp = stat and thumbnail_cache_path(item.path, stat, preferences) or nil
        item.has_cache = cp and nixio_fs.stat(cp) ~= nil or false
    end
    table.sort(images, function(a, b)
        if a.has_cache ~= b.has_cache then
            return not a.has_cache
        end
        return (a.size or 0) < (b.size or 0)
    end)

    for _, item in ipairs(images) do
        task.current_file = item.name
        write_thumbnail_task_state(task)

        local stat = nixio_fs.stat(item.path)
        local cache_path = stat and thumbnail_cache_path(item.path, stat, preferences) or nil
        if cache_path and nixio_fs.stat(cache_path) then
            task.cached_count = task.cached_count + 1
            hb_log(thumbnail_task_log_file, "Cached: " .. item.name)
        elseif cache_path then
            local temp_path = cache_path .. ".tmp." .. task.task_id
            os.remove(temp_path)
            local executable, args = build_thumbnail_command(gm_path, item.path, temp_path)
            local exit_code = run_logged_command(executable, args, thumbnail_task_log_file)
            if exit_code == 0 and nixio_fs.stat(temp_path) and os.rename(temp_path, cache_path) then
                task.success_count = task.success_count + 1
                hb_log(thumbnail_task_log_file, "Generated: " .. item.name)
            else
                os.remove(temp_path)
                task.failed_count = task.failed_count + 1
                hb_log(thumbnail_task_log_file, "Failed: " .. item.name .. " code=" .. tostring(exit_code))
            end
        else
            task.failed_count = task.failed_count + 1
            hb_log(thumbnail_task_log_file, "Failed: " .. item.name .. " cache path unavailable")
        end

        task.processed = task.processed + 1
        write_thumbnail_task_state(task)
    end

    task.done = true
    task.success = task.failed_count == 0
    task.state = task.success and "success" or "failed"
    task.message = task.success and _("Thumbnail generation complete") or _("Thumbnail generation failed")
    task.current_file = ""
    task.finished_at = current_timestamp()
    write_thumbnail_task_state(task)
    hb_log(thumbnail_task_log_file, task.message)
end

local function start_thumbnail_task(task)
    local nixio = require "nixio"
    local pid = nixio.fork()
    if not pid or pid < 0 then
        return nil, "fork thumbnail task failed"
    end
    if pid == 0 then
        pcall(nixio.setsid)
        task.pid = nixio.getpid()
        task.state = "running"
        task.message = _("Generating thumbnails")
        write_thumbnail_task_state(task)
        local ok, err = pcall(run_thumbnail_task, task)
        if not ok then
            task.state = "failed"
            task.done = true
            task.success = false
            task.message = _("Thumbnail generation failed")
            task.finished_at = current_timestamp()
            hb_log(thumbnail_task_log_file, "thumbnail runtime error: " .. tostring(err))
            write_thumbnail_task_state(task)
        end
        os.exit(0)
    end
    return pid, nil
end

local function parse_size(value)
    if not value or not tostring(value):match("^%d+$") then
        return nil
    end
    local size = tonumber(value)
    if not size or size < 0 then
        return nil
    end
    return math.floor(size)
end

local function parse_binary_number(value, default_value)
    if value == nil or value == "" then
        return default_value
    end
    local text = tostring(value):lower()
    local number
    if text:match("^0x[%da-f]+$") then
        number = tonumber(text:sub(3), 16)
    elseif text:match("^%d+$") then
        number = tonumber(text)
    else
        return nil
    end
    if not number or number < 0 then
        return nil
    end
    return math.floor(number)
end

local function validate_upload_name(name)
    if type(name) ~= "string" or name == "" or name == "." or name == ".." then
        return false
    end
    if name:find("[\\/]") or name:find("[%z\1-\31\127]") then
        return false
    end
    return true
end

local function validate_write_request()
    if luci.http.getenv("REQUEST_METHOD") ~= "POST" then
        write_json_status(400, "Bad Request", { code = 1, message = "POST required" })
        return false
    end
    return true
end

local function get_writable_directory(path)
    local nixio_fs = require "nixio.fs"
    local normalized = normalize_path(path)
    local stat = normalized and nixio_fs.stat(normalized) or nil
    if not normalized or not stat or stat.type ~= "dir" then
        return nil, "directory not found"
    end
    if not nixio_fs.access(normalized, "w") then
        return nil, "directory is not writable"
    end
    return normalized
end

local function get_directory_available_bytes(path)
    local nixio_fs = require "nixio.fs"
    local normalized = normalize_path(path)
    if not normalized then
        return nil, "invalid directory"
    end
    local vfs = nixio_fs.statvfs(normalized)
    if not vfs then
        return nil, "read filesystem space failed"
    end
    return (tonumber(vfs.bavail) or 0) * (tonumber(vfs.frsize) or 0)
end

local function ensure_directory_space(path, required_bytes)
    local available, err = get_directory_available_bytes(path)
    if not available then
        return false, 0, err
    end
    local required = (tonumber(required_bytes) or 0) + operation_space_margin
    if available < required then
        return false, available, insufficient_space_message, required
    end
    return true, available, nil, required
end

local function read_mount_paths()
    local mounts = {}
    local fd = io.open("/proc/self/mounts", "r") or io.open("/proc/mounts", "r")
    if not fd then
        return mounts
    end
    for line in fd:lines() do
        local path = line:match("^%S+%s+(%S+)")
        if path then
            path = path:gsub("\\(%d%d%d)", function(value)
                return string.char(tonumber(value, 8))
            end)
            mounts[path] = true
        end
    end
    fd:close()
    return mounts
end

local function contains_mount(path, mounts)
    for mount_path in pairs(mounts) do
        if mount_path == path or is_child_path(mount_path, path) then
            return true
        end
    end
    return false
end

local function remove_tree(path)
    local nixio_fs = require "nixio.fs"
    local stat = nixio_fs.lstat(path)
    if not stat then
        return false, "path not found"
    end
    if stat.type ~= "dir" then
        return nixio_fs.unlink(path) and true or false, "delete file failed"
    end

    local iterator = nixio_fs.dir(path)
    if not iterator then
        return false, "read directory failed"
    end
    for name in iterator do
        local ok, err = remove_tree(join_path(path, name))
        if not ok then
            return false, err
        end
    end
    return nixio_fs.rmdir(path) and true or false, "delete directory failed"
end

local function copy_regular_file(source, target)
    local nixio_fs = require "nixio.fs"
    local input = io.open(source, "rb")
    if not input then
        return false, "open source file failed"
    end
    local output = io.open(target, "wb")
    if not output then
        input:close()
        return false, "create target file failed"
    end
    while true do
        local data = input:read(65536)
        if not data or #data == 0 then
            break
        end
        if not output:write(data) then
            input:close()
            output:close()
            nixio_fs.unlink(target)
            return false, "write target file failed"
        end
    end
    input:close()
    output:close()
    return true
end

local function copy_tree(source, target)
    local nixio_fs = require "nixio.fs"
    local stat = nixio_fs.lstat(source)
    if not stat then
        return false, "source not found"
    end
    if stat.type == "lnk" then
        local link_target = nixio_fs.readlink(source)
        return link_target and nixio_fs.symlink(link_target, target) and true or false, "copy symbolic link failed"
    end
    if stat.type == "reg" then
        return copy_regular_file(source, target)
    end
    if stat.type ~= "dir" then
        return false, "unsupported source type"
    end
    if not nixio_fs.mkdir(target) then
        return false, "create target directory failed"
    end
    local iterator = nixio_fs.dir(source)
    if not iterator then
        nixio_fs.rmdir(target)
        return false, "read source directory failed"
    end
    for name in iterator do
        local ok, err = copy_tree(join_path(source, name), join_path(target, name))
        if not ok then
            remove_tree(target)
            return false, err
        end
    end
    return true
end

local function get_upload_directory(path)
    local nixio_fs = require "nixio.fs"
    local normalized = normalize_path(path)
    if not normalized then
        return nil, nil, "invalid target directory"
    end

    local stat = nixio_fs.stat(normalized)
    if not stat or stat.type ~= "dir" then
        return nil, nil, "target directory not found"
    end
    if not nixio_fs.access(normalized, "w") then
        return nil, nil, "target directory is not writable"
    end

    local available, space_err = get_directory_available_bytes(normalized)
    if not available then
        return nil, nil, space_err
    end
    return normalized, available
end

local function parse_upload_names(value)
    local json = require "luci.jsonc"
    local ok, names = pcall(json.parse, value or "")
    if not ok or type(names) ~= "table" or #names == 0 then
        return nil, "invalid file list"
    end

    local result = {}
    local seen = {}
    for _, name in ipairs(names) do
        if not validate_upload_name(name) then
            return nil, "invalid file name"
        end
        if seen[name] then
            return nil, "duplicate file name in upload batch"
        end
        seen[name] = true
        table.insert(result, name)
    end
    return result
end

is_hidden_file_name = function(name)
    return type(name) == "string" and name:sub(1, 1) == "."
end

local function list_directory(path, preferences)
    local nixio_fs = require "nixio.fs"
    preferences = preferences or read_preferences()
    local show_hidden_files = preferences.show_hidden_files
    local stat = nixio_fs.stat(path)
    if not stat then
        return nil, "path not found"
    end
    if stat.type ~= "dir" then
        return nil, "path is not directory"
    end

    local iterator = nixio_fs.dir(path)
    if not iterator then
        return nil, "read directory failed"
    end

    local items = {}
    for name in iterator do
        if show_hidden_files == 1 or not is_hidden_file_name(name) then
            local item_path = normalize_path(join_path(path, name))
            local item_stat = item_path and nixio_fs.stat(item_path) or nil
            if item_stat then
                local item_type = item_stat.type == "dir" and "directory" or "file"
                local preview = item_type == "file" and classify_preview(item_path, name) or "none"
                local item = {
                    name = name,
                    path = item_path,
                    type = item_type,
                    size = item_stat.size or 0,
                    mtime = item_stat.mtime or 0,
                    ext = get_ext(name),
                    preview = preview
                }
                if preferences.enable_thumbnails == 1 and preview == "image" then
                    item.thumbnail_available = thumbnail_available(item_path, item_stat, preferences)
                end
                table.insert(items, item)
            end
        end
    end

    table.sort(items, function(a, b)
        if a.type ~= b.type then
            return a.type == "directory"
        end
        return a.name:lower() < b.name:lower()
    end)

    return items
end

local function list_root_folders()
    local preferences = read_preferences()
    preferences.enable_thumbnails = 0
    local items, err = list_directory("/", preferences)
    if not items then
        return {}, err
    end

    local folders = {}
    for _, item in ipairs(items) do
        if item.type == "directory" then
            table.insert(folders, item)
        end
    end
    return folders
end

local function drive_name(device, mount_point)
    local i18n = require "luci.i18n"
    if mount_point == "/" then
        return "System Disk"
    end
    if mount_point == "/tmp" then
        return i18n.translate("Temporary Space")
    end

    local name = device:match("([^/]+)$")
    return name and name ~= "" and name or device
end

local function list_drives()
    local drives = {}
    local seen_mount = {}
    local seen_drive = {}
    local process = io.popen("df -kP 2>/dev/null", "r")

    if process then
        process:read("*l")
        for line in process:lines() do
            local device, total, used, available, percent, mount_point =
                line:match("^(%S+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%%%s+(.+)$")

            local is_root = mount_point == "/"
            local is_temporary_space = mount_point == "/tmp"
            local is_device = device and device:match("^/dev/") ~= nil
            local name = drive_name(device, mount_point)
            local drive_key = (name and name ~= "" and name or device or mount_point or ""):lower()

            if mount_point and not seen_mount[mount_point] and not hidden_mounts[mount_point] and (is_root or is_temporary_space or is_device) then
                seen_mount[mount_point] = true
                if not seen_drive[drive_key] then
                    seen_drive[drive_key] = true
                    table.insert(drives, {
                        name = name,
                        device = device,
                        path = mount_point,
                        total_kb = tonumber(total) or 0,
                        used_kb = tonumber(used) or 0,
                        available_kb = tonumber(available) or 0,
                        usage_percent = tonumber(percent) or 0
                    })
                end
            end
        end
        process:close()
    end

    if not seen_mount["/"] then
        table.insert(drives, 1, {
            name = "System Disk",
            device = "rootfs",
            path = "/",
            total_kb = 0,
            used_kb = 0,
            available_kb = 0,
            usage_percent = 0
        })
    end

    table.sort(drives, function(a, b)
        if a.path == "/" then
            return true
        end
        if b.path == "/" then
            return false
        end
        return a.path:lower() < b.path:lower()
    end)
    return drives
end

function api_navigation()
    local preferences = read_preferences()
    local quick_access = build_quick_access(preferences)
    local folders = list_root_folders()
    write_json({
        code = 0,
        message = "success",
        data = {
            quick_access = quick_access,
            home_dir = preferences.home_dir,
            folders = folders,
            drives = list_drives()
        }
    })
end

function api_preferences()
    write_json({
        code = 0,
        message = "success",
        data = read_preferences()
    })
end

function api_terminal_info()
    local info = read_ttyd_info()
    write_json({
        code = 0,
        message = "success",
        data = info
    })
end

function api_save_preferences()
    if not validate_write_request() then
        return
    end

    local view_mode = normalize_preference_number(
        luci.http.formvalue("view_mode"),
        preference_defaults.view_mode,
        valid_view_mode_values
    )
    local allow_system_operations = normalize_preference_number(
        luci.http.formvalue("allow_system_operations"),
        preference_defaults.allow_system_operations,
        valid_boolean_values
    )
    local show_hidden_files = normalize_preference_number(
        luci.http.formvalue("show_hidden_files"),
        preference_defaults.show_hidden_files,
        valid_boolean_values
    )
    local enable_thumbnails = normalize_preference_number(
        luci.http.formvalue("enable_thumbnails"),
        preference_defaults.enable_thumbnails,
        valid_boolean_values
    )
    local home_dir = normalize_home_dir(luci.http.formvalue("home_dir"))

    if not save_preferences(view_mode, allow_system_operations, show_hidden_files, home_dir, enable_thumbnails) then
        write_json_status(500, "Save Failed", { code = 1, message = "save preferences failed" })
        return
    end
    build_quick_access({ home_dir = home_dir })

    write_json({
        code = 0,
        message = "success",
        data = {
            view_mode = view_mode,
            allow_system_operations = allow_system_operations,
            show_hidden_files = show_hidden_files,
            home_dir = home_dir,
            enable_thumbnails = enable_thumbnails
        }
    })
end

function api_list()
    local path = normalize_path(luci.http.formvalue("path"))
    if not path then
        write_json({ code = 1, message = "invalid path" })
        return
    end

    local preferences = read_preferences()
    local items, err = list_directory(path, preferences)
    if not items then
        write_json({ code = 2, message = err or "list failed" })
        return
    end
    local available = get_directory_available_bytes(path) or 0

    write_json({
        code = 0,
        message = "success",
        data = {
            path = path,
            parent = parent_path(path),
            available_bytes = available,
            operation_space_margin = operation_space_margin,
            has_operation_space = available >= operation_space_margin,
            items = items
        }
    })
end

function api_create_directory()
    local nixio_fs = require "nixio.fs"
    if not validate_write_request() then
        return
    end
    local target_dir, err = get_writable_directory(luci.http.formvalue("target_dir"))
    local name = luci.http.formvalue("name")
    if not target_dir or not validate_upload_name(name) then
        write_json_status(400, "Bad Request", { code = 1, message = err or "invalid directory name" })
        return
    end
    if not system_operations_allowed() and is_system_path(target_dir) then
        return deny_system_operation()
    end
    local has_space, available, space_err = ensure_directory_space(target_dir, 0)
    if not has_space then
        write_json_status(507, "Insufficient Storage", {
            code = 2,
            message = space_err or insufficient_space_message,
            data = { available_bytes = available, required_bytes = operation_space_margin }
        })
        return
    end

    local path = join_path(target_dir, name)
    if nixio_fs.lstat(path) then
        write_json_status(409, "Conflict", { code = 1, message = "target already exists" })
        return
    end
    if not nixio_fs.mkdir(path) then
        write_json_status(500, "Create Failed", { code = 1, message = "create directory failed" })
        return
    end
    write_json({ code = 0, message = "success", data = { path = path } })
end

function api_create_file()
    local nixio_fs = require "nixio.fs"
    if not validate_write_request() then
        return
    end
    local target_dir, err = get_writable_directory(luci.http.formvalue("target_dir"))
    local name = luci.http.formvalue("name")
    if not target_dir or not validate_upload_name(name) then
        write_json_status(400, "Bad Request", { code = 1, message = err or "invalid file name" })
        return
    end
    if not system_operations_allowed() and is_system_path(target_dir) then
        return deny_system_operation()
    end
    local has_space, available, space_err = ensure_directory_space(target_dir, 0)
    if not has_space then
        write_json_status(507, "Insufficient Storage", {
            code = 2,
            message = space_err or insufficient_space_message,
            data = { available_bytes = available, required_bytes = operation_space_margin }
        })
        return
    end

    local path = join_path(target_dir, name)
    if nixio_fs.lstat(path) then
        write_json_status(409, "Conflict", { code = 1, message = "target already exists" })
        return
    end

    local fd, open_err = io.open(path, "wb")
    if not fd then
        write_json_status(500, "Create Failed", { code = 1, message = open_err or "create file failed" })
        return
    end
    fd:close()
    write_json({ code = 0, message = "success", data = { path = path } })
end

function api_rename()
    local nixio_fs = require "nixio.fs"
    if not validate_write_request() then
        return
    end
    local path = normalize_path(luci.http.formvalue("path"))
    local new_name = luci.http.formvalue("new_name")
    local stat = path and path ~= "/" and nixio_fs.lstat(path) or nil
    if not stat or not validate_upload_name(new_name) then
        write_json_status(400, "Bad Request", { code = 1, message = "invalid path or name" })
        return
    end
    if not system_operations_allowed() and is_system_path(path) then
        return deny_system_operation()
    end

    local parent, err = get_writable_directory(parent_path(path))
    if not parent then
        write_json_status(403, "Forbidden", { code = 1, message = err })
        return
    end
    local has_space, available, space_err, required = ensure_directory_space(parent, 0)
    if not has_space then
        write_json_status(507, "Insufficient Storage", {
            code = 2,
            message = space_err or insufficient_space_message,
            data = { available_bytes = available, required_bytes = required or operation_space_margin }
        })
        return
    end
    if stat.type == "dir" and contains_mount(path, read_mount_paths()) then
        write_json_status(409, "Conflict", { code = 1, message = "directory contains a mount point" })
        return
    end
    local target = join_path(parent, new_name)
    if target ~= path and nixio_fs.lstat(target) then
        write_json_status(409, "Conflict", { code = 1, message = "target already exists" })
        return
    end
    if target ~= path and not os.rename(path, target) then
        write_json_status(500, "Rename Failed", { code = 1, message = "rename failed" })
        return
    end
    write_json({ code = 0, message = "success", data = { path = target } })
end

function api_delete()
    local nixio_fs = require "nixio.fs"
    if not validate_write_request() then
        return
    end
    local path = normalize_path(luci.http.formvalue("path"))
    local stat = path and path ~= "/" and nixio_fs.lstat(path) or nil
    if not stat then
        write_json_status(400, "Bad Request", { code = 1, message = "invalid path" })
        return
    end
    if not system_operations_allowed() and is_system_path(path) then
        return deny_system_operation()
    end

    local parent, err = get_writable_directory(parent_path(path))
    if not parent then
        write_json_status(403, "Forbidden", { code = 1, message = err })
        return
    end
    if stat.type == "dir" and contains_mount(path, read_mount_paths()) then
        write_json_status(409, "Conflict", { code = 1, message = "directory contains a mount point" })
        return
    end
    local ok, remove_err = remove_tree(path)
    if not ok then
        write_json_status(500, "Delete Failed", { code = 1, message = remove_err })
        return
    end
    write_json({ code = 0, message = "success", data = {} })
end

local function transfer_path(mode)
    local nixio_fs = require "nixio.fs"
    if not validate_write_request() then
        return
    end
    local source = normalize_path(luci.http.formvalue("source"))
    local target_dir, target_err = get_writable_directory(luci.http.formvalue("target_dir"))
    local source_stat = source and source ~= "/" and nixio_fs.lstat(source) or nil
    if not source_stat or not target_dir then
        write_json_status(400, "Bad Request", { code = 1, message = target_err or "invalid source path" })
        return
    end
    if not system_operations_allowed() then
        if is_system_path(target_dir) then
            return deny_system_operation()
        end
        if mode == "move" and is_system_path(source) then
            return deny_system_operation()
        end
    end
    if source_stat.type ~= "reg" and source_stat.type ~= "dir" and source_stat.type ~= "lnk" then
        write_json_status(400, "Bad Request", { code = 1, message = "unsupported source type" })
        return
    end
    if source_stat.type == "dir" and (is_child_path(target_dir, source) or contains_mount(source, read_mount_paths())) then
        write_json_status(409, "Conflict", { code = 1, message = "invalid target directory or mounted source" })
        return
    end

    local name = source:match("([^/]+)$")
    local target = join_path(target_dir, name)
    if target == source or nixio_fs.lstat(target) then
        write_json_status(409, "Conflict", { code = 1, message = "target already exists" })
        return
    end
    if mode == "move" and not nixio_fs.access(parent_path(source), "w") then
        write_json_status(403, "Forbidden", { code = 1, message = "source directory is not writable" })
        return
    end

    local ok
    local err
    if mode == "move" and os.rename(source, target) then
        ok = true
    else
        local required_size = source_stat.type == "reg" and (tonumber(source_stat.size) or 0) or 0
        local has_space, available, space_err, required = ensure_directory_space(target_dir, required_size)
        if not has_space then
            write_json_status(507, "Insufficient Storage", {
                code = 2,
                message = space_err or insufficient_space_message,
                data = { available_bytes = available, required_bytes = required or operation_space_margin }
            })
            return
        end
        ok, err = copy_tree(source, target)
        if ok and mode == "move" then
            ok, err = remove_tree(source)
            if not ok then
                remove_tree(target)
            end
        end
    end
    if not ok then
        remove_tree(target)
        write_json_status(500, "Transfer Failed", { code = 1, message = err or "file operation failed" })
        return
    end
    write_json({ code = 0, message = "success", data = { path = target } })
end

local function parse_path_array_param(name)
    local jsonc = require "luci.jsonc"
    local ok, values = pcall(jsonc.parse, luci.http.formvalue(name) or "")
    if not ok or type(values) ~= "table" or #values == 0 then
        return nil, "invalid path list"
    end
    return values
end

local function validate_batch_sources(paths, mode, target_dir)
    local nixio_fs = require "nixio.fs"
    local seen_paths = {}
    local seen_names = {}
    local items = {}
    local mounts = read_mount_paths()
    for _, raw_path in ipairs(paths or {}) do
        local path = normalize_path(raw_path)
        local stat = path and path ~= "/" and nixio_fs.lstat(path) or nil
        if not stat then
            return nil, raw_path, "invalid source path"
        end
        if seen_paths[path] then
            return nil, path, "duplicate source path"
        end
        if stat.type ~= "reg" and stat.type ~= "dir" and stat.type ~= "lnk" then
            return nil, path, "unsupported source type"
        end
        if not system_operations_allowed() and (mode == "move" or mode == "delete") and is_system_path(path) then
            return nil, path, _("System folder operations are disabled")
        end
        if stat.type == "dir" and contains_mount(path, mounts) then
            return nil, path, "directory contains a mount point"
        end
        if target_dir and stat.type == "dir" and is_child_path(target_dir, path) then
            return nil, path, "invalid target directory"
        end
        local name = path:match("([^/]+)$")
        if not name or name == "" then
            return nil, path, "invalid source path"
        end
        if target_dir and seen_names[name] then
            return nil, path, "duplicate target name"
        end
        seen_paths[path] = true
        seen_names[name] = true
        table.insert(items, { path = path, stat = stat, name = name })
    end
    return items
end

local function transfer_one(mode, item, target_dir)
    local nixio_fs = require "nixio.fs"
    local source = item.path
    local target = join_path(target_dir, item.name)
    if target == source or nixio_fs.lstat(target) then
        return false, "target already exists"
    end
    if mode == "move" and not nixio_fs.access(parent_path(source), "w") then
        return false, "source directory is not writable"
    end
    if mode == "move" and os.rename(source, target) then
        return true
    end
    local ok, err = copy_tree(source, target)
    if ok and mode == "move" then
        ok, err = remove_tree(source)
        if not ok then
            remove_tree(target)
        end
    end
    if not ok then
        remove_tree(target)
    end
    return ok, err
end

local function write_batch_failure(status, reason, message, processed, success_count, failed_path)
    write_json_status(status, reason, {
        code = 1,
        message = message or "batch operation failed",
        data = {
            processed = processed or 0,
            success_count = success_count or 0,
            failed_path = failed_path or ""
        }
    })
end

local function batch_transfer_path(mode)
    if not validate_write_request() then
        return
    end
    local paths, parse_err = parse_path_array_param("sources")
    if not paths then
        write_json_status(400, "Bad Request", { code = 1, message = parse_err })
        return
    end
    local target_dir, target_err = get_writable_directory(luci.http.formvalue("target_dir"))
    if not target_dir then
        write_json_status(400, "Bad Request", { code = 1, message = target_err or "invalid target directory" })
        return
    end
    if not system_operations_allowed() and is_system_path(target_dir) then
        return deny_system_operation()
    end

    local items, failed_path, err = validate_batch_sources(paths, mode, target_dir)
    if not items then
        write_batch_failure(409, "Conflict", err, 0, 0, failed_path)
        return
    end

    local required_size = 0
    for _, item in ipairs(items) do
        if item.stat.type == "reg" then
            required_size = required_size + (tonumber(item.stat.size) or 0)
        end
    end
    local has_space, available, space_err, required = ensure_directory_space(target_dir, required_size)
    if not has_space then
        write_json_status(507, "Insufficient Storage", {
            code = 2,
            message = space_err or insufficient_space_message,
            data = { available_bytes = available, required_bytes = required or (required_size + operation_space_margin) }
        })
        return
    end

    local success_count = 0
    for index, item in ipairs(items) do
        local ok, op_err = transfer_one(mode, item, target_dir)
        if not ok then
            write_batch_failure(500, "Transfer Failed", op_err, index - 1, success_count, item.path)
            return
        end
        success_count = success_count + 1
    end
    write_json({ code = 0, message = "success", data = { processed = #items, success_count = success_count } })
end

local function batch_delete_paths()
    if not validate_write_request() then
        return
    end
    local paths, parse_err = parse_path_array_param("paths")
    if not paths then
        write_json_status(400, "Bad Request", { code = 1, message = parse_err })
        return
    end
    local items, failed_path, err = validate_batch_sources(paths, "delete")
    if not items then
        write_batch_failure(409, "Conflict", err, 0, 0, failed_path)
        return
    end

    local success_count = 0
    for index, item in ipairs(items) do
        local parent, parent_err = get_writable_directory(parent_path(item.path))
        if not parent then
            write_batch_failure(403, "Forbidden", parent_err, index - 1, success_count, item.path)
            return
        end
        local ok, remove_err = remove_tree(item.path)
        if not ok then
            write_batch_failure(500, "Delete Failed", remove_err, index - 1, success_count, item.path)
            return
        end
        success_count = success_count + 1
    end
    write_json({ code = 0, message = "success", data = { processed = #items, success_count = success_count } })
end

function api_copy()
    transfer_path("copy")
end

function api_move()
    transfer_path("move")
end

function api_batch_copy()
    batch_transfer_path("copy")
end

function api_batch_move()
    batch_transfer_path("move")
end

function api_batch_delete()
    batch_delete_paths()
end

function api_package_install_start()
    local nixio_fs = require "nixio.fs"
    if not validate_write_request() then
        return
    end

    local current = read_package_install_state()
    if current and (current.state == "pending" or current.state == "running") and not current.done then
        write_json_status(409, "Conflict", {
            code = 1,
            message = _("Another package installation is already running"),
            data = build_package_install_response(current)
        })
        return
    end

    local path, package_type, err = validate_package_file(luci.http.formvalue("path"))
    if not path then
        write_json_status(400, "Bad Request", { code = 1, message = err })
        return
    end

    local executable, _, cmd_err = build_package_install_command({
        installer = package_ext_map[package_type].installer,
        package_type = package_type,
        path = path
    })
    if not executable then
        write_json_status(500, "Install Failed", { code = 1, message = cmd_err })
        return
    end

    local task = create_package_install_task(path, package_type)
    nixio_fs.writefile(package_install_log_file, "")
    if not write_package_install_state(task) then
        write_json_status(500, "Install Failed", { code = 1, message = _("Package installation failed") })
        return
    end

    local pid, start_err = start_package_install_task(task)
    if not pid then
        task.state = "failed"
        task.done = true
        task.success = false
        task.message = _("Package installation failed")
        task.exit_code = -1
        task.finished_at = current_timestamp()
        write_package_install_state(task)
        write_json_status(500, "Install Failed", { code = 1, message = start_err or _("Package installation failed") })
        return
    end

    task.pid = pid
    write_json({
        code = 0,
        message = "success",
        data = build_package_install_response(task)
    })
end

function api_package_install_status()
    local task_id = luci.http.formvalue("task_id")
    if type(task_id) ~= "string" or task_id == "" then
        write_json_status(400, "Bad Request", { code = 1, message = _("Invalid task id") })
        return
    end

    local task = read_package_install_state()
    if not task or task.task_id ~= task_id then
        write_json_status(404, "Not Found", { code = 1, message = _("Package install task not found") })
        return
    end

    write_json({
        code = 0,
        message = "success",
        data = build_package_install_response(task)
    })
end

function api_thumbnail_generate_start()
    local nixio_fs = require "nixio.fs"
    if luci.http.getenv("REQUEST_METHOD") ~= "POST" then
        write_json_status(400, "Bad Request", { code = 1, message = "POST required" })
        return
    end

    local uname_fd = io.popen("uname -m")
    if uname_fd then
        local arch = uname_fd:read("*l") or ""
        uname_fd:close()
        if arch:lower():find("mips") then
            write_json_status(501, "Not Supported", {
                code = 4,
                message = _("This device does not support thumbnail generation"),
                data = { arch = arch }
            })
            return
        end
    end

    local current = read_thumbnail_task_state()
    if current and not current.done then
        write_json_status(409, "Conflict", {
            code = 1,
            message = _("Another thumbnail generation task is already running"),
            data = build_thumbnail_task_response(current)
        })
        return
    end

    local gm_path = find_executable("gm")
    if not gm_path then
        write_json_status(424, "Dependency Required", {
            code = 2,
            message = _("GraphicsMagick command not found"),
            data = {
                missing_tool = "gm",
                package_name = "graphicsmagick",
                installer = detect_package_installer()
            }
        })
        return
    end

    local mem_kb = get_available_memory_kb()
    if mem_kb and mem_kb < thumbnail_memory_margin then
        write_json_status(507, "Insufficient Memory", {
            code = 3,
            message = _("Insufficient memory for thumbnail generation"),
            data = { available_kb = mem_kb, required_kb = thumbnail_memory_margin }
        })
        return
    end

    local path = normalize_path(luci.http.formvalue("path"))
    local stat = path and nixio_fs.stat(path) or nil
    if not path or not stat or stat.type ~= "dir" then
        write_json_status(400, "Bad Request", { code = 1, message = "invalid directory" })
        return
    end

    local preferences = read_preferences()
    local images, err = collect_thumbnail_images(path, preferences.show_hidden_files)
    if not images then
        write_json_status(400, "Bad Request", { code = 1, message = err or "read directory failed" })
        return
    end
    if #images == 0 then
        write_json_status(400, "Bad Request", { code = 1, message = _("No image files found") })
        return
    end

    local cache_dir = thumbnail_cache_dir(preferences)
    if not cache_dir or not mkdir_p(cache_dir) or not nixio_fs.access(cache_dir, "w") then
        write_json_status(403, "Forbidden", { code = 1, message = _("Thumbnail cache directory is not writable") })
        return
    end

    local task = create_thumbnail_task(path, preferences, #images)
    nixio_fs.writefile(thumbnail_task_log_file, "")
    if not write_thumbnail_task_state(task) then
        write_json_status(500, "Thumbnail Failed", { code = 1, message = _("Thumbnail generation failed") })
        return
    end

    local pid, fork_err = start_thumbnail_task(task)
    if not pid then
        task.state = "failed"
        task.done = true
        task.success = false
        task.message = _("Thumbnail generation failed")
        task.finished_at = current_timestamp()
        hb_log(thumbnail_task_log_file, "fork failed: " .. tostring(fork_err))
        write_thumbnail_task_state(task)
        write_json_status(500, "Thumbnail Failed", { code = 1, message = task.message })
        return
    end

    write_json({ code = 0, message = "success", data = build_thumbnail_task_response(task) })
end

function api_thumbnail_tool_install_start()
    local nixio_fs = require "nixio.fs"
    if not validate_write_request() then
        return
    end

    if find_executable("gm") then
        local task = create_repository_install_task("graphicsmagick", detect_package_installer() or "")
        task.state = "success"
        task.done = true
        task.success = true
        task.message = _("GraphicsMagick is already installed")
        task.exit_code = 0
        task.finished_at = current_timestamp()
        nixio_fs.writefile(package_install_log_file, "GraphicsMagick is already installed\n")
        write_package_install_state(task)
        write_json({ code = 0, message = "success", data = build_package_install_response(task) })
        return
    end

    local current = read_package_install_state()
    if current and (current.state == "pending" or current.state == "running") and not current.done then
        write_json_status(409, "Conflict", {
            code = 1,
            message = _("Another package installation is already running"),
            data = build_package_install_response(current)
        })
        return
    end

    local installer = detect_package_installer()
    if not installer then
        write_json_status(500, "Install Failed", { code = 1, message = _("Installer command not found") })
        return
    end

    local task = create_repository_install_task("graphicsmagick", installer)
    nixio_fs.writefile(package_install_log_file, "")
    if not write_package_install_state(task) then
        write_json_status(500, "Install Failed", { code = 1, message = _("Package installation failed") })
        return
    end

    local pid, start_err = start_package_install_task(task)
    if not pid then
        task.state = "failed"
        task.done = true
        task.success = false
        task.message = _("Package installation failed")
        task.exit_code = -1
        task.finished_at = current_timestamp()
        write_package_install_state(task)
        write_json_status(500, "Install Failed", { code = 1, message = start_err or _("Package installation failed") })
        return
    end

    write_json({
        code = 0,
        message = "success",
        data = build_package_install_response(task)
    })
end

function api_thumbnail_generate_status()
    local task_id = luci.http.formvalue("task_id")
    if type(task_id) ~= "string" or task_id == "" then
        write_json_status(400, "Bad Request", { code = 1, message = _("Invalid task id") })
        return
    end

    local task = read_thumbnail_task_state()
    if not task or task.task_id ~= task_id then
        write_json_status(404, "Not Found", { code = 1, message = _("Thumbnail task not found") })
        return
    end

    write_json({
        code = 0,
        message = "success",
        data = build_thumbnail_task_response(task)
    })
end


local function validate_preview_file(path, expected_type)
    local nixio_fs = require "nixio.fs"
    if not path then
        return nil, "invalid path"
    end

    local stat = nixio_fs.stat(path)
    if not stat or stat.type ~= "reg" then
        return nil, "file not found"
    end

    if classify_preview(path, path) ~= expected_type then
        return nil, "file type is not supported"
    end

    return stat
end

local function validate_text_edit_file(path)
    local stat, err = validate_preview_file(path, "text")
    if not stat then
        return nil, err
    end
    if (tonumber(stat.size) or 0) > max_text_size then
        return nil, "file is too large for editing"
    end
    return stat
end

local function write_text_atomic(path, content, source_stat)
    local nixio_fs = require "nixio.fs"
    local file_name = path:match("([^/]+)$") or "text"
    local parent = parent_path(path)
    local temp_path = join_path(
        parent,
        "." .. file_name .. ".harbor_file_tmp_" ..
            tostring(math.floor(video_now_ms() or 0)) .. "_" .. tostring(math.floor(os.time() % 100000))
    )
    local fd, open_err = io.open(temp_path, "wb")
    if not fd then
        return nil, open_err or "open temporary file failed"
    end

    local ok, write_ok, write_err = pcall(fd.write, fd, content or "")
    fd:close()
    if not ok or write_ok == nil then
        nixio_fs.unlink(temp_path)
        return nil, tostring(write_err or "write temporary file failed")
    end

    local mode_text = source_stat and source_stat.modestr or nil
    if type(mode_text) == "string" and mode_text ~= "" then
        pcall(nixio_fs.chmod, temp_path, mode_text)
    end

    if not os.rename(temp_path, path) then
        nixio_fs.unlink(temp_path)
        return nil, "replace file failed"
    end

    local stat = nixio_fs.stat(path)
    if not stat or stat.type ~= "reg" then
        return nil, "verify saved file failed"
    end
    return stat
end

local function validate_download_file(path)
    local nixio_fs = require "nixio.fs"
    if not path then
        return nil, "invalid path"
    end

    local stat = nixio_fs.stat(path)
    if not stat or stat.type ~= "reg" then
        return nil, "file not found"
    end

    return stat
end

local function sanitize_download_name(name)
    local value = tostring(name or ""):gsub("[\\/\r\n\"]", "_"):gsub("[%z\1-\31\127]", "_")
    if value == "" or value == "." or value == ".." then
        return "download"
    end
    return value
end

local function encode_rfc5987(value)
    return (tostring(value or ""):gsub("([^%w%!%#%$%&%+%-%._%~])", function(ch)
        return string.format("%%%02X", string.byte(ch))
    end))
end

function api_download()
    local path = normalize_path(luci.http.formvalue("path"))
    local stat, err = validate_download_file(path)
    if not stat then
        write_plain_status(400, "Bad Request", err)
        return
    end

    local fd = io.open(path, "rb")
    if not fd then
        write_plain_status(500, "Internal Server Error", "open file failed")
        return
    end

    local file_name = path:match("([^/]+)$") or "download"
    local safe_name = sanitize_download_name(file_name)
    set_status(200, "OK")
    luci.http.header("Content-Type", "application/octet-stream")
    luci.http.header("Content-Length", tostring(stat.size or 0))
    luci.http.header("Content-Disposition",
        "attachment; filename=\"" .. safe_name .. "\"; filename*=UTF-8''" .. encode_rfc5987(file_name))
    luci.http.header("Cache-Control", "no-store")
    luci.http.header("X-Content-Type-Options", "nosniff")

    while true do
        local data = fd:read(65536)
        if not data or #data == 0 then
            break
        end
        luci.http.write(data)
    end

    fd:close()
end

function api_read_text()
    local path = normalize_path(luci.http.formvalue("path"))
    local stat, err = validate_preview_file(path, "text")
    if not stat then
        write_json({ code = 1, message = err })
        return
    end

    local fd = io.open(path, "rb")
    if not fd then
        write_json({ code = 2, message = "open file failed" })
        return
    end

    local content = fd:read(max_text_size + 1) or ""
    fd:close()
    local truncated = #content > max_text_size
    if truncated then
        content = content:sub(1, max_text_size)
    end

    write_json({
        code = 0,
        message = "success",
        data = {
            path = path,
            content = content,
            truncated = truncated,
            max_size = max_text_size,
            size = tonumber(stat.size) or 0,
            mtime = tonumber(stat.mtime) or 0
        }
    })
end

function api_read_binary()
    local nixio_fs = require "nixio.fs"
    local path = normalize_path(luci.http.formvalue("path"))
    local stat = path and nixio_fs.stat(path) or nil
    if not path or not stat or stat.type ~= "reg" then
        write_json({ code = 1, message = "file not found" })
        return
    end
    local file_size = tonumber(stat.size) or 0
    local start_offset = parse_binary_number(luci.http.formvalue("offset"), 0)
    local size_kb_value = luci.http.formvalue("size_kb")
    local read_kb
    if size_kb_value ~= nil and size_kb_value ~= "" then
        read_kb = parse_binary_number(size_kb_value, nil)
    else
        local read_size = parse_binary_number(luci.http.formvalue("size"), default_binary_read_kb * 1024)
        read_kb = read_size and math.ceil(read_size / 1024) or nil
    end
    if not start_offset or not read_kb or read_kb < 1 or read_kb > max_binary_read_kb then
        write_json({ code = 1, message = "invalid range" })
        return
    end
    local read_limit = read_kb * 1024
    if start_offset > file_size then
        start_offset = file_size
    end

    local fd = io.open(path, "rb")
    if not fd then
        write_json({ code = 2, message = "open file failed" })
        return
    end
    if start_offset > 0 then
        if not fd:seek("set", start_offset) then
            fd:close()
            write_json({ code = 2, message = "seek file failed" })
            return
        end
    end

    local content = fd:read(read_limit + 1) or ""
    fd:close()
    local truncated = #content > read_limit or (start_offset + #content) < file_size
    if truncated then
        content = content:sub(1, read_limit)
    end

    local rows = {}
    for relative_offset = 1, #content, 16 do
        local chunk = content:sub(relative_offset, relative_offset + 15)
        local hex = {}
        local ascii = {}
        for index = 1, #chunk do
            local byte = chunk:byte(index)
            if index == 9 then
                table.insert(hex, " ")
                table.insert(ascii, " ")
            end
            table.insert(hex, string.format("%02x", byte))
            table.insert(ascii, byte > 32 and byte <= 126 and string.char(byte) or ".")
        end
        table.insert(rows, {
            line = #rows + 1,
            offset = hex32(start_offset + relative_offset - 1),
            hex = table.concat(hex, " "),
            ascii = table.concat(ascii, "")
        })
    end

    write_json({
        code = 0,
        message = "success",
        data = {
            path = path,
            rows = rows,
            truncated = truncated,
            max_size = max_binary_read_size,
            max_kb = max_binary_read_kb,
            size = file_size,
            offset = start_offset,
            requested_size = read_limit,
            requested_kb = read_kb,
            read_size = #content,
            lines = #rows,
            mtime = tonumber(stat.mtime) or 0
        }
    })
end

function api_save_text()
    if not validate_write_request() then
        return
    end

    local path = normalize_path(luci.http.formvalue("path"))
    local stat, err = validate_text_edit_file(path)
    if not stat then
        write_json_status(400, "Bad Request", { code = 1, message = err or "invalid path" })
        return
    end
    if not system_operations_allowed() and is_system_path(path) then
        return deny_system_operation()
    end

    local parent, parent_err = get_writable_directory(parent_path(path))
    if not parent then
        write_json_status(403, "Forbidden", { code = 1, message = parent_err or "directory is not writable" })
        return
    end

    local content = luci.http.formvalue("content")
    if type(content) ~= "string" then
        content = ""
    end
    if #content > max_text_size then
        write_json_status(413, "Payload Too Large", { code = 1, message = "content is too large" })
        return
    end
    local has_space, available, space_err, required = ensure_directory_space(parent, #content)
    if not has_space then
        write_json_status(507, "Insufficient Storage", {
            code = 2,
            message = space_err or insufficient_space_message,
            data = { available_bytes = available, required_bytes = required or operation_space_margin }
        })
        return
    end

    local saved_stat, save_err = write_text_atomic(path, content, stat)
    if not saved_stat then
        write_json_status(500, "Save Failed", { code = 1, message = save_err or "save file failed" })
        return
    end

    write_json({
        code = 0,
        message = "success",
        data = {
            path = path,
            parent = parent,
            size = tonumber(saved_stat.size) or 0,
            mtime = tonumber(saved_stat.mtime) or 0
        }
    })
end

function api_image()
    local path = normalize_path(luci.http.formvalue("path"))
    local request_id = "image-" .. tostring(math.floor(video_now_ms() or 0))
    hb_log(video_log_file, request_id .. " begin raw_path=" .. clean_log_value(luci.http.formvalue("path")) .. " path=" .. clean_log_value(path))
    local stat, err = validate_preview_file(path, "image")
    if not stat then
        hb_log(video_log_file, request_id .. " reject path=" .. clean_log_value(path) .. " error=" .. clean_log_value(err))
        write_plain_status(400, "Bad Request", err)
        return
    end

    local fd = io.open(path, "rb")
    if not fd then
        hb_log(video_log_file, request_id .. " open_failed path=" .. clean_log_value(path))
        write_plain_status(500, "Internal Server Error", "open file failed")
        return
    end

    local mime = image_mime_map[get_ext(path)] or "application/octet-stream"
    set_status(200, "OK")
    luci.http.header("X-Content-Type-Options", "nosniff")
    luci.http.header("Content-Length", tostring(stat.size or 0))
    luci.http.header("Cache-Control", "no-store")
    luci.http.header("Content-Disposition", "inline")
    luci.http.prepare_content(mime)
    hb_log(video_log_file, request_id .. " response path=" .. clean_log_value(path) .. " size=" .. tostring(stat.size or 0) .. " mime=" .. mime)

    local sent = 0
    local write_error = ""
    while true do
        local data = fd:read(65536)
        if not data or #data == 0 then
            break
        end
        luci.http.write(data)
        sent = sent + #data
    end
    fd:close()
    hb_log(video_log_file, request_id .. " done path=" .. clean_log_value(path) .. " sent=" .. tostring(sent) .. " error=" .. clean_log_value(write_error))
end

function api_thumbnail()
    local nixio_fs = require "nixio.fs"
    local path = normalize_path(luci.http.formvalue("path"))
    local stat, err = validate_preview_file(path, "image")
    if not stat then
        write_plain_status(400, "Bad Request", err)
        return
    end

    local cache_path = thumbnail_cache_path(path, stat, read_preferences())
    local cache_stat = cache_path and nixio_fs.stat(cache_path) or nil
    if not cache_stat or cache_stat.type ~= "reg" then
        write_plain_status(404, "Not Found", "thumbnail not found")
        return
    end

    local fd = io.open(cache_path, "rb")
    if not fd then
        write_plain_status(500, "Internal Server Error", "open thumbnail failed")
        return
    end

    set_status(200, "OK")
    luci.http.header("Content-Length", tostring(cache_stat.size or 0))
    luci.http.header("Cache-Control", "private, max-age=86400")
    luci.http.header("X-Content-Type-Options", "nosniff")
    luci.http.prepare_content("image/jpeg")

    while true do
        local data = fd:read(65536)
        if not data or #data == 0 then
            break
        end
        luci.http.write(data)
    end
    fd:close()
end

function api_pdf()
    local path = normalize_path(luci.http.formvalue("path"))
    local stat, err = validate_preview_file(path, "pdf")
    if not stat then
        write_plain_status(400, "Bad Request", err)
        return
    end

    local fd = io.open(path, "rb")
    if not fd then
        write_plain_status(500, "Internal Server Error", "open file failed")
        return
    end

    set_status(200, "OK")
    luci.http.header("Content-Length", tostring(stat.size or 0))
    luci.http.header("Cache-Control", "private, max-age=60")
    luci.http.header("X-Content-Type-Options", "nosniff")
    luci.http.prepare_content(pdf_mime_map[get_ext(path)])

    while true do
        local data = fd:read(65536)
        if not data or #data == 0 then
            break
        end
        luci.http.write(data)
    end
    fd:close()
end

local function parse_range_header(value, file_size)
    local start_value
    local end_value
    if value then
        start_value, end_value = value:match("^bytes=(%d*)%-(%d*)$")
    end
    if start_value == nil then
        return nil, nil
    end

    local start_pos
    local end_pos
    if start_value == "" then
        local suffix = tonumber(end_value)
        if not suffix or suffix <= 0 then
            return nil, nil
        end
        start_pos = suffix >= file_size and 0 or file_size - suffix
        end_pos = file_size - 1
    else
        start_pos = tonumber(start_value)
        end_pos = end_value == "" and file_size - 1 or tonumber(end_value)
        if not start_pos or not end_pos or start_pos < 0 or end_pos < start_pos then
            return nil, nil
        end
        end_pos = math.min(end_pos, file_size - 1)
    end

    if start_pos >= file_size then
        return nil, nil
    end
    return start_pos, end_pos
end

local function get_request_range()
    local candidates = {}
    local range_value = luci.http.getenv("HTTP_RANGE")
    table.insert(candidates, "http_env=" .. clean_log_value(range_value))
    if range_value and range_value ~= "" then
        return range_value, "http_env", table.concat(candidates, " ")
    end
    range_value = luci.http.getenv("Range")
    table.insert(candidates, "http_header=" .. clean_log_value(range_value))
    if range_value and range_value ~= "" then
        return range_value, "http_header", table.concat(candidates, " ")
    end
    range_value = os.getenv("HTTP_RANGE")
    table.insert(candidates, "process_env=" .. clean_log_value(range_value))
    if range_value and range_value ~= "" then
        return range_value, "process_env", table.concat(candidates, " ")
    end
    range_value = os.getenv("Range")
    table.insert(candidates, "process_header=" .. clean_log_value(range_value))
    if range_value and range_value ~= "" then
        return range_value, "process_header", table.concat(candidates, " ")
    end
    range_value = luci.http.formvalue("range")
    table.insert(candidates, "query=" .. clean_log_value(range_value))
    if range_value and range_value ~= "" then
        return range_value, "query", table.concat(candidates, " ")
    end
    return "", "none", table.concat(candidates, " ")
end

local function build_video_range(file_size, range_value)
    if range_value == "" then
        return 0, file_size - 1, false
    end

    local start_pos, end_pos = parse_range_header(range_value, file_size)
    if start_pos == nil then
        return nil, nil, nil
    end
    return start_pos, end_pos, true
end

local function stream_file(fd, content_length)
    local remain = content_length
    local sent = 0
    local first_write_ms
    while remain > 0 do
        local block_size = math.min(remain, 65536)
        local data = fd:read(block_size)
        if not data or #data == 0 then
            return sent, first_write_ms, "unexpected end of file"
        end
        luci.http.write(data)
        if not first_write_ms then
            first_write_ms = video_now_ms()
        end
        sent = sent + #data
        remain = remain - #data
    end
    return sent, first_write_ms
end

function api_video()
    local request_started = video_now_ms()
    local request_id = tostring(os.time()) .. "-" .. tostring({}):gsub("[^%w]", ""):sub(-8)
    local path = normalize_path(luci.http.formvalue("path"))
    local stat, err = validate_preview_file(path, "video")
    if not stat then
        hb_log(video_log_file, request_id .. " reject path=" .. clean_log_value(path) .. " error=" .. clean_log_value(err))
        write_plain_status(400, "Bad Request", err)
        return
    end

    local file_size = stat.size or 0
    if file_size <= 0 then
        write_plain_status(404, "Not Found", "empty file")
        return
    end

    local range_value, range_source, range_candidates = get_request_range()
    hb_log(video_log_file, request_id .. " begin method=" .. clean_log_value(luci.http.getenv("REQUEST_METHOD")) ..
        " path=" .. clean_log_value(path) .. " size=" .. tostring(file_size) ..
        " range_source=" .. range_source .. " range=" .. clean_log_value(range_value) ..
        " candidates=" .. range_candidates)
    hb_log(video_log_file, request_id .. " " .. describe_http_environment())
    local start_pos, end_pos, partial = build_video_range(file_size, range_value)
    luci.http.header("X-FS-Range-Source", range_source)
    if start_pos == nil then
        set_status(416, "Range Not Satisfiable")
        luci.http.header("Content-Range", "bytes */" .. tostring(file_size))
        luci.http.prepare_content("text/plain")
        luci.http.write("invalid range")
        return
    end

    local fd = io.open(path, "rb")
    if not fd then
        hb_log(video_log_file, request_id .. " open_failed elapsed_ms=" .. tostring(video_now_ms() - request_started))
        write_plain_status(500, "Internal Server Error", "open file failed")
        return
    end
    if not fd:seek("set", start_pos) then
        fd:close()
        hb_log(video_log_file, request_id .. " seek_failed start=" .. tostring(start_pos))
        write_plain_status(500, "Internal Server Error", "seek file failed")
        return
    end

    local content_length = end_pos - start_pos + 1
    set_status(partial and 206 or 200, partial and "Partial Content" or "OK")
    if partial then
        luci.http.header("Content-Range", string.format("bytes %d-%d/%d", start_pos, end_pos, file_size))
    end
    luci.http.header("X-FS-Range-Served", partial and string.format("%d-%d", start_pos, end_pos) or "full")
    luci.http.header("Accept-Ranges", "bytes")
    luci.http.header("Content-Length", tostring(content_length))
    luci.http.header("Cache-Control", "private, max-age=60")
    luci.http.prepare_content(video_mime_map[get_ext(path)])
    hb_log(video_log_file, request_id .. " response status=" .. (partial and "206" or "200") ..
        " start=" .. tostring(start_pos) .. " end=" .. tostring(end_pos) ..
        " length=" .. tostring(content_length) .. " header_ms=" .. tostring(video_now_ms() - request_started))

    if luci.http.getenv("REQUEST_METHOD") ~= "HEAD" then
        local sent, first_write_ms, stream_err = stream_file(fd, content_length)
        hb_log(video_log_file, request_id .. " stream_done sent=" .. tostring(sent) ..
            " first_write_ms=" .. tostring(first_write_ms and first_write_ms - request_started or -1) ..
            " total_ms=" .. tostring(video_now_ms() - request_started) ..
            " error=" .. clean_log_value(stream_err))
    end
    fd:close()
end

function api_video_log()
    local nixio_fs = require "nixio.fs"
    local content = nixio_fs.readfile(video_log_file) or ""
    if #content > 65536 then
        content = content:sub(#content - 65535)
    end
    luci.http.header("Cache-Control", "no-store")
    write_json({ code = 0, message = "success", data = { content = content } })
end

local function find_upload_conflicts(target_dir, names)
    local nixio_fs = require "nixio.fs"
    local conflicts = {}
    local blocked = {}
    for _, name in ipairs(names) do
        local stat = nixio_fs.lstat(join_path(target_dir, name))
        if stat then
            if stat.type == "reg" then
                table.insert(conflicts, name)
            else
                table.insert(blocked, name)
            end
        end
    end
    return conflicts, blocked
end

function api_upload_check()
    if luci.http.getenv("REQUEST_METHOD") ~= "POST" then
        write_json_status(400, "Bad Request", { code = 1, message = "POST required" })
        return
    end

    local total_size = parse_size(luci.http.formvalue("total_size"))
    local names, names_err = parse_upload_names(luci.http.formvalue("names"))
    if total_size == nil or not names then
        write_json_status(400, "Bad Request", { code = 1, message = names_err or "invalid total size" })
        return
    end

    local target_dir, available, dir_err = get_upload_directory(luci.http.formvalue("target_dir"))
    if not target_dir then
        write_json_status(403, "Forbidden", { code = 1, message = dir_err })
        return
    end
    if not system_operations_allowed() and is_system_path(target_dir) then
        return deny_system_operation()
    end

    local required = total_size + upload_safety_margin
    local conflicts, blocked = find_upload_conflicts(target_dir, names)
    write_json({
        code = 0,
        message = "success",
        data = {
            target_dir = target_dir,
            available_bytes = available,
            required_bytes = required,
            safety_margin = upload_safety_margin,
            enough_space = available >= required,
            space_message = available >= required and "" or insufficient_space_message,
            conflicts = conflicts,
            blocked_conflicts = blocked
        }
    })
end

local function parse_query_params()
	return {
		target_dir = luci.http.formvalue("target_dir", true),
		expected_size = luci.http.formvalue("expected_size", true),
		overwrite = luci.http.formvalue("overwrite", true)
	}
end

local function close_upload_file(state)
    if state.fd then
        state.fd:close()
        state.fd = nil
    end
end

local function cleanup_upload(state)
    local nixio_fs = require "nixio.fs"
    close_upload_file(state)
    if state.temp_path then
        nixio_fs.unlink(state.temp_path)
        state.temp_path = nil
    end
end

local function fail_upload(state, status, message)
    if not state.error then
        state.status = status
        state.error = message
    end
    cleanup_upload(state)
end

local function start_upload_file(state, meta)
    local nixio_fs = require "nixio.fs"
    if state.started then
        fail_upload(state, 400, "only one file is allowed per request")
        return false
    end

    if not meta or meta.name ~= "file" then
        fail_upload(state, 400, "invalid upload field")
        return false
    end

    local name = meta.file
    if not validate_upload_name(name) then
        fail_upload(state, 400, "invalid file name")
        return false
    end

    local final_path = join_path(state.target_dir, name)
    local existing = nixio_fs.lstat(final_path)
    if existing and (not state.overwrite or existing.type ~= "reg") then
        fail_upload(state, 409, "target already exists")
        return false
    end

    local token = tostring({}):gsub("[^%w]", "")
    local temp_path = join_path(state.target_dir, ".harbor-upload-" .. tostring(os.time()) .. "-" .. token)
    local fd = io.open(temp_path, "wb")
    if not fd then
        fail_upload(state, 500, "create temporary file failed")
        return false
    end

    state.started = true
    state.name = name
    state.final_path = final_path
    state.temp_path = temp_path
    state.fd = fd
    return true
end

local function finish_upload_file(state)
    local nixio_fs = require "nixio.fs"
    close_upload_file(state)
    if state.written ~= state.expected_size then
        fail_upload(state, 400, "uploaded file size does not match")
        return
    end

    local existing = nixio_fs.lstat(state.final_path)
    if existing and (not state.overwrite or existing.type ~= "reg") then
        fail_upload(state, 409, "target already exists")
        return
    end

    if not os.rename(state.temp_path, state.final_path) then
        fail_upload(state, 500, "save uploaded file failed")
        return
    end
    state.temp_path = nil
    state.completed = true
end

local function handle_upload_chunk(state, meta, chunk, eof)
    if state.error then
        return
    end
    if not state.started and not start_upload_file(state, meta) then
        return
    end

    if chunk and #chunk > 0 then
        if state.written + #chunk > state.expected_size then
            fail_upload(state, 400, "uploaded file is larger than declared size")
            return
        end
        local write_ok, result = pcall(state.fd.write, state.fd, chunk)
        if not write_ok or not result then
            fail_upload(state, 500, "write uploaded file failed")
            return
        end
        state.written = state.written + #chunk
    end

    if eof then
        finish_upload_file(state)
    end
end

function api_upload()
    if luci.http.getenv("REQUEST_METHOD") ~= "POST" then
        write_json_status(400, "Bad Request", { code = 1, message = "POST required" })
        return
    end

    local params = parse_query_params()
    local expected_size = parse_size(params.expected_size)
    local target_dir, available, dir_err = get_upload_directory(params.target_dir)
    if expected_size == nil or not target_dir then
        local status = target_dir and 400 or 403
        write_json_status(status, status == 400 and "Bad Request" or "Forbidden", {
            code = 1,
            message = dir_err or "invalid expected size"
        })
        return
    end
    if not system_operations_allowed() and is_system_path(target_dir) then
        return deny_system_operation()
    end
    if available < expected_size + upload_safety_margin then
        write_json_status(507, "Insufficient Storage", {
            code = 2,
            message = insufficient_space_message,
            data = {
                available_bytes = available,
                required_bytes = expected_size + upload_safety_margin
            }
        })
        return
    end

    local state = {
        target_dir = target_dir,
        expected_size = expected_size,
        overwrite = params.overwrite == "1",
        written = 0,
        status = 500
    }
    luci.http.setfilehandler(function(meta, chunk, eof)
        handle_upload_chunk(state, meta, chunk, eof)
    end)

    local parse_ok = pcall(function()
        luci.http.formvalue("file")
    end)
    if not parse_ok and not state.error then
        fail_upload(state, 400, "parse upload request failed")
    elseif not state.started and not state.error then
        fail_upload(state, 400, "upload file is missing")
    elseif not state.completed and not state.error then
        fail_upload(state, 400, "upload is incomplete")
    end

    if state.error then
        write_json_status(state.status, state.status == 409 and "Conflict" or "Upload Failed", {
            code = 1,
            message = state.error
        })
        return
    end

    write_json({
        code = 0,
        message = "success",
        data = {
            name = state.name,
            path = state.final_path,
            size = state.written
        }
    })
end
