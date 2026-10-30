local wezterm = require("wezterm")
local config = {}

if wezterm.config_builder then
    config = wezterm.config_builder()
end

-- ================= 窗口尺寸与赛博朋克极简外观 =================
config.initial_cols = 130
config.initial_rows = 28

-- 彻底去除所有系统边框与外框线条（全纯净无边框体验）
config.window_decorations = "NONE"
config.window_close_confirmation = "AlwaysPrompt"

-- 消除标签栏与窗口内部任何分割边框
config.window_frame = {
    border_left_width = '0px',
    border_right_width = '0px',
    border_bottom_height = '0px',
    border_top_height = '0px',
}

-- 赛博轻微透光感（94% 不透明度），既保留深邃霓虹对比度，又有隐约呼吸感
config.window_background_opacity = 0.94

-- 精致均衡的内边距
config.window_padding = {
    left = 12,
    right = 12,
    top = 10,
    bottom = 8,
}

-- 走 XWayland (X11) 模式，彻底杜绝休眠唤醒后输入法焦点脱节问题
config.enable_wayland = false
config.scrollback_lines = 10000

-- ================= 顶部赛博霓虹标签栏 =================
config.enable_tab_bar = true
config.use_fancy_tab_bar = false       -- 采用现代扁平风格
config.tab_bar_at_bottom = false      -- 标签栏顶格担任标题栏
config.tab_max_width = 30
config.hide_tab_bar_if_only_one_tab = false

-- ================= 字体配置 =================
config.font = wezterm.font_with_fallback({
    "JetBrains Mono",
    "Noto Sans Mono",
    "Noto Sans Mono CJK SC",
})
config.font_size = 12.5
config.warn_about_missing_glyphs = false

-- 剪贴板与选取配置
config.selection_word_boundary = " \t\n{}[]()\"'`"

-- ================= 默认启动程序与菜单 =================
config.default_prog = { "bash", "-l" }

config.launch_menu = {
    { label = "bash", args = { "bash", "-l" } },
}

-- ================= ⚡ Synthwave '84 霓虹赛博朋克高对比色彩体系 =================
local CYBER_BG = "#161026"          -- 幽紫深黑底色
local CYBER_TAB_BAR = "#110b1f"     -- 顶部深渊紫栏
local CYBER_ACTIVE_TAB = "#24173d"  -- 激活标签背衬
local CYBER_NEON_PINK = "#ff7edb"   -- 荧光霓虹粉
local CYBER_NEON_CYAN = "#36f3e1"   -- 荧光青绿蓝
local CYBER_NEON_YELLOW = "#fede5d" -- 荧光暖黄
local CYBER_FG = "#f0eafc"          -- 柔白高对比正文

config.colors = {
    background = CYBER_BG,
    foreground = CYBER_FG,
    cursor_bg = CYBER_NEON_PINK,
    cursor_fg = "#ffffff",
    cursor_border = CYBER_NEON_PINK,
    selection_bg = "#492f64",
    selection_fg = "#ffffff",

    -- ANSI 霓虹荧光色盘（优化色彩对比度，杜绝同亮度浅色文字与浅色背景撞色）
    ansi = {
        "#1a1528", -- 黑 (深邃暗底)
        "#fe4450", -- 红 (霓虹赤红)
        "#72f1b8", -- 绿 (高亮薄荷)
        "#fede5d", -- 黄 (高亮电黄)
        "#2563eb", -- 蓝 (鲜明高对比科技蓝，印在绿底背景色块上依然黑白分明)
        "#ff7edb", -- 紫 (霓虹粉紫)
        "#36f3e1", -- 青 (赛博高亮青)
        "#e2daf0", -- 白 (柔和浅灰白)
    },
    brights = {
        "#3c2f58",
        "#ff616d",
        "#88ffc8",
        "#ffea79",
        "#4e93ff", -- 高亮亮蓝
        "#ff94e4",
        "#69fff1",
        "#ffffff",
    },

    tab_bar = {
        background = CYBER_TAB_BAR,
        active_tab = {
            bg_color = CYBER_ACTIVE_TAB,
            fg_color = CYBER_NEON_PINK,
            intensity = "Bold",
        },
        inactive_tab = {
            bg_color = CYBER_TAB_BAR,
            fg_color = "#7c6a99",
        },
        inactive_tab_hover = {
            bg_color = "#1e1333",
            fg_color = CYBER_NEON_CYAN,
        },
        new_tab = {
            bg_color = CYBER_TAB_BAR,
            fg_color = "#7c6a99",
        },
        new_tab_hover = {
            bg_color = "#1e1333",
            fg_color = CYBER_NEON_CYAN,
        },
    },
}

-- ================= 自定义霓虹胶囊 Tab 样式 =================
wezterm.on("format-tab-title", function(tab, tabs, panes, cfg, hover, max_width)
    local title = tab.active_pane.title
    if max_width and #title > max_width - 4 then
        title = wezterm.truncate_right(title, max_width - 6) .. "…"
    end

    local bg = CYBER_TAB_BAR
    local fg = "#7c6a99"
    local indicator = "   "

    if tab.is_active then
        bg = CYBER_ACTIVE_TAB
        fg = CYBER_NEON_PINK
        indicator = " ⚡ "
    elseif hover then
        bg = "#1e1333"
        fg = CYBER_NEON_CYAN
        indicator = " ✦ "
    end

    return {
        { Background = { Color = bg } },
        { Foreground = { Color = fg } },
        { Text = indicator .. title .. "   " },
    }
end)

-- 右上角赛博朋克状态胶囊（显示当前时间与系统标识）
wezterm.on("update-right-status", function(window, pane)
    local time_str = wezterm.strftime("%H:%M")
    window:set_right_status(wezterm.format {
        { Background = { Color = CYBER_TAB_BAR } },
        { Foreground = { Color = CYBER_NEON_CYAN } },
        { Text = "  " .. time_str .. "  " },
        { Background = { Color = CYBER_ACTIVE_TAB } },
        { Foreground = { Color = CYBER_NEON_PINK } },
        { Text = " CYBERPUNK " },
    })
end)

-- ================= 快捷键 =================
config.keys = {
    { key = "Enter", mods = "ALT", action = wezterm.action.ToggleFullScreen },
    { key = "x", mods = "ALT", action = wezterm.action.QuitApplication },
    { key = "L", mods = "CTRL|SHIFT", action = wezterm.action.ShowLauncher },
    { key = "Space", mods = "CTRL|SHIFT", action = wezterm.action.ShowLauncherArgs { flags = "LAUNCH_MENU_ITEMS" } },
    { key = "W", mods = "CTRL|SHIFT", action = wezterm.action.CloseCurrentTab { confirm = false } },

    -- Alt + 1~9 快速切换标签
    { key = '1', mods = 'ALT', action = wezterm.action.ActivateTab(0) },
    { key = '2', mods = 'ALT', action = wezterm.action.ActivateTab(1) },
    { key = '3', mods = 'ALT', action = wezterm.action.ActivateTab(2) },
    { key = '4', mods = 'ALT', action = wezterm.action.ActivateTab(3) },
    { key = '5', mods = 'ALT', action = wezterm.action.ActivateTab(4) },
    { key = '6', mods = 'ALT', action = wezterm.action.ActivateTab(5) },
    { key = '7', mods = 'ALT', action = wezterm.action.ActivateTab(6) },
    { key = '8', mods = 'ALT', action = wezterm.action.ActivateTab(7) },
    { key = '9', mods = 'ALT', action = wezterm.action.ActivateTab(-1) },
    { key = 'Tab', mods = 'CTRL', action = wezterm.action.ActivateTabRelative(1) },
    { key = 'Tab', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTabRelative(-1) },

    -- Delete 键取消选中
    {
        key = 'Delete',
        mods = 'NONE',
        action = wezterm.action_callback(function(window, pane)
            if window:get_selection_text_for_pane(pane) ~= "" then
                window:perform_action(wezterm.action.ClearSelection, pane)
            else
                window:perform_action(wezterm.action.SendKey { key = 'Delete' }, pane)
            end
        end),
    },
}

-- ================= 鼠标交互优化 =================
config.mouse_bindings = {
    -- Ctrl + 左键点击打开链接
    {
        event = { Up = { streak = 1, button = "Left" } },
        mods = "CTRL",
        action = wezterm.action.OpenLinkAtMouseCursor,
    },
    -- 鼠标中键直接关闭当前标签
    {
        event = { Up = { streak = 1, button = "Middle" } },
        mods = "NONE",
        action = wezterm.action.CloseCurrentTab { confirm = false },
    },
    -- 右键交互：有选中时快速复制并清除高亮，无选中时直接粘贴
    {
        event = { Up = { streak = 1, button = "Right" } },
        mods = "NONE",
        action = wezterm.action_callback(function(window, pane)
            local has_selection = window:get_selection_text_for_pane(pane) ~= ""
            if has_selection then
                window:perform_action(wezterm.action.CopyTo("Clipboard"), pane)
                window:perform_action(wezterm.action.ClearSelection, pane)
            else
                window:perform_action(wezterm.action.PasteFrom("Clipboard"), pane)
            end
        end),
    },
}

-- ================= 启动选择终端类型 =================
local STARTUP_CHOICES = {}
local STARTUP_ARGS = {}
for i, item in ipairs(config.launch_menu) do
    local id = "m" .. i
    table.insert(STARTUP_CHOICES, { label = item.label, id = id })
    STARTUP_ARGS[id] = item.args
end

wezterm.on("gui-startup", function(cmd)
    local tab, pane, window = wezterm.mux.spawn_window(cmd or {})

    -- 如果外部指定了工作目录（如文件夹右键打开），直接进入该目录，不弹出选择框
    if cmd and cmd.cwd and cmd.cwd ~= "" then
        return
    end

    local gui = window:gui_window()
    if gui then
        gui:perform_action(wezterm.action.InputSelector {
            title = "选择终端类型",
            choices = STARTUP_CHOICES,
            fuzzy = true,
            action = wezterm.action_callback(function(win, win_pane, id)
                if not id then return end
                local args = STARTUP_ARGS[id]
                if args and (args[1] ~= "bash") then
                    win:perform_action(wezterm.action.SpawnCommandInNewTab { args = args }, win_pane)
                    pane:window():active_tab():activate()
                end
            end),
        }, pane)
    end
end)

-- ================= 标签栏操作 =================
wezterm.on("new-tab-button-click", function(window, pane, button, default_action)
    if button == "Left" then
        if default_action then
            window:perform_action(default_action, pane)
        end
        return false
    elseif button == "Right" then
        -- 右键点击加号呼出启动菜单
        window:perform_action(wezterm.action.ShowLauncherArgs {
            flags = "LAUNCH_MENU_ITEMS"
        }, pane)
        return false
    end
end)

return config
