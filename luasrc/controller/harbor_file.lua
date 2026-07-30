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

local harbor_log_file = "/tmp/log/harbor_file.log"
local harbor_debug_log = os.getenv("HARBOR_FILE_DEBUG") == "1"

archive = {
    state_file = "/tmp/harbor_file_archive_state.json",
    log_file = harbor_log_file,
    log_limit = 131072,
    create_formats = {
        ["tar.gz"] = { extension = ".tar.gz", command = "tar", title = "TAR.GZ" }
    },
    extract_formats = {
        zip = { command = "unzip", title = "ZIP", container = true },
        tar = { command = "tar", title = "TAR", container = true },
        ["tar.gz"] = { command = "tar", title = "TAR.GZ", container = true },
        tgz = { command = "tar", title = "TGZ", container = true, canonical = "tar.gz" },
        gz = { command = "gzip", title = "GZ", single_file = true }
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
local operation_space_ratio = 0.05
local thumbnail_memory_margin = 20 * 1024
local insufficient_space_message = "available space is less than 5% of the current partition, operation is not allowed"
local package_install_state_file = "/tmp/harbor_file_package_install_state.json"
local package_install_log_file = harbor_log_file
local preferences_log_file = harbor_log_file
local package_install_log_limit = 131072
local thumbnail_task_state_file = "/tmp/harbor_file_thumbnail_state.json"
local thumbnail_task_log_file = harbor_log_file
local thumbnail_task_log_limit = 65536
local thumbnail_size = 128
local thumbnail_cache_version = "contain-v2"
local nginx_template_file = "/etc/nginx/uci.conf.template"
local nginx_insert_anchor = "large_client_header_buffers"
local nginx_package_name = "luci-nginx"
local terminal_package_name = "ttyd"
local uwsgi_config_file = "/etc/uwsgi/vassals/luci-webui.ini"
local uhttpd_script_timeout_default = 600
local uhttpd_network_timeout_default = 600
local uwsgi_configuration_options = {
    {
        name = "reload-on-as",
        preference = "reload-on-as",
        enabled_preference = "reload-on-as_enabled",
        default_value = 256,
        default_enabled = 0
    },
    {
        name = "reload-on-rss",
        preference = "reload-on-rss",
        enabled_preference = "reload-on-rss_enabled",
        default_value = 192,
        default_enabled = 0
    },
    {
        name = "post-buffering",
        preference = "post-buffering",
        default_value = 8192
    },
    {
        name = "limit-as",
        preference = "limit-as",
        default_value = 1000
    },
    {
        name = "reload-mercy",
        preference = "reload-mercy",
        default_value = 8
    },
    {
        name = "buffer-size",
        preference = "buffer-size",
        default_value = 10000
    }
}
local nginx_configuration_options = {
    {
        preference = "uwsgi_request_buffering",
        directive = "uwsgi_request_buffering",
        values = {
            [0] = "off",
            [1] = "on"
        }
    },
    {
        preference = "client_max_body_size",
        directive = "client_max_body_size",
        value = function(preference_value)
            if preference_value == 0 then
                return "0"
            end
            return tostring(preference_value) .. "M"
        end
    }
}
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
    if nixio_fs.access("/etc/fwx_release") then
        entry({"admin", "fwx_harbor_file"}, template("harbor_file/index"), _("File management"), 16).dependent = true
    else
        entry({"admin", "harbor_file"}, alias("admin", "system", "harbor_file"), nil).leaf = true
        entry({"admin", "system", "harbor_file"}, template("harbor_file/index"), _("Harbor File"), 90).dependent = true
    end
    entry({"admin", "local_fs", "navigation"}, call("api_navigation"), nil).leaf = true
    entry({"admin", "local_fs", "terminal_info"}, call("api_terminal_info"), nil).leaf = true
    entry({"admin", "local_fs", "preferences"}, call("api_preferences"), nil).leaf = true
    entry({"admin", "local_fs", "save_preferences"}, call("api_save_preferences"), nil).leaf = true
    entry({"admin", "local_fs", "nginx_install_start"}, call("api_nginx_install_start"), nil).leaf = true
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
    entry({"admin", "local_fs", "terminal_tool_install_start"}, call("api_terminal_tool_install_start"), nil).leaf = true
    entry({"admin", "local_fs", "pdf"}, call("api_pdf"), nil).leaf = true
    entry({"admin", "local_fs", "video"}, call("api_video"), nil).leaf = true
    entry({"admin", "local_fs", "video_check"}, call("api_video_check"), nil).leaf = true
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
    entry({"admin", "local_fs", "archive_create_start"}, call("api_archive_create_start"), nil).leaf = true
    entry({"admin", "local_fs", "archive_extract_start"}, call("api_archive_extract_start"), nil).leaf = true
    entry({"admin", "local_fs", "archive_status"}, call("api_archive_status"), nil).leaf = true
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
    log_path = harbor_log_file
    if not nixio_fs.stat("/tmp/log") then
        nixio_fs.mkdir("/tmp/log")
    end
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

local function preference_log(message)
    if harbor_debug_log then
        hb_log(preferences_log_file, clean_log_value(message))
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
    path = harbor_log_file
    return truncate_log_text(nixio_fs.readfile(path) or "", limit or package_install_log_limit)
end

local function shell_quote(value)
    local text = tostring(value or "")
    return "'" .. text:gsub("'", [['"'"']]) .. "'"
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

local function normalize_nginx_body_size(value, default_value)
    local number = tonumber(value)
    if not number then
        return default_value
    end
    number = math.floor(number)
    if number < 0 or number > 1024 then
        return default_value
    end
    return number
end

local function normalize_integer_value(value, default_value)
    local number = tonumber(value)
    if not number then
        return default_value
    end
    return math.floor(number)
end

local function normalize_timeout_value(value, default_value)
    local number = normalize_integer_value(value, default_value)
    if number < 0 then
        return default_value
    end
    return number
end

local function to_boolean(value)
    local text = tostring(value or ""):lower()
    return text == "1" or text == "true" or text == "yes" or text == "on"
end

local function ensure_preference_section(uci)
    uci = uci or require("luci.model.uci").cursor()
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

local function detect_web_server()
    local process = io.popen("ps ww 2>/dev/null || ps w 2>/dev/null || ps 2>/dev/null", "r")
    if not process then
        return "unknown"
    end

    local nginx_running = false
    local uhttpd_running = false
    for line in process:lines() do
        local command = line:lower()
        if command:find("nginx:", 1, true) or command:find("/nginx", 1, true) or
                command:match("%snginx%s") then
            nginx_running = true
        elseif command:find("/uhttpd", 1, true) or command:match("%suhttpd%s") then
            uhttpd_running = true
        end
    end
    process:close()

    if nginx_running then
        return "nginx"
    end
    if uhttpd_running then
        return "uhttpd"
    end
    return "unknown"
end

local function is_fanchmwrt_system()
    local nixio_fs = require "nixio.fs"
    return nixio_fs.access("/etc/fwx_release") and 1 or 0
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

local function read_uwsgi_preferences(include_state)
    local nixio_fs = require "nixio.fs"
    local content = nixio_fs.readfile(uwsgi_config_file)
    local preferences = {
        uwsgi_config_available = content ~= nil
    }
    if include_state then
        preferences._present = {}
    end

    for _, option in ipairs(uwsgi_configuration_options) do
        preferences[option.preference] = option.default_value
        if option.enabled_preference then
            preferences[option.enabled_preference] = option.default_enabled
        end
    end

    if not content then
        return preferences
    end

    for line in content:gmatch("[^\r\n]+") do
        for _, option in ipairs(uwsgi_configuration_options) do
            local pattern = option.name:gsub("%-", "%%-")
            local disabled, value = line:match("^%s*(;?)%s*" .. pattern .. "%s*=%s*([+-]?%d+)")
            if value then
                if include_state then
                    preferences._present[option.preference] = true
                end
                preferences[option.preference] = normalize_integer_value(value, option.default_value)
                if option.enabled_preference then
                    preferences[option.enabled_preference] = disabled == ";" and 0 or 1
                end
            end
        end
    end

    return preferences
end

local function read_nginx_preferences()
    local nixio_fs = require "nixio.fs"
    local content = nixio_fs.readfile(nginx_template_file)
    local preferences = {
        nginx_config_available = content ~= nil,
        uwsgi_request_buffering = 0,
        client_max_body_size = 128
    }

    if not content then
        return preferences
    end

    for line in content:gmatch("[^\r\n]+") do
        local buffering = line:match("^%s*uwsgi_request_buffering%s+([^;]+);%s*$")
        if buffering then
            buffering = tostring(buffering):lower():match("^%s*(.-)%s*$")
            preferences.uwsgi_request_buffering = buffering == "on" and 1 or 0
        end

        local body_size = line:match("^%s*client_max_body_size%s+([^;]+);%s*$")
        if body_size then
            body_size = tostring(body_size):lower():match("^%s*(.-)%s*$")
            if body_size == "0" then
                preferences.client_max_body_size = 0
            else
                preferences.client_max_body_size = normalize_nginx_body_size(
                    body_size:match("^(%d+)m$") or body_size:match("^(%d+)$"),
                    preferences.client_max_body_size
                )
            end
        end
    end

    return preferences
end

local function read_uhttpd_preferences()
    local nixio_fs = require "nixio.fs"
    local uci = require("luci.model.uci").cursor()
    local preferences = {
        uhttpd_config_available = nixio_fs.access("/etc/config/uhttpd") == true,
        uhttpd_script_timeout = uhttpd_script_timeout_default,
        uhttpd_network_timeout = uhttpd_network_timeout_default
    }

    local ok, script_timeout = pcall(function()
        return uci:get("uhttpd", "main", "script_timeout")
    end)
    if ok then
        preferences.uhttpd_script_timeout = normalize_timeout_value(
            script_timeout,
            preferences.uhttpd_script_timeout
        )
    end

    local network_ok, network_timeout = pcall(function()
        return uci:get("uhttpd", "main", "network_timeout")
    end)
    if network_ok then
        preferences.uhttpd_network_timeout = normalize_timeout_value(
            network_timeout,
            preferences.uhttpd_network_timeout
        )
    end

    return preferences
end

local function save_basic_preferences(view_mode, allow_system_operations, show_hidden_files, home_dir, enable_thumbnails)
    local uci = require("luci.model.uci").cursor()
    ensure_preference_section(uci)
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

local function detect_nginx_installer()
    if find_executable("apk") then
        return "apk"
    end
    if find_executable("opkg") then
        return "opkg"
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

local function replace_nginx_directive(content, directive, value)
    local count = 0
    local updated = content:gsub(
        "([^\r\n]+)",
        function(line)
            local indent = line:match("^([ \t]*)" .. directive .. "%s+[^;]+;%s*$")
            if indent and count == 0 then
                count = 1
                return indent .. directive .. " " .. value .. ";"
            end
            return line
        end
    )
    return updated, count > 0
end

local function insert_nginx_directive(content, directive, value)
    local count = 0
    local updated = content:gsub(
        "([^\r\n]+)",
        function(line)
            local indent = line:match("^([ \t]*)" .. nginx_insert_anchor .. "%s+[^;]+;%s*$")
            if indent and count == 0 then
                count = 1
                return line .. "\n" .. indent .. directive .. " " .. value .. ";"
            end
            return line
        end
    )
    return updated, count > 0
end

local function set_nginx_directive(content, directive, value)
    local updated, found = replace_nginx_directive(content, directive, value)
    if found then
        return updated, true
    end
    return insert_nginx_directive(updated, directive, value)
end

local function backup_config_file(path, content)
    local nixio_fs = require "nixio.fs"
    local backup_path = path .. ".harbor_file.bak"
    if not nixio_fs.writefile(backup_path, content) then
        return nil
    end
    return backup_path
end

local function restore_config_file(path, content)
    local nixio_fs = require "nixio.fs"
    return nixio_fs.writefile(path, content)
end

local function schedule_uwsgi_restart()
    local result = os.execute("(sleep 1; /etc/init.d/uwsgi restart >/dev/null 2>&1) >/dev/null 2>&1 &")
    return result ~= false and result ~= nil
end

local function read_uwsgi_form_preferences(current)
    local preferences = {}
    current = current or read_uwsgi_preferences()

    for _, option in ipairs(uwsgi_configuration_options) do
        preferences[option.preference] = normalize_integer_value(
            luci.http.formvalue(option.preference),
            current[option.preference] or option.default_value
        )
        if option.enabled_preference then
            preferences[option.enabled_preference] = normalize_preference_number(
                luci.http.formvalue(option.enabled_preference),
                current[option.enabled_preference] or option.default_enabled,
                valid_boolean_values
            )
        end
    end

    return preferences
end

local function uwsgi_preferences_changed(current, target)
    local present = current._present or {}
    for _, option in ipairs(uwsgi_configuration_options) do
        if not present[option.preference] then
            return true
        end
        if current[option.preference] ~= target[option.preference] then
            return true
        end
        if option.enabled_preference and current[option.enabled_preference] ~= target[option.enabled_preference] then
            return true
        end
    end
    return false
end

local function save_uwsgi_configuration(target)
    local nixio_fs = require "nixio.fs"
    local content = nixio_fs.readfile(uwsgi_config_file)
    if not content then
        return nil, _("uWSGI configuration file was not found")
    end

    local current = read_uwsgi_preferences(true)
    if not uwsgi_preferences_changed(current, target) then
        return true
    end

    local backup_path = backup_config_file(uwsgi_config_file, content)
    if not backup_path then
        return nil, _("Failed to backup uWSGI configuration")
    end

    local commands = {}
    for _, option in ipairs(uwsgi_configuration_options) do
        local disabled = option.enabled_preference and target[option.enabled_preference] ~= 1
        local prefix = disabled and ";" or ""
        local line = prefix .. option.name .. " = " .. tostring(target[option.preference])
        table.insert(commands, "sed -i " .. shell_quote("/^[;[:space:]]*" .. option.name .. "[[:space:]]*=.*/d") ..
            " " .. shell_quote(uwsgi_config_file))
        table.insert(commands, "echo " .. shell_quote(line) .. " >> " .. shell_quote(uwsgi_config_file))
    end

    if parse_execute_result(os.execute(table.concat(commands, " && "))) ~= 0 then
        restore_config_file(uwsgi_config_file, content)
        return nil, _("Failed to update uWSGI configuration")
    end
    if not schedule_uwsgi_restart() then
        restore_config_file(uwsgi_config_file, content)
        return nil, _("Failed to restart uWSGI")
    end
    nixio_fs.unlink(backup_path)
    return true
end

local function schedule_nginx_restart()
    local result = os.execute("(sleep 1; /etc/init.d/nginx restart >/dev/null 2>&1) >/dev/null 2>&1 &")
    return result ~= false and result ~= nil
end

local function schedule_uhttpd_restart()
    local result = os.execute("(sleep 1; /etc/init.d/uhttpd restart >/dev/null 2>&1) >/dev/null 2>&1 &")
    return result ~= false and result ~= nil
end

local function read_uhttpd_form_preferences(current)
    current = current or read_uhttpd_preferences()
    return {
        uhttpd_script_timeout = normalize_timeout_value(
            luci.http.formvalue("uhttpd_script_timeout"),
            current.uhttpd_script_timeout or uhttpd_script_timeout_default
        ),
        uhttpd_network_timeout = normalize_timeout_value(
            luci.http.formvalue("uhttpd_network_timeout"),
            current.uhttpd_network_timeout or uhttpd_network_timeout_default
        )
    }
end

local function ensure_uhttpd_section(uci)
    local ok, section = pcall(function()
        return uci:get("uhttpd", "main")
    end)
    if not ok or section == nil then
        uci:section("uhttpd", "uhttpd", "main", {})
    end
end

local function save_uhttpd_configuration(target)
    local uci = require("luci.model.uci").cursor()
    ensure_uhttpd_section(uci)
    uci:set("uhttpd", "main", "script_timeout", tostring(target.uhttpd_script_timeout))
    uci:set("uhttpd", "main", "network_timeout", tostring(target.uhttpd_network_timeout))
    if not uci:commit("uhttpd") then
        return nil, _("Failed to update uHTTPd configuration")
    end
    if not schedule_uhttpd_restart() then
        return nil, _("Failed to restart uHTTPd")
    end
    return true
end

local function read_nginx_form_preferences(current)
    current = current or read_nginx_preferences()
    return {
        uwsgi_request_buffering = normalize_preference_number(
            luci.http.formvalue("uwsgi_request_buffering"),
            current.uwsgi_request_buffering,
            valid_boolean_values
        ),
        client_max_body_size = normalize_nginx_body_size(
            luci.http.formvalue("client_max_body_size"),
            current.client_max_body_size
        )
    }
end

local function test_nginx_configuration()
    local command = "nginx -t -c " .. shell_quote(nginx_template_file) .. " >/dev/null 2>&1"
    return parse_execute_result(os.execute(command)) == 0
end

local function save_nginx_configuration(target)
    local nixio_fs = require "nixio.fs"
    local content = nixio_fs.readfile(nginx_template_file)
    if not content then
        return nil, _("Nginx configuration template was not found")
    end

    local updated = content
    for _, option in ipairs(nginx_configuration_options) do
        local preference_value = target[option.preference]
        local value = option.value and option.value(preference_value) or option.values[preference_value]
        local found
        updated, found = set_nginx_directive(updated, option.directive, value)
    end
    if updated == content then
        return true
    end

    local backup_path = backup_config_file(nginx_template_file, content)
    if not backup_path then
        return nil, _("Failed to backup Nginx configuration")
    end
    if not nixio_fs.writefile(nginx_template_file, updated) then
        restore_config_file(nginx_template_file, content)
        return nil, _("Failed to update Nginx configuration")
    end
    if not test_nginx_configuration() then
        restore_config_file(nginx_template_file, content)
        return nil, _("Nginx configuration test failed")
    end
    if not schedule_nginx_restart() then
        restore_config_file(nginx_template_file, content)
        return nil, _("Failed to restart Nginx")
    end
    nixio_fs.unlink(backup_path)
    return true
end

local function run_logged_command(executable, args, log_path)
    log_path = harbor_log_file
    local command = "mkdir -p /tmp/log; " .. command_to_shell(executable, args) .. " >> " .. shell_quote(log_path) .. " 2>&1"
    return parse_execute_result(os.execute(command))
end

function archive.run_shell(command, log_path)
    log_path = harbor_log_file
    return parse_execute_result(os.execute("mkdir -p /tmp/log; ( " .. tostring(command or "") .. " ) >> " .. shell_quote(log_path) .. " 2>&1"))
end

local function activate_nginx_web_server(log_path)
    log_path = harbor_log_file
    local command = table.concat({
        "if [ -x /etc/init.d/uhttpd ]; then /etc/init.d/uhttpd disable; /etc/init.d/uhttpd stop; fi",
        "/etc/init.d/uwsgi enable",
        "/etc/init.d/uwsgi restart",
        "/etc/init.d/nginx enable",
        "/etc/init.d/nginx restart"
    }, "; ")
    return parse_execute_result(os.execute(
        "mkdir -p /tmp/log; ( " .. command .. " ) >> " .. shell_quote(log_path) .. " 2>&1"
    ))
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
    if task.activate_nginx then
        os.execute("sleep 2")
    end
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

    hb_log(package_install_log_file, "==== Package install task start ====")
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
    if success and task.activate_nginx then
        local activate_exit_code = activate_nginx_web_server(package_install_log_file)
        if activate_exit_code ~= 0 then
            success = false
            exit_code = activate_exit_code
            hb_log(package_install_log_file, "Failed to activate nginx with code " .. tostring(activate_exit_code))
        end
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
        elseif cache_path then
            local temp_path = cache_path .. ".tmp." .. task.task_id
            os.remove(temp_path)
            local executable, args = build_thumbnail_command(gm_path, item.path, temp_path)
            local exit_code = run_logged_command(executable, args, thumbnail_task_log_file)
            if exit_code == 0 and nixio_fs.stat(temp_path) and os.rename(temp_path, cache_path) then
                task.success_count = task.success_count + 1
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

local function calculate_operation_space_margin(total_bytes)
    local total = tonumber(total_bytes) or 0
    if total <= 0 then
        return 0
    end
    return math.ceil(total * operation_space_ratio)
end

local function get_directory_space_info(path)
    local nixio_fs = require "nixio.fs"
    local normalized = normalize_path(path)
    if not normalized then
        return nil, nil, nil, "invalid directory"
    end
    local vfs = nixio_fs.statvfs(normalized)
    if not vfs then
        return nil, nil, nil, "read filesystem space failed"
    end
    local block_size = tonumber(vfs.frsize) or tonumber(vfs.bsize) or 0
    local available = (tonumber(vfs.bavail) or 0) * block_size
    local total = (tonumber(vfs.blocks) or 0) * block_size
    return available, total, calculate_operation_space_margin(total)
end

local function get_directory_available_bytes(path)
    local available, _, _, err = get_directory_space_info(path)
    if not available then
        return nil, err
    end
    return available
end

local function ensure_directory_space(path, required_bytes)
    local available, total, margin, err = get_directory_space_info(path)
    if not available then
        return false, 0, err
    end
    local required = (tonumber(required_bytes) or 0) + (margin or 0)
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

local function cleanup_stale_uploads(dir)
    local nixio_fs = require "nixio.fs"
    local iterator = nixio_fs.dir(dir)
    if not iterator then
        return
    end
    local now = os.time()
    for name in iterator do
        if name:sub(1, 15) == ".harbor-upload-" then
            local path = join_path(dir, name)
            local stat = nixio_fs.stat(path)
            if stat and stat.type == "reg" and now - (stat.mtime or 0) > 120 then
                nixio_fs.unlink(path)
            end
        end
    end
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

    cleanup_stale_uploads(normalized)
    local available, _, operation_space_margin, space_err = get_directory_space_info(normalized)
    if not available then
        return nil, nil, nil, space_err
    end
    return normalized, available, operation_space_margin or 0
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
    local preferences = read_preferences()
    if harbor_debug_log then
        preference_log("api_preferences start")
        preference_log("base view_mode=" .. tostring(preferences.view_mode) ..
            " home_dir=" .. tostring(preferences.home_dir) ..
            " allow_system_operations=" .. tostring(preferences.allow_system_operations) ..
            " show_hidden_files=" .. tostring(preferences.show_hidden_files) ..
            " enable_thumbnails=" .. tostring(preferences.enable_thumbnails))
    end
    local nginx_preferences = read_nginx_preferences()
    if harbor_debug_log then
        preference_log("nginx template=" .. tostring(nginx_template_file) ..
            " available=" .. tostring(nginx_preferences.nginx_config_available) ..
            " uwsgi_request_buffering=" .. tostring(nginx_preferences.uwsgi_request_buffering) ..
            " client_max_body_size=" .. tostring(nginx_preferences.client_max_body_size))
    end
    for key, value in pairs(nginx_preferences) do
        preferences[key] = value
    end
    local uwsgi_preferences = read_uwsgi_preferences()
    if harbor_debug_log then
        preference_log("uwsgi config=" .. tostring(uwsgi_config_file) ..
            " available=" .. tostring(uwsgi_preferences.uwsgi_config_available) ..
            " reload-on-as=" .. tostring(uwsgi_preferences["reload-on-as"]) ..
            " reload-on-as_enabled=" .. tostring(uwsgi_preferences["reload-on-as_enabled"]) ..
            " reload-on-rss=" .. tostring(uwsgi_preferences["reload-on-rss"]) ..
            " reload-on-rss_enabled=" .. tostring(uwsgi_preferences["reload-on-rss_enabled"]) ..
            " post-buffering=" .. tostring(uwsgi_preferences["post-buffering"]) ..
            " limit-as=" .. tostring(uwsgi_preferences["limit-as"]) ..
            " reload-mercy=" .. tostring(uwsgi_preferences["reload-mercy"]) ..
            " buffer-size=" .. tostring(uwsgi_preferences["buffer-size"]))
    end
    for key, value in pairs(uwsgi_preferences) do
        preferences[key] = value
    end
    local uhttpd_preferences = read_uhttpd_preferences()
    if harbor_debug_log then
        preference_log("uhttpd config available=" .. tostring(uhttpd_preferences.uhttpd_config_available) ..
            " script_timeout=" .. tostring(uhttpd_preferences.uhttpd_script_timeout) ..
            " network_timeout=" .. tostring(uhttpd_preferences.uhttpd_network_timeout))
    end
    for key, value in pairs(uhttpd_preferences) do
        preferences[key] = value
    end
    preferences.web_server = detect_web_server()
    preferences.nginx_running = preferences.web_server == "nginx"
    preferences.fcm = is_fanchmwrt_system()
    if harbor_debug_log then
        preference_log("detected web_server=" .. tostring(preferences.web_server) ..
            " nginx_running=" .. tostring(preferences.nginx_running) ..
            " fcm=" .. tostring(preferences.fcm))
        preference_log("response nginx_config_available=" .. tostring(preferences.nginx_config_available) ..
            " uwsgi_request_buffering=" .. tostring(preferences.uwsgi_request_buffering) ..
            " client_max_body_size=" .. tostring(preferences.client_max_body_size) ..
            " uwsgi_config_available=" .. tostring(preferences.uwsgi_config_available) ..
            " uhttpd_config_available=" .. tostring(preferences.uhttpd_config_available))
    end
    write_json({
        code = 0,
        message = "success",
        data = preferences
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

    local section = luci.http.formvalue("section") or "basic"
    local current = read_preferences()
    local web_server = detect_web_server()

    if section == "nginx" then
        section = "web_server"
    end

    if section == "web_server" then
        if web_server == "uhttpd" then
            local current_uhttpd_preferences = read_uhttpd_preferences()
            local uhttpd_preferences = read_uhttpd_form_preferences(current_uhttpd_preferences)
            local uhttpd_ok, uhttpd_saved, uhttpd_err = pcall(save_uhttpd_configuration, uhttpd_preferences)
            if not uhttpd_ok then
                uhttpd_err = tostring(uhttpd_saved)
                uhttpd_saved = nil
            end
            if not uhttpd_saved then
                write_json({
                    code = 1,
                    message = uhttpd_err or _("Failed to update uHTTPd configuration")
                })
                return
            end

            local preferences = read_preferences()
            local nginx_preferences = read_nginx_preferences()
            for key, value in pairs(nginx_preferences) do
                preferences[key] = value
            end
            local uwsgi_preferences = read_uwsgi_preferences()
            for key, value in pairs(uwsgi_preferences) do
                preferences[key] = value
            end
            local saved_uhttpd_preferences = read_uhttpd_preferences()
            for key, value in pairs(saved_uhttpd_preferences) do
                preferences[key] = value
            end
            preferences.web_server = web_server
            preferences.nginx_running = false
            preferences.fcm = is_fanchmwrt_system()
            write_json({
                code = 0,
                message = "success",
                data = preferences
            })
            return
        end

        if web_server ~= "nginx" then
            write_json_status(400, "Web Service Not Supported", {
                code = 1,
                message = _("Web service is not supported")
            })
            return
        end

        local current_nginx_preferences = read_nginx_preferences()
        local nginx_preferences = read_nginx_form_preferences(current_nginx_preferences)
        local current_uwsgi_preferences = read_uwsgi_preferences()
        local uwsgi_preferences = read_uwsgi_form_preferences(current_uwsgi_preferences)

        if not current_nginx_preferences.nginx_config_available then
            write_json({
                code = 1,
                message = _("Nginx configuration template was not found")
            })
            return
        end
        if not current_uwsgi_preferences.uwsgi_config_available then
            write_json({
                code = 1,
                message = _("uWSGI configuration file was not found")
            })
            return
        end

        local ok, applied, apply_err = pcall(save_nginx_configuration, nginx_preferences)
        if not ok then
            apply_err = tostring(applied)
            applied = nil
        end
        if not applied then
            write_json({
                code = 1,
                message = apply_err or _("Failed to update Nginx configuration")
            })
            return
        end

        local uwsgi_ok, uwsgi_saved, uwsgi_err = pcall(save_uwsgi_configuration, uwsgi_preferences)
        if not uwsgi_ok then
            uwsgi_err = tostring(uwsgi_saved)
            uwsgi_saved = nil
        end
        if not uwsgi_saved then
            write_json({
                code = 1,
                message = uwsgi_err or _("Failed to update uWSGI configuration")
            })
            return
        end

        local preferences = read_preferences()
        local saved_nginx_preferences = read_nginx_preferences()
        for key, value in pairs(saved_nginx_preferences) do
            preferences[key] = value
        end
        local saved_uwsgi_preferences = read_uwsgi_preferences()
        for key, value in pairs(saved_uwsgi_preferences) do
            preferences[key] = value
        end
        local uhttpd_preferences = read_uhttpd_preferences()
        for key, value in pairs(uhttpd_preferences) do
            preferences[key] = value
        end
        preferences.web_server = web_server
        preferences.nginx_running = true
        preferences.fcm = is_fanchmwrt_system()
        write_json({
            code = 0,
            message = "success",
            data = preferences
        })
        return
    end

    if section ~= "basic" then
        write_json_status(400, "Invalid Section", { code = 1, message = "invalid section" })
        return
    end

    local view_mode = normalize_preference_number(
        luci.http.formvalue("view_mode"),
        current.view_mode,
        valid_view_mode_values
    )
    local allow_system_operations = normalize_preference_number(
        luci.http.formvalue("allow_system_operations"),
        current.allow_system_operations,
        valid_boolean_values
    )
    local show_hidden_files = normalize_preference_number(
        luci.http.formvalue("show_hidden_files"),
        current.show_hidden_files,
        valid_boolean_values
    )
    local enable_thumbnails = normalize_preference_number(
        luci.http.formvalue("enable_thumbnails"),
        current.enable_thumbnails,
        valid_boolean_values
    )
    local home_dir = normalize_home_dir(luci.http.formvalue("home_dir") or current.home_dir)

    if not save_basic_preferences(
        view_mode,
        allow_system_operations,
        show_hidden_files,
        home_dir,
        enable_thumbnails
    ) then
        write_json_status(500, "Save Failed", { code = 1, message = "save preferences failed" })
        return
    end
    build_quick_access({ home_dir = home_dir })

    local preferences = read_preferences()
    local nginx_preferences = read_nginx_preferences()
    for key, value in pairs(nginx_preferences) do
        preferences[key] = value
    end
    local uwsgi_preferences = read_uwsgi_preferences()
    for key, value in pairs(uwsgi_preferences) do
        preferences[key] = value
    end
    local uhttpd_preferences = read_uhttpd_preferences()
    for key, value in pairs(uhttpd_preferences) do
        preferences[key] = value
    end
    preferences.web_server = web_server
    preferences.nginx_running = web_server == "nginx"
    preferences.fcm = is_fanchmwrt_system()

    write_json({
        code = 0,
        message = "success",
        data = preferences
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
    local available, total, operation_space_margin = get_directory_space_info(path)
    local has_operation_space = available ~= nil and available >= (operation_space_margin or 0)
    available = available or 0
    total = total or 0
    operation_space_margin = operation_space_margin or 0

    write_json({
        code = 0,
        message = "success",
        data = {
            path = path,
            parent = parent_path(path),
            available_bytes = available,
            total_bytes = total,
            operation_space_margin = operation_space_margin,
            has_operation_space = has_operation_space,
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
            data = { available_bytes = available, required_bytes = 0 }
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
            data = { available_bytes = available, required_bytes = 0 }
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
            data = { available_bytes = available, required_bytes = required or 0 }
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
                data = { available_bytes = available, required_bytes = required or 0 }
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
            data = { available_bytes = available, required_bytes = required or required_size }
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

function archive.task_id()
    return string.format("%s-%d", tostring(math.floor(video_now_ms() or 0)), math.floor(os.time() % 100000))
end

function archive.read_state()
    local state = read_json_file(archive.state_file)
    if not state then
        return nil
    end
    if (state.state == "pending" or state.state == "running") and not task_process_running(state.pid) then
        state.state = "failed"
        state.done = true
        state.success = false
        state.message = _("Archive task ended unexpectedly")
        state.finished_at = state.finished_at or current_timestamp()
        state.exit_code = state.exit_code or -1
        write_json_file(archive.state_file, state)
    end
    return state
end

function archive.write_state(state)
    return write_json_file(archive.state_file, state)
end

function archive.response(state)
    return {
        task_id = state.task_id,
        state = state.state,
        mode = state.mode,
        done = state.done == true,
        success = state.success == true,
        message = state.message or "",
        exit_code = state.exit_code,
        format = state.format,
        path = state.path,
        output_path = state.output_path,
        destination_path = state.destination_path,
        source_count = state.source_count,
        started_at = state.started_at,
        finished_at = state.finished_at,
        log = read_log_file(archive.log_file, archive.log_limit)
    }
end

function archive.file_name(path)
    return tostring(path or ""):match("([^/]+)$") or ""
end

function archive.detect_extract_format(path)
    local name = archive.file_name(path):lower()
    if name:match("%.tar%.gz$") then
        return "tar.gz"
    end
    if name:match("%.tgz$") then
        return "tgz"
    end
    if name:match("%.tar$") then
        return "tar"
    end
    if name:match("%.zip$") then
        return "zip"
    end
    if name:match("%.gz$") then
        return "gz"
    end
    return nil
end

function archive.strip_suffix(name, format)
    local lower = tostring(name or ""):lower()
    local value = tostring(name or "")
    local suffixes = {
        ["tar.gz"] = ".tar.gz",
        tgz = ".tgz",
        tar = ".tar",
        zip = ".zip",
        gz = ".gz"
    }
    local suffix = suffixes[format]
    if suffix and lower:sub(-#suffix) == suffix then
        return value:sub(1, #value - #suffix)
    end
    return value
end

function archive.ensure_extension(name, format)
    local info = archive.create_formats[format]
    local output_name = tostring(name or "")
    local lower = output_name:lower()
    if info and info.extension and lower:sub(-#info.extension) ~= info.extension then
        output_name = output_name .. info.extension
    end
    return output_name
end

function archive.source_size_estimate(path)
    local nixio_fs = require "nixio.fs"
    local stat = nixio_fs.lstat(path)
    if not stat then
        return 0
    end
    if stat.type == "reg" then
        return tonumber(stat.size) or 0
    end
    if stat.type ~= "dir" then
        return 0
    end
    local total = 0
    local iterator = nixio_fs.dir(path)
    if not iterator then
        return total
    end
    for name in iterator do
        total = total + archive.source_size_estimate(join_path(path, name))
    end
    return total
end

function archive.source_size(items)
    local total = 0
    for _, item in ipairs(items or {}) do
        total = total + archive.source_size_estimate(item.path)
    end
    return total
end

function archive.create_command(task)
    local format = archive.create_formats[task.format]
    if not format then
        return nil, _("Unsupported archive format")
    end
    local executable = find_executable(format.command)
    if not executable then
        return nil, _("Archive command not found")
    end
    if task.format == "tar.gz" then
        local flag = "-czf"
        local args = { flag, task.output_path, "-C", task.target_dir }
        for _, name in ipairs(task.names or {}) do
            table.insert(args, name)
        end
        return command_to_shell(executable, args)
    end
    return nil, _("Unsupported archive format")
end

function archive.extract_command(task)
    local info = archive.extract_formats[task.format]
    if not info then
        return nil, _("Unsupported archive format")
    end
    local executable = find_executable(info.command)
    if not executable then
        return nil, _("Archive command not found")
    end
    if task.format == "zip" then
        return command_to_shell(executable, { task.path, "-d", task.destination_path })
    end
    if task.format == "tar" or task.format == "tar.gz" or task.format == "tgz" then
        local flag = "-xf"
        if task.format == "tar.gz" or task.format == "tgz" then
            flag = "-xzf"
        end
        return command_to_shell(executable, { flag, task.path, "-C", task.destination_path })
    end
    if task.format == "gz" then
        return command_to_shell(executable, { "-dc", task.path }) .. " > " .. shell_quote(task.destination_path)
    end
    return nil, _("Unsupported archive format")
end

function archive.run_task(task)
    local nixio = require "nixio"
    local nixio_fs = require "nixio.fs"
    task.state = "running"
    task.pid = nixio.getpid()
    task.message = task.mode == "create" and _("Creating archive") or _("Extracting archive")
    archive.write_state(task)
    hb_log(archive.log_file, task.message)

    local command, command_err
    if task.mode == "create" then
        command, command_err = archive.create_command(task)
    else
        command, command_err = archive.extract_command(task)
        if not command_err and task.container and not nixio_fs.mkdir(task.destination_path) then
            command = nil
            command_err = _("Create destination directory failed")
        end
    end

    local exit_code = -1
    if command then
        exit_code = archive.run_shell(command, archive.log_file)
    else
        hb_log(archive.log_file, command_err or "archive command build failed")
    end

    local success = exit_code == 0
    if not success and task.mode == "extract" and task.format == "zip" and exit_code == 1 then
        success = true
        hb_log(archive.log_file, "unzip finished with warnings; treating exit code 1 as success")
    end
    if not success then
        if task.output_path then
            nixio_fs.unlink(task.output_path)
        end
        if task.container and task.destination_path then
            remove_tree(task.destination_path)
        elseif task.mode == "extract" and task.destination_path then
            nixio_fs.unlink(task.destination_path)
        end
    end
    hb_log(archive.log_file, success and "Archive task finished successfully" or ("Archive task failed with code " .. tostring(exit_code)))

    task.state = success and "success" or "failed"
    task.done = true
    task.success = success
    task.exit_code = exit_code
    task.message = success and (task.mode == "create" and _("Archive created successfully") or _("Archive extracted successfully")) or
        (command_err or _("Archive operation failed"))
    task.finished_at = current_timestamp()
    archive.write_state(task)
end

function archive.start_task(task)
    local nixio = require "nixio"
    local pid = nixio.fork()
    if not pid or pid < 0 then
        return nil, "fork archive task failed"
    end
    if pid == 0 then
        pcall(nixio.setsid)
        local ok, err = pcall(archive.run_task, task)
        if not ok then
            task.state = "failed"
            task.done = true
            task.success = false
            task.message = _("Archive operation failed")
            task.exit_code = -1
            task.finished_at = current_timestamp()
            hb_log(archive.log_file, "archive runtime error: " .. tostring(err))
            archive.write_state(task)
        end
        os.exit(0)
    end
    task.pid = pid
    task.state = "running"
    task.message = task.mode == "create" and _("Creating archive") or _("Extracting archive")
    archive.write_state(task)
    return pid
end

function archive.busy_response(current)
    write_json_status(409, "Conflict", {
        code = 1,
        message = _("Another archive task is already running"),
        data = archive.response(current)
    })
end

function archive.start_response(task)
    local nixio_fs = require "nixio.fs"
    hb_log(archive.log_file, "==== Archive task start ====")
    if not archive.write_state(task) then
        write_json_status(500, "Archive Failed", { code = 1, message = _("Archive operation failed") })
        return
    end
    local pid, start_err = archive.start_task(task)
    if not pid then
        task.state = "failed"
        task.done = true
        task.success = false
        task.message = _("Archive operation failed")
        task.exit_code = -1
        task.finished_at = current_timestamp()
        archive.write_state(task)
        write_json_status(500, "Archive Failed", { code = 1, message = start_err or _("Archive operation failed") })
        return
    end
    write_json({ code = 0, message = "success", data = archive.response(task) })
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

function api_archive_create_start()
    local nixio_fs = require "nixio.fs"
    if not validate_write_request() then
        return
    end

    local current = archive.read_state()
    if current and (current.state == "pending" or current.state == "running") and not current.done then
        archive.busy_response(current)
        return
    end

    local paths, parse_err = parse_path_array_param("sources")
    if not paths then
        write_json_status(400, "Bad Request", { code = 1, message = parse_err })
        return
    end

    local format_key = tostring(luci.http.formvalue("format") or ""):lower()
    local format_info = archive.create_formats[format_key]
    if not format_info then
        write_json_status(400, "Bad Request", { code = 1, message = _("Unsupported archive format") })
        return
    end

    local first_path = normalize_path(paths[1])
    local target_dir = first_path and parent_path(first_path) or nil
    target_dir = target_dir and select(1, get_writable_directory(target_dir)) or nil
    if not target_dir then
        write_json_status(400, "Bad Request", { code = 1, message = "invalid target directory" })
        return
    end
    if not system_operations_allowed() and is_system_path(target_dir) then
        return deny_system_operation()
    end

    local items, failed_path, err = validate_batch_sources(paths, "copy", target_dir)
    if not items then
        write_batch_failure(409, "Conflict", err, 0, 0, failed_path)
        return
    end
    for _, item in ipairs(items) do
        if parent_path(item.path) ~= target_dir then
            write_json_status(409, "Conflict", { code = 1, message = _("Archive sources must be in the same directory") })
            return
        end
    end
    if format_info.single_file and (#items ~= 1 or items[1].stat.type ~= "reg") then
        write_json_status(400, "Bad Request", { code = 1, message = _("This archive format only supports one regular file") })
        return
    end

    local output_name = archive.ensure_extension(luci.http.formvalue("output_name"), format_key)
    if not validate_upload_name(output_name) then
        write_json_status(400, "Bad Request", { code = 1, message = "invalid file name" })
        return
    end
    local output_path = join_path(target_dir, output_name)
    if nixio_fs.lstat(output_path) then
        write_json_status(409, "Conflict", { code = 1, message = "target already exists" })
        return
    end

    local required_size = archive.source_size(items)
    local has_space, available, space_err, required = ensure_directory_space(target_dir, required_size)
    if not has_space then
        write_json_status(507, "Insufficient Storage", {
            code = 2,
            message = space_err or insufficient_space_message,
            data = { available_bytes = available, required_bytes = required or required_size }
        })
        return
    end
    if not find_executable(format_info.command) then
        write_json_status(424, "Dependency Required", { code = 2, message = _("Archive command not found"), data = { missing_tool = format_info.command } })
        return
    end

    local names = {}
    local sources = {}
    for _, item in ipairs(items) do
        table.insert(names, item.name)
        table.insert(sources, item.path)
    end
    local task = {
        task_id = archive.task_id(),
        mode = "create",
        state = "pending",
        done = false,
        success = false,
        message = _("Preparing archive"),
        exit_code = nil,
        format = format_key,
        target_dir = target_dir,
        output_path = output_path,
        names = names,
        sources = sources,
        source_count = #sources,
        started_at = current_timestamp(),
        finished_at = nil,
        pid = nil
    }
    archive.start_response(task)
end

function api_archive_extract_start()
    local nixio_fs = require "nixio.fs"
    if not validate_write_request() then
        return
    end

    local current = archive.read_state()
    if current and (current.state == "pending" or current.state == "running") and not current.done then
        archive.busy_response(current)
        return
    end

    local path = normalize_path(luci.http.formvalue("path"))
    local stat = path and path ~= "/" and nixio_fs.lstat(path) or nil
    local format_key = path and archive.detect_extract_format(path) or nil
    local format_info = format_key and archive.extract_formats[format_key] or nil
    if not path or not stat or stat.type ~= "reg" or not format_info then
        write_json_status(400, "Bad Request", { code = 1, message = _("Unsupported archive format") })
        return
    end

    local target_dir, parent_err = get_writable_directory(parent_path(path))
    if not target_dir then
        write_json_status(403, "Forbidden", { code = 1, message = parent_err or "directory is not writable" })
        return
    end
    if not system_operations_allowed() and is_system_path(target_dir) then
        return deny_system_operation()
    end

    local base_name = archive.file_name(path)
    local destination_name = archive.strip_suffix(base_name, format_key)
    if not destination_name or destination_name == "" or destination_name == "." then
        destination_name = "archive_extract"
    end
    local destination_path = join_path(target_dir, destination_name)
    if nixio_fs.lstat(destination_path) then
        write_json_status(409, "Conflict", { code = 1, message = "target already exists" })
        return
    end

    local has_space, available, space_err, required = ensure_directory_space(target_dir, 0)
    if not has_space then
        write_json_status(507, "Insufficient Storage", {
            code = 2,
            message = space_err or insufficient_space_message,
            data = { available_bytes = available, required_bytes = required or 0 }
        })
        return
    end
    if not find_executable(format_info.command) then
        write_json_status(424, "Dependency Required", { code = 2, message = _("Archive command not found"), data = { missing_tool = format_info.command } })
        return
    end

    local task = {
        task_id = archive.task_id(),
        mode = "extract",
        state = "pending",
        done = false,
        success = false,
        message = _("Preparing archive"),
        exit_code = nil,
        format = format_key,
        path = path,
        destination_path = destination_path,
        container = format_info.container == true,
        source_count = 1,
        started_at = current_timestamp(),
        finished_at = nil,
        pid = nil
    }
    archive.start_response(task)
end

function api_archive_status()
    local task_id = luci.http.formvalue("task_id")
    if type(task_id) ~= "string" or task_id == "" then
        write_json_status(400, "Bad Request", { code = 1, message = _("Invalid task id") })
        return
    end

    local task = archive.read_state()
    if not task or task.task_id ~= task_id then
        write_json_status(404, "Not Found", { code = 1, message = _("Archive task not found") })
        return
    end

    write_json({ code = 0, message = "success", data = archive.response(task) })
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
    hb_log(package_install_log_file, "==== Package install request ====")
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

function api_nginx_install_start()
    local nixio_fs = require "nixio.fs"
    if not validate_write_request() then
        return
    end

    if detect_web_server() == "nginx" then
        write_json({
            code = 0,
            message = "success",
            data = {
                done = true,
                success = true,
                web_server = "nginx"
            }
        })
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

    local installer = detect_nginx_installer()
    if not installer then
        write_json_status(500, "Install Failed", {
            code = 1,
            message = _("Installer command not found")
        })
        return
    end

    local task = create_repository_install_task(nginx_package_name, installer)
    task.activate_nginx = true
    hb_log(package_install_log_file, "==== Nginx install request ====")
    if not write_package_install_state(task) then
        write_json_status(500, "Install Failed", {
            code = 1,
            message = _("Package installation failed")
        })
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
        write_json_status(500, "Install Failed", {
            code = 1,
            message = start_err or _("Package installation failed")
        })
        return
    end

    task.pid = pid
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
    hb_log(thumbnail_task_log_file, "==== Thumbnail task start ====")
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
        hb_log(package_install_log_file, "GraphicsMagick is already installed")
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
    hb_log(package_install_log_file, "==== GraphicsMagick install request ====")
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

function api_terminal_tool_install_start()
    local nixio_fs = require "nixio.fs"
    if not validate_write_request() then
        return
    end

    if find_executable("ttyd") then
        local task = create_repository_install_task(terminal_package_name, detect_package_installer() or "")
        task.state = "success"
        task.done = true
        task.success = true
        task.message = _("ttyd is already installed")
        task.exit_code = 0
        task.finished_at = current_timestamp()
        hb_log(package_install_log_file, "ttyd is already installed")
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

    local task = create_repository_install_task(terminal_package_name, installer)
    hb_log(package_install_log_file, "==== ttyd install request ====")
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
            data = { available_bytes = available, required_bytes = required or 0 }
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
    local stat, err = validate_preview_file(path, "image")
    if not stat then
        write_plain_status(400, "Bad Request", err)
        return
    end

    local fd = io.open(path, "rb")
    if not fd then
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

    while true do
        local data = fd:read(65536)
        if not data or #data == 0 then
            break
        end
        luci.http.write(data)
    end
    fd:close()
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

local video_range_window = 16 * 1024 * 1024

local function build_video_range(file_size, range_value)
    if range_value == "" then
        return 0, file_size - 1, false
    end

    local start_pos, end_pos = parse_range_header(range_value, file_size)
    if start_pos == nil then
        return nil, nil, nil
    end
    if end_pos - start_pos + 1 > video_range_window then
        end_pos = start_pos + video_range_window - 1
    end
    return start_pos, end_pos, true
end

local function ru32(data, pos)
    local a, b, c, d = data:byte(pos, pos + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
end

local function ru64(data, pos)
    return ru32(data, pos) * 4294967296 + ru32(data, pos + 4)
end

local function be32(value)
    local b4 = value % 256
    value = (value - b4) / 256
    local b3 = value % 256
    value = (value - b3) / 256
    local b2 = value % 256
    value = (value - b2) / 256
    return string.char(value % 256, b2, b3, b4)
end

local function be64(value)
    return be32(math.floor(value / 4294967296)) .. be32(value % 4294967296)
end

local mp4_container_boxes = { trak = true, mdia = true, minf = true, stbl = true }

local function patch_moov_offsets(moov_data, shift)
    local patches = {}
    local codecs = {}
    local total_entries = 0
    local function walk(pos, limit)
        while pos + 7 <= limit do
            local size = ru32(moov_data, pos)
            local btype = moov_data:sub(pos + 4, pos + 7)
            local hlen = 8
            if size == 1 then
                if pos + 15 > limit then
                    return false
                end
                size = ru64(moov_data, pos + 8)
                hlen = 16
            elseif size == 0 then
                size = limit - pos + 1
            end
            if size < hlen or pos + size - 1 > limit then
                return false
            end
            if btype == "cmov" then
                return false
            end
            if btype == "stco" or btype == "co64" then
                local width = btype == "stco" and 4 or 8
                local count_pos = pos + hlen + 4
                if count_pos + 3 > limit then
                    return false
                end
                local count = ru32(moov_data, count_pos)
                local entry_pos = count_pos + 4
                if entry_pos + count * width - 1 > pos + size - 1 then
                    return false
                end
                total_entries = total_entries + count
                if total_entries > 1048576 then
                    return false
                end
                local out = {}
                for i = 0, count - 1 do
                    local p = entry_pos + i * width
                    local value = (width == 4 and ru32(moov_data, p) or ru64(moov_data, p)) + shift
                    if width == 4 and value >= 4294967296 then
                        return false
                    end
                    out[i + 1] = width == 4 and be32(value) or be64(value)
                end
                table.insert(patches, { pos = entry_pos, len = count * width, data = table.concat(out) })
            elseif btype == "stsd" then
                if pos + hlen + 15 <= limit then
                    local fourcc = moov_data:sub(pos + hlen + 12, pos + hlen + 15):gsub("[^%w]", "?")
                    table.insert(codecs, fourcc)
                end
            elseif mp4_container_boxes[btype] then
                if not walk(pos + hlen, pos + size - 1) then
                    return false
                end
            end
            pos = pos + size
        end
        return true
    end
    local root_hlen = ru32(moov_data, 1) == 1 and 16 or 8
    if not walk(1 + root_hlen, #moov_data) or #patches == 0 then
        return nil, table.concat(codecs, ",")
    end
    table.sort(patches, function(a, b) return a.pos < b.pos end)
    local pieces = {}
    local last = 1
    for _, patch in ipairs(patches) do
        table.insert(pieces, moov_data:sub(last, patch.pos - 1))
        table.insert(pieces, patch.data)
        last = patch.pos + patch.len
    end
    table.insert(pieces, moov_data:sub(last))
    return table.concat(pieces), table.concat(codecs, ",")
end

local function build_faststart_plan(path, file_size)
    local ext = get_ext(path)
    if ext ~= "mp4" and ext ~= "m4v" and ext ~= "mov" then
        return nil, "skip ext=" .. tostring(ext)
    end
    local fd = io.open(path, "rb")
    if not fd then
        return nil, "skip open_failed"
    end
    local boxes = {}
    local offset = 0
    while offset + 8 <= file_size and #boxes < 32 do
        fd:seek("set", offset)
        local header = fd:read(8)
        if not header or #header < 8 then
            break
        end
        local size = ru32(header, 1)
        local btype = header:sub(5, 8)
        local hlen = 8
        if size == 1 then
            local ext8 = fd:read(8)
            if not ext8 or #ext8 < 8 then
                break
            end
            size = ru64(ext8, 1)
            hlen = 16
        elseif size == 0 then
            size = file_size - offset
        end
        if size < hlen then
            break
        end
        table.insert(boxes, { type = btype, offset = offset, size = size })
        offset = offset + size
    end
    local mdat_off, moov
    for _, box in ipairs(boxes) do
        if box.type == "mdat" and not mdat_off then
            mdat_off = box.offset
        end
        if box.type == "moov" and not moov then
            moov = box
        end
    end
    if not moov or not mdat_off or moov.offset < mdat_off then
        fd:close()
        return nil, "skip layout_ok"
    end
    if moov.size > 16 * 1024 * 1024 then
        fd:close()
        return nil, "skip moov_too_large size=" .. tostring(moov.size)
    end
    fd:seek("set", moov.offset)
    local moov_data = fd:read(moov.size)
    fd:close()
    if not moov_data or #moov_data ~= moov.size then
        return nil, "skip moov_read_failed"
    end
    local patched, codecs = patch_moov_offsets(moov_data, moov.size)
    if not patched then
        return nil, "skip patch_failed codecs=" .. tostring(codecs)
    end
    local segments = {
        { offset = 0, length = mdat_off },
        { data = patched },
        { offset = mdat_off, length = moov.offset - mdat_off }
    }
    local tail_start = moov.offset + moov.size
    if tail_start < file_size then
        table.insert(segments, { offset = tail_start, length = file_size - tail_start })
    end
    return segments, "applied moov_size=" .. tostring(moov.size) .. " mdat_off=" .. tostring(mdat_off) ..
        " codecs=" .. tostring(codecs)
end

local function stream_segments(path, segments, start_pos, total_length)
    local nixio = require "nixio"
    local fd = io.open(path, "rb")
    if not fd then
        return 0, nil, "open file failed", 0
    end
    local remain = total_length
    local skip = start_pos
    local sent = 0
    local first_write_ms
    local mem_floor_kb = 100 * 1024
    local check_step = 4 * 1024 * 1024
    local next_check = check_step
    local waited_ms = 0

    local function push(data)
        luci.http.write(data)
        if not first_write_ms then
            first_write_ms = video_now_ms()
        end
        sent = sent + #data
        remain = remain - #data
        if sent >= next_check then
            next_check = sent + check_step
            local mem_kb = get_available_memory_kb()
            if mem_kb and mem_kb < mem_floor_kb then
                local wait_start = video_now_ms()
                while mem_kb and mem_kb < mem_floor_kb do
                    nixio.nanosleep(0, 200 * 1000000)
                    if video_now_ms() - wait_start > 60000 then
                        return "low memory timeout mem_kb=" .. tostring(mem_kb)
                    end
                    mem_kb = get_available_memory_kb()
                end
                waited_ms = waited_ms + (video_now_ms() - wait_start)
            end
        end
        return nil
    end

    for _, seg in ipairs(segments) do
        if remain <= 0 then
            break
        end
        local seg_len = seg.data and #seg.data or seg.length
        if skip >= seg_len then
            skip = skip - seg_len
        elseif seg.data then
            local piece = seg.data:sub(skip + 1, skip + math.min(remain, seg_len - skip))
            skip = 0
            local err = push(piece)
            if err then
                fd:close()
                return sent, first_write_ms, err, waited_ms
            end
        else
            if not fd:seek("set", seg.offset + skip) then
                fd:close()
                return sent, first_write_ms, "seek file failed", waited_ms
            end
            local seg_remain = math.min(seg_len - skip, remain)
            skip = 0
            while seg_remain > 0 do
                local data = fd:read(math.min(seg_remain, 65536))
                if not data or #data == 0 then
                    fd:close()
                    return sent, first_write_ms, "unexpected end of file", waited_ms
                end
                seg_remain = seg_remain - #data
                local err = push(data)
                if err then
                    fd:close()
                    return sent, first_write_ms, err, waited_ms
                end
            end
        end
    end
    fd:close()
    if remain > 0 then
        return sent, first_write_ms, "unexpected end of file", waited_ms
    end
    return sent, first_write_ms, nil, waited_ms
end

function api_video_check()
    local path = normalize_path(luci.http.formvalue("path"))
    local stat, err = validate_preview_file(path, "video")
    if not stat then
        write_json_status(400, "Bad Request", { code = 1, message = err or "invalid file" })
        return
    end
    local file_size = stat.size or 0
    local range_value = get_request_range()
    local range_supported = range_value ~= ""
    local tmp_available = get_directory_available_bytes("/tmp") or 0
    write_json({
        code = 0,
        message = "success",
        data = {
            range_supported = range_supported,
            tmp_available = tmp_available,
            file_size = file_size,
            playable = range_supported or tmp_available >= file_size
        }
    })
end

function api_video()
    local path = normalize_path(luci.http.formvalue("path"))
    local stat, err = validate_preview_file(path, "video")
    if not stat then
        write_plain_status(400, "Bad Request", err)
        return
    end

    local file_size = stat.size or 0
    if file_size <= 0 then
        write_plain_status(404, "Not Found", "empty file")
        return
    end

    local range_value, range_source = get_request_range()
    if range_value == "" then
        local tmp_available = get_directory_available_bytes("/tmp") or 0
        if tmp_available < file_size then
            write_json_status(507, "Insufficient Storage", {
                code = 2,
                message = _("Web server does not support Range requests and available memory is too small to play this video")
            })
            return
        end
    end
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
        write_plain_status(500, "Internal Server Error", "open file failed")
        return
    end
    fd:close()

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

    if luci.http.getenv("REQUEST_METHOD") ~= "HEAD" then
        local segments
        if range_value == "" then
            local plan_ok, plan_segments = pcall(build_faststart_plan, path, file_size)
            if plan_ok then
                segments = plan_segments
            end
        end
        if not segments then
            segments = { { offset = 0, length = file_size } }
        end
        stream_segments(path, segments, start_pos, content_length)
    end
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

    local target_dir, available, upload_safety_margin, dir_err = get_upload_directory(luci.http.formvalue("target_dir"))
    if not target_dir then
        write_json_status(403, "Forbidden", { code = 1, message = dir_err })
        return
    end
    if not system_operations_allowed() and is_system_path(target_dir) then
        return deny_system_operation()
    end

    upload_safety_margin = upload_safety_margin or 0
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
    local target_dir, available, upload_safety_margin, dir_err = get_upload_directory(params.target_dir)
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
    upload_safety_margin = upload_safety_margin or 0
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
