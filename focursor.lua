local obs = obslua
local VERSION = "0.1.0"

-- FFI安全加载
local ffi = nil
local ffi_loaded = false

local function load_ffi()
    if ffi_loaded then
        return ffi ~= nil
    end
    
    local success, result = pcall(require, "ffi")
    if success then
        ffi = result
        ffi_loaded = true
        return true
    else
        -- 仅在调试模式才输出日志
        ffi_loaded = true
        return false
    end
end

-- ========================================
-- 缩放相关变量
-- ========================================

local source_name = ""  -- 用户设置的源名称/模式
local source_name_current = ""  -- 当前场景中实际使用的源名称
local source = nil
local sceneitem = nil
local sceneitem_info_orig = nil
local sceneitem_crop_orig = nil
local sceneitem_info = nil
local sceneitem_crop = nil
local crop_filter = nil
local crop_filter_settings = nil
local crop_filter_info_orig = { x = 0.0, y = 0.0, w = 0.0, h = 0.0 }
local crop_filter_info = { x = 0.0, y = 0.0, w = 0.0, h = 0.0 }  -- 实际值（double精度）
local crop_filter_info_display = { left = 0, top = 0, right = 0, bottom = 0 }  -- 显示值（整数，用于OBS）
local monitor_info = nil
local zoom_info = {
    source_size = { width = 0.0, height = 0.0 },
    source_crop = { x = 0.0, y = 0.0, w = 0.0, h = 0.0 },
    source_crop_filter = { x = 0.0, y = 0.0, w = 0.0, h = 0.0 },
    zoom_to = 2.0
}
local zoom_time = 0
local zoom_target = nil
local virtual_window = nil
local zoom_start_position = nil
local locked_center = nil
local locked_last_pos = nil
local hotkey_zoom_id = nil
local hotkey_follow_id = nil
local is_timer_running = false

local CROP_FILTER_NAME = "smooth-cursor-zoom-crop"

-- ========================================
-- 鼠标指针相关变量
-- ========================================

local cursor_source_name = ""  -- 用户设置的源名称/模式
local cursor_source_name_current = ""  -- 当前场景中实际使用的源名称
local cursor_source = nil
local is_cursor_enabled = false
local cursor_timer_running = false
local hotkey_cursor_id = nil

local current_pos = { x = 0.0, y = 0.0 }
local target_pos = { x = 0.0, y = 0.0 }
local last_mouse_pos = { x = 0.0, y = 0.0 }

local smooth_factor = 0.15
local smooth_factor_clicking = 0.5
local cursor_image_path = ""
local cursor_image_clicking = ""
local cursor_image_dragging = ""
local cursor_scale = 1.0
local click_scale = 1.3
local click_duration = 150
local hotspot_x = 0
local hotspot_y = 0
local click_anchor_x = 0.5
local click_anchor_y = 0.5

local click_start_time = 0
local is_clicking = false
local is_dragging = false
local drag_start_time = 0
local drag_threshold = 100
local current_click_scale = 1.0
local click_animation_active = false

-- 鼠标跟随缩放
local cursor_follow_zoom = true
local cursor_zoom_offset = { x = 0.0, y = 0.0 }

-- 自动缩放功能
local auto_zoom_enabled = false
local auto_zoom_timeout = 3000  -- 自动恢复时间（毫秒）
local auto_zoom_move_threshold = 300  -- 移动阈值（像素）
local auto_zoom_start_time = 0  -- 自动缩放开始时间
local auto_zoom_start_pos = { x = 0.0, y = 0.0 }  -- 自动缩放时的鼠标位置
local auto_zoom_active = false  -- 是否正在自动缩放中
local auto_zoom_was_clicked = false  -- 上一帧是否点击
local auto_zoom_timer_running = false  -- 自动缩放定时器是否运行
local auto_zoom_ready = false  -- 放大完成，准备开始计时/检测移动
local auto_zoom_threshold_strategy = "wait_complete"  -- 阈值检测策略: immediate 或 wait_complete
local auto_zoom_center_follow_on_click = true  -- 点击时是否设置/更新基准点
local auto_zoom_center_follow_on_longpress = false  -- 长按时是否更新基准点

-- ========================================
-- 配置变量
-- ========================================

local use_auto_follow_mouse = true
local use_follow_outside_bounds = false
local is_following_mouse = false
local follow_speed = 0.25
local follow_border = 8
local follow_safezone_sensitivity = 4
local use_follow_auto_lock = false
local zoom_value = 2
local zoom_speed_in = 0.25  -- 放大速度
local zoom_speed_out = 0.25 -- 缩小速度
local zoom_ease_in_type = "EaseInOut"
local zoom_ease_out_type = "EaseInOut"
local zoom_custom_ease_in_expr = "t * t"
local zoom_custom_ease_out_expr = "t * (2 - t)"

local allow_all_sources = false
local use_monitor_override = false
local monitor_override_x = 0
local monitor_override_y = 0
local monitor_override_w = 1920
local monitor_override_h = 1080
local monitor_override_sx = 1
local monitor_override_sy = 1
local monitor_override_dw = 1920
local monitor_override_dh = 1080
local debug_logs = false
local is_obs_loaded = false

local ZoomState = {
    None = 0,
    ZoomingIn = 1,
    ZoomingOut = 2,
    ZoomedIn = 3,
}
local zoom_state = ZoomState.None

-- Windows API
local win_api_available = false
local win_point = nil

-- ========================================
-- 日志函数
-- ========================================

function log(msg)
    if debug_logs then
        obs.script_log(obs.OBS_LOG_INFO, msg)
    end
end

-- ========================================
-- Windows API 初始化
-- ========================================

local function init_windows_api()
    if not load_ffi() then
        return false
    end
    
    if ffi.os ~= "Windows" then
        return false
    end
    
    local success, error_msg = pcall(function()
        ffi.cdef([[
            typedef int BOOL;
            typedef unsigned short WORD;
            typedef short SHORT;
            typedef struct {
                long x;
                long y;
            } POINT, *LPPOINT;
            
            BOOL GetCursorPos(LPPOINT);
            WORD GetKeyState(int nVirtKey);
            SHORT GetAsyncKeyState(int vKey);
        ]])
        
        win_point = ffi.new("POINT[1]")
    end)
    
    if success then
        win_api_available = true
        log("Windows API initialized successfully")
    else
        log("Failed to initialize Windows API: " .. tostring(error_msg))
    end
    
    return win_api_available
end

-- ========================================
-- 鼠标位置获取
-- ========================================

function get_mouse_pos()
    local mouse = { x = 0, y = 0 }
    
    if not win_api_available or not ffi or not win_point then
        return mouse
    end
    
    local success, result = pcall(function()
        if ffi.C.GetCursorPos(win_point) ~= 0 then
            return { x = win_point[0].x, y = win_point[0].y }
        end
        return mouse
    end)
    
    if success then
        return result
    else
        return mouse
    end
end

function is_mouse_clicked()
    if not win_api_available or not ffi then
        return false
    end
    
    local success, result = pcall(function()
        -- GetAsyncKeyState 检查物理按键状态，比 GetKeyState 更适合长跑脚本
        -- 返回值是一个 16 位有符号数，最高位 (bit 15) 为 1 表示按键当前处于按下状态
        local left_down = ffi.C.GetAsyncKeyState(0x01) < 0
        local right_down = ffi.C.GetAsyncKeyState(0x02) < 0
        return left_down or right_down
    end)
    
    return success and result or false
end

-- ========================================
-- 数学工具函数 & 缓动函数
-- ========================================

function lerp(v0, v1, t)
    return v0 * (1 - t) + v1 * t
end

function clamp(min, max, value)
    return math.max(min, math.min(max, value))
end

-- 获取当前时间（毫秒），使用 64 位高性能计数器代替 os.clock，避免长寿命脚本溢出或 CPU 时间漂移
function get_time_ms()
    -- obs.os_gettime_ns() 返回纳秒，除以 1000000 得到毫秒
    return obs.os_gettime_ns() / 1000000
end

-- 缓动函数集合
local Easing = {
    Linear = function(t) return t end,
    EaseIn = function(t) return t * t end,
    EaseOut = function(t) return t * (2 - t) end,
    EaseInOut = function(t) 
        if t < 0.5 then return 2 * t * t else return -1 + (4 - 2 * t) * t end 
    end,
    EaseInCubic = function(t) return t * t * t end,
    EaseOutCubic = function(t) return 1 - math.pow(1 - t, 3) end,
    EaseInOutCubic = function(t) 
        if t < 0.5 then return 4 * t * t * t else return 1 - math.pow(-2 * t + 2, 3) / 2 end 
    end,
    EaseInQuart = function(t) return t * t * t * t end,
    EaseOutQuart = function(t) return 1 - math.pow(1 - t, 4) end,
    EaseInOutQuart = function(t) 
        if t < 0.5 then return 8 * t * t * t * t else return 1 - math.pow(-2 * t + 2, 4) / 2 end
    end,
    EaseOutElastic = function(t)
        local c4 = (2 * math.pi) / 3
        if t == 0 then return 0 end
        if t == 1 then return 1 end
        return math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * c4) + 1
    end,
    EaseOutBack = function(t)
        local c1 = 1.70158
        local c3 = c1 + 1
        return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
    end,
    EaseOutBounce = function(t)
        local n1 = 7.5625
        local d1 = 2.75
        if t < 1 / d1 then
            return n1 * t * t
        elseif t < 2 / d1 then
            t = t - 1.5 / d1
            return n1 * t * t + 0.75
        elseif t < 2.5 / d1 then
            t = t - 2.25 / d1
            return n1 * t * t + 0.9375
        else
            t = t - 2.625 / d1
            return n1 * t * t + 0.984375
        end
    end
}

-- 编译自定义函数
local custom_ease_in_func = function(t) return t end
local custom_ease_out_func = function(t) return t end

function create_custom_easing(expr_str)
    -- 尝试编译用户输入的表达式
    -- 包装在一个接受 t 的函数中，并自动 clamp 结果
    local chunk_str = [[
        return function(t) 
            local val = (function() return ]] .. expr_str .. [[ end)()
            if type(val) ~= "number" then return t end
            return math.max(0, math.min(1, val))
        end
    ]]
    
    local chunk, err = load(chunk_str)
    if not chunk then
        log("自定义缓动函数编译错误: " .. tostring(err))
        return function(t) return t end
    end
    
    local success, func = pcall(chunk)
    if not success or type(func) ~= "function" then
        log("自定义缓动函数加载失败")
        return function(t) return t end
    end
    
    return func
end

function get_easing_function(name, is_in)
    if name == "Custom" then
        return is_in and custom_ease_in_func or custom_ease_out_func
    end
    return Easing[name] or Easing.EaseInOut
end

-- 兼容旧代码引用
function ease_in_out(t) return Easing.EaseInOutCubic(t) end
function ease_out_cubic(t) return Easing.EaseOutCubic(t) end

-- ========================================
-- 监视器信息
-- ========================================

function get_monitor_info(src)
    local info = nil

    if use_monitor_override then
        info = {
            x = monitor_override_x,
            y = monitor_override_y,
            width = monitor_override_w,
            height = monitor_override_h,
            scale_x = monitor_override_sx,
            scale_y = monitor_override_sy,
            display_width = monitor_override_dw,
            display_height = monitor_override_dh
        }
    elseif src ~= nil then
        local width = obs.obs_source_get_width(src)
        local height = obs.obs_source_get_height(src)
        
        if width > 0 and height > 0 then
            info = {
                x = 0,
                y = 0,
                width = width,
                height = height,
                scale_x = 1,
                scale_y = 1,
                display_width = width,
                display_height = height
            }
        end
    end

    if not info then
        log("WARNING: Could not auto calculate zoom source position and size.")
    end

    return info
end

-- ========================================
-- 缩放功能
-- ========================================

function release_sceneitem()
    if is_timer_running then
        obs.timer_remove(on_timer)
        is_timer_running = false
    end

    zoom_state = ZoomState.None
    virtual_window = nil
    zoom_start_position = nil
    
    -- 重置显示值缓存
    crop_filter_info_display = { left = 0, top = 0, right = 0, bottom = 0 }

    if sceneitem ~= nil then
        -- 不再使用裁剪滤镜，无需移除
        crop_filter = nil
        crop_filter_settings = nil

        if sceneitem_info_orig ~= nil then
            obs.obs_sceneitem_set_info(sceneitem, sceneitem_info_orig)
            sceneitem_info_orig = nil
        end

        if sceneitem_crop_orig ~= nil then
            obs.obs_sceneitem_set_crop(sceneitem, sceneitem_crop_orig)
            sceneitem_crop_orig = nil
        end

        obs.obs_sceneitem_release(sceneitem)
        sceneitem = nil
    end

    if source ~= nil then
        obs.obs_source_release(source)
        source = nil
    end
end

function set_crop_settings(crop)
    -- 使用场景项裁剪和缩放来实现放大效果，而不是使用裁剪滤镜
    -- 内部保持双精度浮点数用于计算，只在最后向OBS传递时四舍五入
    if sceneitem == nil or sceneitem_info_orig == nil then return end
    if zoom_info.source_size.width <= 0 or zoom_info.source_size.height <= 0 then return end
    
    local orig_width = zoom_info.source_size.width
    local orig_height = zoom_info.source_size.height
    
    -- 计算裁剪边距（场景项裁剪使用 left, top, right, bottom 边距）
    -- 直接从浮点数计算，然后向上取整，以保持最终显示值的一致性
    local crop_left_float = crop.x
    local crop_top_float = crop.y
    local crop_right_float = orig_width - crop.x - crop.w
    local crop_bottom_float = orig_height - crop.y - crop.h
    
    -- 向上取整到整数（显示值）
    local crop_left = math.ceil(crop_left_float)
    local crop_top = math.ceil(crop_top_float)
    local crop_right = math.ceil(crop_right_float)
    local crop_bottom = math.ceil(crop_bottom_float)
    
    -- 只在实际值改变时才更新OBS
    if crop_filter_info_display.left ~= crop_left or 
       crop_filter_info_display.top ~= crop_top or 
       crop_filter_info_display.right ~= crop_right or 
       crop_filter_info_display.bottom ~= crop_bottom then
        
        crop_filter_info_display.left = crop_left
        crop_filter_info_display.top = crop_top
        crop_filter_info_display.right = crop_right
        crop_filter_info_display.bottom = crop_bottom
        
        -- 设置场景项裁剪
        local new_crop = obs.obs_sceneitem_crop()
        new_crop.left = crop_left
        new_crop.top = crop_top
        new_crop.right = crop_right
        new_crop.bottom = crop_bottom
        obs.obs_sceneitem_set_crop(sceneitem, new_crop)
        
        -- 计算缩放比例：原始尺寸 / 裁剪后尺寸
        -- 重要：必须基于取整后的裁剪值计算，确保裁剪和缩放完全一致
        local cropped_width = orig_width - crop_left - crop_right
        local cropped_height = orig_height - crop_top - crop_bottom
        
        -- 防止除以零
        if cropped_width <= 0 or cropped_height <= 0 then return end
        
        local scale_x = orig_width / cropped_width
        local scale_y = orig_height / cropped_height
        
        -- 获取当前变换信息并更新缩放
        local new_info = obs.obs_transform_info()
        obs.obs_sceneitem_get_info(sceneitem, new_info)
        
        -- 应用新的缩放（原始缩放 * 放大倍数）
        new_info.scale.x = sceneitem_info_orig.scale.x * scale_x
        new_info.scale.y = sceneitem_info_orig.scale.y * scale_y
        
        obs.obs_sceneitem_set_info(sceneitem, new_info)
    end
end

-- ========================================
-- 缩放源查找函数（支持模式匹配）
-- ========================================

-- 在当前场景中查找匹配模式的缩放源
-- 模式匹配规则：
-- 1. 精确匹配：source_name
-- 2. 带场景名后缀：source_name_<场景名>
-- 3. 带任意后缀：source_name_*
function find_zoom_source_in_scene()
    local scene_source = obs.obs_frontend_get_current_scene()
    if not scene_source then
        return nil
    end
    
    local scene = obs.obs_scene_from_source(scene_source)
    if not scene then
        obs.obs_source_release(scene_source)
        return nil
    end
    
    local scene_name = obs.obs_source_get_name(scene_source)
    local found_name = nil
    
    -- 如果 source_name 不为空，使用原有的模式匹配逻辑
    if source_name ~= "" then
        -- 优先级1：精确匹配 source_name
        local item = obs.obs_scene_find_source(scene, source_name)
        if item then
            found_name = source_name
        end
        
        -- 优先级2：尝试 source_name_<场景名>
        if not found_name and scene_name then
            local scene_specific_name = source_name .. "_" .. scene_name
            item = obs.obs_scene_find_source(scene, scene_specific_name)
            if item then
                found_name = scene_specific_name
            end
        end
        
        -- 优先级3：遍历场景查找以 source_name 开头的源
        if not found_name then
            local items = obs.obs_scene_enum_items(scene)
            if items then
                for _, scene_item in ipairs(items) do
                    local item_source = obs.obs_sceneitem_get_source(scene_item)
                    if item_source then
                        local item_name = obs.obs_source_get_name(item_source)
                        -- 检查是否以 source_name 开头
                        if item_name and string.sub(item_name, 1, #source_name) == source_name then
                            found_name = item_name
                            break
                        end
                    end
                end
                obs.sceneitem_list_release(items)
            end
        end
    else
        -- source_name 为空，自动选择第一个窗口/显示器采集源
        local items = obs.obs_scene_enum_items(scene)
        if items then
            for _, scene_item in ipairs(items) do
                local item_source = obs.obs_sceneitem_get_source(scene_item)
                if item_source then
                    local item_name = obs.obs_source_get_name(item_source)
                    local source_id = obs.obs_source_get_id(item_source)
                    
                    -- 检查是否是窗口/显示器采集源
                    if source_id == "monitor_capture" or source_id == "display_capture" or source_id == "window_capture" then
                        found_name = item_name
                        break
                    end
                end
            end
            obs.sceneitem_list_release(items)
        end
    end
    
    obs.obs_source_release(scene_source)
    return found_name
end

function get_target_position(zoom)
    local mouse = get_mouse_pos()

    if monitor_info then
        mouse.x = mouse.x - monitor_info.x
        mouse.y = mouse.y - monitor_info.y
    end

    mouse.x = mouse.x - zoom.source_crop_filter.x
    mouse.y = mouse.y - zoom.source_crop_filter.y

    if monitor_info and monitor_info.scale_x and monitor_info.scale_y then
        mouse.x = mouse.x * monitor_info.scale_x
        mouse.y = mouse.y * monitor_info.scale_y
    end

    local new_size = {
        width = zoom.source_size.width / zoom.zoom_to,
        height = zoom.source_size.height / zoom.zoom_to
    }

    local pos = {
        x = mouse.x - new_size.width * 0.5,
        y = mouse.y - new_size.height * 0.5
    }

    local crop = {
        x = pos.x,
        y = pos.y,
        w = new_size.width,
        h = new_size.height,
    }

    crop.x = clamp(0.0, (zoom.source_size.width - new_size.width), crop.x)
    crop.y = clamp(0.0, (zoom.source_size.height - new_size.height), crop.y)

    return { crop = crop, raw_center = mouse, clamped_center = { x = crop.x + crop.w * 0.5, y = crop.y + crop.h * 0.5 } }
end

function refresh_sceneitem(find_newest)
    if find_newest then
        release_sceneitem()

        -- 使用模式匹配查找缩放源（包括空名称时的自动选择）
        local found_name = find_zoom_source_in_scene()
        if not found_name then
            local mode_desc = source_name == "" and "自动选择模式" or ("模式: " .. source_name)
            log("未找到匹配的缩放源 (" .. mode_desc .. ")")
            return
        end
        
        source_name_current = found_name
        log("Finding sceneitem for Zoom Source '" .. source_name_current .. "'")
        
        source = obs.obs_get_source_by_name(source_name_current)
        if source == nil then
            log("Source not found: " .. source_name_current)
            return
        end

        local scene_source = obs.obs_frontend_get_current_scene()
        if scene_source then
            local scene = obs.obs_scene_from_source(scene_source)
            if scene then
                local item = obs.obs_scene_find_source(scene, source_name_current)
                if item then
                    sceneitem = item
                    obs.obs_sceneitem_addref(sceneitem)
                end
            end
            obs.obs_source_release(scene_source)
        end
    end

    if not monitor_info then
        monitor_info = get_monitor_info(source)
    end

    if sceneitem ~= nil then
        sceneitem_info_orig = obs.obs_transform_info()
        obs.obs_sceneitem_get_info(sceneitem, sceneitem_info_orig)
        
        -- 如果场景项设置了边界框，需要临时禁用，否则裁剪后OBS会自动缩放场景项
        if sceneitem_info_orig.bounds_type ~= obs.OBS_BOUNDS_NONE then
            local new_info = obs.obs_transform_info()
            obs.obs_sceneitem_get_info(sceneitem, new_info)
            new_info.bounds_type = obs.OBS_BOUNDS_NONE
            obs.obs_sceneitem_set_info(sceneitem, new_info)
            log("禁用场景项边界框以防止自动缩放")
        end

        sceneitem_crop_orig = obs.obs_sceneitem_crop()
        obs.obs_sceneitem_get_crop(sceneitem, sceneitem_crop_orig)

        local width = obs.obs_source_get_width(source)
        local height = obs.obs_source_get_height(source)

        zoom_info.source_size.width = width
        zoom_info.source_size.height = height
        zoom_info.source_crop.x = sceneitem_crop_orig.left
        zoom_info.source_crop.y = sceneitem_crop_orig.top
        zoom_info.source_crop.w = sceneitem_crop_orig.right
        zoom_info.source_crop.h = sceneitem_crop_orig.bottom
        zoom_info.source_crop_filter = { x = 0.0, y = 0.0, w = 0.0, h = 0.0 }

        -- 不再使用裁剪滤镜，改用场景项裁剪+缩放
        crop_filter = nil
        crop_filter_settings = nil

        crop_filter_info = {
            x = 0.0,
            y = 0.0,
            w = (width + 0.0),
            h = (height + 0.0)
        }
        crop_filter_info_orig = {
            x = 0.0,
            y = 0.0,
            w = (width + 0.0),
            h = (height + 0.0)
        }

        log("Zoom source initialized: " .. width .. "x" .. height)
    end
end

-- ========================================
-- on_timer (阻尼追踪模式)
-- ========================================

-- 阈值：当差距小于此值时认为动画完成
local ZOOM_THRESHOLD = 0.5

function on_timer()
    if crop_filter_info == nil then return end
    
    -- 确定当前阻尼系数（速度）
    local damping = zoom_speed_in
    if zoom_state == ZoomState.ZoomingOut then
        damping = zoom_speed_out
    end
    
    -- 确定目标裁剪区域
    local target_crop = nil
    
    if zoom_state == ZoomState.ZoomingOut then
        -- 缩小：目标是原始大小
        target_crop = {
            x = crop_filter_info_orig.x or 0,
            y = crop_filter_info_orig.y or 0,
            w = zoom_info.source_size.width,
            h = zoom_info.source_size.height
        }
    elseif zoom_state == ZoomState.ZoomingIn then
        -- 放大：计算目标位置
        local temp_zoom_info = {
            source_size = zoom_info.source_size,
            source_crop_filter = zoom_info.source_crop_filter,
            zoom_to = zoom_info.zoom_to
        }
        local pos_info = get_target_position(temp_zoom_info)
        target_crop = pos_info.crop
    elseif zoom_state == ZoomState.ZoomedIn then
        -- 已放大：跟随鼠标
        if is_following_mouse then
            zoom_target = get_target_position(zoom_info)

            local skip_frame = false
            if not use_follow_outside_bounds then
                if zoom_target.raw_center.x < zoom_target.crop.x or
                    zoom_target.raw_center.x > zoom_target.crop.x + zoom_target.crop.w or
                    zoom_target.raw_center.y < zoom_target.crop.y or
                    zoom_target.raw_center.y > zoom_target.crop.y + zoom_target.crop.h then
                    skip_frame = true
                end
            end

            if not skip_frame then
                if locked_center ~= nil then
                    local diff = {
                        x = zoom_target.raw_center.x - locked_center.x,
                        y = zoom_target.raw_center.y - locked_center.y
                    }

                    local track = {
                        x = zoom_target.crop.w * (0.5 - (follow_border * 0.01)),
                        y = zoom_target.crop.h * (0.5 - (follow_border * 0.01))
                    }

                    if math.abs(diff.x) > track.x or math.abs(diff.y) > track.y then
                        locked_center = nil
                        locked_last_pos = {
                            x = zoom_target.raw_center.x,
                            y = zoom_target.raw_center.y,
                            diff_x = diff.x,
                            diff_y = diff.y
                        }
                    end
                end

                if locked_center == nil and (zoom_target.crop.x ~= crop_filter_info.x or zoom_target.crop.y ~= crop_filter_info.y) then
                    crop_filter_info.x = lerp(crop_filter_info.x, zoom_target.crop.x, follow_speed)
                    crop_filter_info.y = lerp(crop_filter_info.y, zoom_target.crop.y, follow_speed)
                    set_crop_settings(crop_filter_info)

                    if is_following_mouse and locked_center == nil and locked_last_pos ~= nil then
                        local diff = {
                            x = math.abs(crop_filter_info.x - zoom_target.crop.x),
                            y = math.abs(crop_filter_info.y - zoom_target.crop.y),
                            auto_x = zoom_target.raw_center.x - locked_last_pos.x,
                            auto_y = zoom_target.raw_center.y - locked_last_pos.y
                        }

                        locked_last_pos.x = zoom_target.raw_center.x
                        locked_last_pos.y = zoom_target.raw_center.y

                        local lock = false
                        if math.abs(locked_last_pos.diff_x) > math.abs(locked_last_pos.diff_y) then
                            if (diff.auto_x < 0 and locked_last_pos.diff_x > 0) or (diff.auto_x > 0 and locked_last_pos.diff_x < 0) then
                                lock = true
                            end
                        else
                            if (diff.auto_y < 0 and locked_last_pos.diff_y > 0) or (diff.auto_y > 0 and locked_last_pos.diff_y < 0) then
                                lock = true
                            end
                        end

                        if (lock and use_follow_auto_lock) or (diff.x <= follow_safezone_sensitivity and diff.y <= follow_safezone_sensitivity) then
                            locked_center = {
                                x = math.floor(crop_filter_info.x + zoom_target.crop.w * 0.5),
                                y = math.floor(crop_filter_info.y + zoom_target.crop.h * 0.5)
                            }
                            log("Cursor stopped. Tracking locked to " .. locked_center.x .. ", " .. locked_center.y)
                        end
                    end
                end
            end
        end
        return  -- ZoomedIn 状态不需要后续动画完成检测
    else
        return  -- None 状态
    end
    
    if target_crop == nil then return end
    
    -- 阻尼追踪：每帧向目标逼近
    crop_filter_info.x = lerp(crop_filter_info.x, target_crop.x, damping)
    crop_filter_info.y = lerp(crop_filter_info.y, target_crop.y, damping)
    crop_filter_info.w = lerp(crop_filter_info.w, target_crop.w, damping)
    crop_filter_info.h = lerp(crop_filter_info.h, target_crop.h, damping)
    set_crop_settings(crop_filter_info)
    
    -- 检查是否到达目标（阈值判断）
    local dx = math.abs(crop_filter_info.x - target_crop.x)
    local dy = math.abs(crop_filter_info.y - target_crop.y)
    local dw = math.abs(crop_filter_info.w - target_crop.w)
    local dh = math.abs(crop_filter_info.h - target_crop.h)
    
    -- 对于 ZoomingIn：只检查尺寸是否到达目标（允许位置继续跟随鼠标）
    -- 对于 ZoomingOut：需要位置和尺寸都到达目标
    local size_reached = (dw < ZOOM_THRESHOLD and dh < ZOOM_THRESHOLD)
    local position_reached = (dx < ZOOM_THRESHOLD and dy < ZOOM_THRESHOLD)
    local animation_complete = false
    
    if zoom_state == ZoomState.ZoomingIn then
        -- 放大时：尺寸到达目标即可认为放大完成，位置会继续跟随
        animation_complete = size_reached
    else
        -- 缩小时：需要尺寸和位置都到达
        animation_complete = size_reached and position_reached
    end
    
    if animation_complete then
        local should_stop_timer = false
        
        if zoom_state == ZoomState.ZoomingOut then
            -- 缩小完成，精确设置到目标值
            crop_filter_info.x = target_crop.x
            crop_filter_info.y = target_crop.y
            crop_filter_info.w = target_crop.w
            crop_filter_info.h = target_crop.h
            set_crop_settings(crop_filter_info)
            
            log("Zoomed out")
            zoom_state = ZoomState.None
            virtual_window = nil
            zoom_start_position = nil
            should_stop_timer = true
        elseif zoom_state == ZoomState.ZoomingIn then
            -- 放大完成（尺寸到达目标），切换到 ZoomedIn 状态
            -- 注意：不精确设置位置，因为位置会继续跟随鼠标
            crop_filter_info.w = target_crop.w
            crop_filter_info.h = target_crop.h
            set_crop_settings(crop_filter_info)
            
            log("Zoomed in")
            zoom_state = ZoomState.ZoomedIn
            virtual_window = nil
            zoom_start_position = nil
            should_stop_timer = (not use_auto_follow_mouse) and (not is_following_mouse)

            if use_auto_follow_mouse then
                is_following_mouse = true
                log("Tracking mouse is " .. (is_following_mouse and "on" or "off") .. " (due to auto follow)")
            end

            if is_following_mouse and follow_border < 50 then
                zoom_target = get_target_position(zoom_info)
                locked_center = { x = zoom_target.clamped_center.x, y = zoom_target.clamped_center.y }
                log("Cursor stopped. Tracking locked to " .. locked_center.x .. ", " .. locked_center.y)
            end
        end

        if should_stop_timer then
            is_timer_running = false
            obs.timer_remove(on_timer)
        end
    end
end

-- ========================================
-- 热键回调
-- ========================================

function on_toggle_follow(pressed)
    if pressed then
        is_following_mouse = not is_following_mouse
        log("Tracking mouse is " .. (is_following_mouse and "on" or "off"))

        if is_following_mouse and zoom_state == ZoomState.ZoomedIn then
            if is_timer_running == false then
                is_timer_running = true
                local timer_interval = math.floor(obs.obs_get_frame_interval_ns() / 1000000)
                obs.timer_add(on_timer, timer_interval)
            end
        end
    end
end

function on_toggle_zoom(pressed)
    if pressed then
        -- 允许在任何状态（包括动画中）切换
        if zoom_state == ZoomState.ZoomedIn or zoom_state == ZoomState.ZoomingIn then
            -- 正在放大或已放大 -> 开始缩小
            zoom_state = ZoomState.ZoomingOut
            locked_center = nil
            locked_last_pos = nil
            if is_following_mouse then
                is_following_mouse = false
            end
            log("Switching to zoom out")
        elseif zoom_state == ZoomState.None or zoom_state == ZoomState.ZoomingOut then
            -- 未放大或正在缩小 -> 开始放大
            if sceneitem == nil then
                refresh_sceneitem(true)
                if sceneitem == nil then
                    local mode_desc = source_name == "" and "自动选择模式" or ("模式: " .. source_name)
                    log("无法找到缩放源 (" .. mode_desc .. ")")
                    return
                end
            end
            
            zoom_state = ZoomState.ZoomingIn
            zoom_info.zoom_to = zoom_value
            locked_center = nil
            locked_last_pos = nil
            log("Switching to zoom in, source: " .. (source_name_current or source_name))
        end

        if is_timer_running == false then
            is_timer_running = true
            local timer_interval = math.floor(obs.obs_get_frame_interval_ns() / 1000000)
            obs.timer_add(on_timer, timer_interval)
        end
    end
end

-- ========================================
-- 点击动画和拖动检测
-- ========================================

function update_click_animation()
    local mouse_clicked = is_mouse_clicked()
    local current_time = get_time_ms()
    
    -- 检测拖动状态（按住超过阈值时间）
    if mouse_clicked then
        if not is_clicking then
            is_clicking = true
            click_start_time = current_time
            drag_start_time = current_time
            click_animation_active = true
            is_dragging = false
        elseif not is_dragging and (current_time - drag_start_time) > drag_threshold then
            is_dragging = true
        end
    else
        if is_clicking then
            is_clicking = false
            is_dragging = false
            click_start_time = current_time
        end
    end
    
    -- click_duration 为 0 时禁用动画
    if click_duration <= 0 then
        if mouse_clicked then
            current_click_scale = click_scale
        else
            current_click_scale = 1.0
        end
        return
    end
    
    local half_duration = click_duration * 0.5
    
    if mouse_clicked then
        local elapsed = current_time - click_start_time
        local progress = math.min(elapsed / half_duration, 1.0)
        local eased = ease_out_cubic(progress)
        -- 从 1.0 过渡到 click_scale
        current_click_scale = 1.0 + (click_scale - 1.0) * eased
    else
        if click_animation_active then
            local elapsed = current_time - click_start_time
            local progress = math.min(elapsed / half_duration, 1.0)
            local eased = ease_out_cubic(progress)
            -- 从 click_scale 过渡回 1.0
            current_click_scale = click_scale + (1.0 - click_scale) * eased
            
            if progress >= 1.0 then
                current_click_scale = 1.0
                click_animation_active = false
            end
        end
    end
end

-- 获取当前应该使用的鼠标图片
function get_current_cursor_image()
    if is_dragging and cursor_image_dragging ~= "" then
        return cursor_image_dragging
    elseif is_clicking and cursor_image_clicking ~= "" then
        return cursor_image_clicking
    else
        return cursor_image_path
    end
end

-- 更新鼠标源的图片
function update_cursor_image(scene_item)
    local current_image = get_current_cursor_image()
    if current_image == "" then return end
    
    local src = obs.obs_sceneitem_get_source(scene_item)
    if not src then return end
    
    local settings = obs.obs_source_get_settings(src)
    if settings then
        local current_file = obs.obs_data_get_string(settings, "file")
        if current_file ~= current_image then
            obs.obs_data_set_string(settings, "file", current_image)
            obs.obs_source_update(src, settings)
        end
        obs.obs_data_release(settings)
    end
end

-- ========================================
-- 平滑鼠标指针
-- ========================================

function get_zoom_transform()
    -- 获取当前缩放变换信息
    -- 返回: zoom_scale(缩放倍数), crop_x, crop_y(裁剪偏移)
    if zoom_state == ZoomState.None or not crop_filter_info then
        return 1, 0, 0
    end
    
    local source_w = zoom_info.source_size.width
    local source_h = zoom_info.source_size.height
    
    if source_w <= 0 or source_h <= 0 then
        return 1, 0, 0
    end
    
    local current_w = crop_filter_info.w or source_w
    local current_h = crop_filter_info.h or source_h
    
    if current_w <= 0 or current_h <= 0 then
        return 1, 0, 0
    end
    
    local scale = source_w / current_w
    local crop_x = crop_filter_info.x or 0
    local crop_y = crop_filter_info.y or 0
    
    return scale, crop_x, crop_y
end

function update_cursor()
    if not is_cursor_enabled or not cursor_source or cursor_source_name == "" then
        return
    end
    
    update_click_animation()
    
    local mouse = get_mouse_pos()
    
    -- 应用显示器偏移
    if monitor_info then
        mouse.x = mouse.x - monitor_info.x
        mouse.y = mouse.y - monitor_info.y
        
        -- 应用DPI缩放（如果有）
        if monitor_info.scale_x and monitor_info.scale_y then
            mouse.x = mouse.x * monitor_info.scale_x
            mouse.y = mouse.y * monitor_info.scale_y
        end
    end
    
    if mouse.x ~= last_mouse_pos.x or mouse.y ~= last_mouse_pos.y then
        target_pos.x = mouse.x
        target_pos.y = mouse.y
        last_mouse_pos.x = mouse.x
        last_mouse_pos.y = mouse.y
    end
    
    -- 按住时根据紧致度参数调整跟随平滑度
    -- smooth_factor_clicking: 0=不改变，1=最紧（直接不平滑）
    local current_smooth = smooth_factor
    if is_clicking and smooth_factor_clicking > 0 then
        -- 紧致度从0到1，平滑度从smooth_factor降到1.0
        current_smooth = smooth_factor + (1.0 - smooth_factor) * smooth_factor_clicking
    end
    current_pos.x = lerp(current_pos.x, target_pos.x, current_smooth)
    current_pos.y = lerp(current_pos.y, target_pos.y, current_smooth)
    
    local success, error_msg = pcall(function()
        local scene_source = obs.obs_frontend_get_current_scene()
        if not scene_source then return end
        
        local scene = obs.obs_scene_from_source(scene_source)
        if not scene then
            obs.obs_source_release(scene_source)
            return
        end
        
        local scene_item = obs.obs_scene_find_source(scene, cursor_source_name_current)
        if not scene_item then
            obs.obs_source_release(scene_source)
            return
        end
        
        -- 更新鼠标图片（如果有不同状态的图片）
        update_cursor_image(scene_item)
        
        local transform = obs.obs_transform_info()
        obs.obs_sceneitem_get_info(scene_item, transform)
        
        -- 计算最终位置和缩放
        local display_x = current_pos.x
        local display_y = current_pos.y
        local zoom_scale_factor = 1.0
        
        -- 如果启用了鼠标跟随缩放，应用缩放变换
        if cursor_follow_zoom and zoom_state ~= ZoomState.None then
            local scale, crop_x, crop_y = get_zoom_transform()
            zoom_scale_factor = scale
            -- 将鼠标位置转换到缩放后的坐标系
            display_x = (current_pos.x - crop_x) * scale
            display_y = (current_pos.y - crop_y) * scale
        end
        
        -- 获取图片源的原始尺寸
        local img_src = obs.obs_sceneitem_get_source(scene_item)
        local img_width = img_src and obs.obs_source_get_width(img_src) or 32
        local img_height = img_src and obs.obs_source_get_height(img_src) or 32
        
        local base_scale = cursor_scale * zoom_scale_factor
        local final_scale = base_scale * current_click_scale
        
        -- 计算点击缩放的锚点偏移
        -- 当 current_click_scale != 1 时，需要调整位置以保持锚点不动
        local anchor_offset_x = 0
        local anchor_offset_y = 0
        if current_click_scale ~= 1.0 then
            -- 锚点在图片中的位置（相对于基础缩放后的尺寸）
            local anchor_x_in_img = click_anchor_x * img_width * base_scale
            local anchor_y_in_img = click_anchor_y * img_height * base_scale
            -- 缩放后锚点的位置变化
            anchor_offset_x = anchor_x_in_img * (current_click_scale - 1.0)
            anchor_offset_y = anchor_y_in_img * (current_click_scale - 1.0)
        end
        
        transform.pos.x = display_x - hotspot_x * final_scale - anchor_offset_x
        transform.pos.y = display_y - hotspot_y * final_scale - anchor_offset_y
        transform.scale.x = final_scale
        transform.scale.y = final_scale
        
        obs.obs_sceneitem_set_info(scene_item, transform)
        obs.obs_source_release(scene_source)
    end)
    
    if not success then
        log("Update cursor failed: " .. tostring(error_msg))
    end
end

function on_cursor_timer()
    if not is_cursor_enabled or not cursor_timer_running then
        return
    end
    
    local success, error_msg = pcall(update_cursor)
    if not success then
        log("Cursor timer error: " .. tostring(error_msg))
    end
end

-- 自动缩放独立定时器
function on_auto_zoom_timer()
    if not auto_zoom_enabled then
        return
    end
    
    local success, error_msg = pcall(check_auto_zoom)
    if not success then
        log("Auto zoom timer error: " .. tostring(error_msg))
    end
end

function start_auto_zoom_timer()
    if auto_zoom_enabled and not auto_zoom_timer_running then
        if not win_api_available then
            init_windows_api()
        end
        obs.timer_add(on_auto_zoom_timer, 16)
        auto_zoom_timer_running = true
        log("自动缩放定时器已启动")
    end
end

function stop_auto_zoom_timer()
    if auto_zoom_timer_running then
        obs.timer_remove(on_auto_zoom_timer)
        auto_zoom_timer_running = false
        auto_zoom_active = false
        log("自动缩放定时器已停止")
    end
end

-- ========================================
-- 鼠标源查找函数（支持模式匹配）
-- ========================================

-- 在当前场景中查找匹配模式的鼠标源
-- 模式匹配规则：
-- 1. 精确匹配：cursor_source_name
-- 2. 带场景名后缀：cursor_source_name_<场景名>
-- 3. 带任意后缀：cursor_source_name_*
function find_cursor_source_in_scene()
    if cursor_source_name == "" then
        return nil, nil
    end
    
    local scene_source = obs.obs_frontend_get_current_scene()
    if not scene_source then
        return nil, nil
    end
    
    local scene = obs.obs_scene_from_source(scene_source)
    if not scene then
        obs.obs_source_release(scene_source)
        return nil, nil
    end
    
    local scene_name = obs.obs_source_get_name(scene_source)
    local found_name = nil
    local found_item = nil
    
    -- 优先级1：精确匹配 cursor_source_name
    local item = obs.obs_scene_find_source(scene, cursor_source_name)
    if item then
        found_name = cursor_source_name
        found_item = item
    end
    
    -- 优先级2：尝试 cursor_source_name_<场景名>
    if not found_item and scene_name then
        local scene_specific_name = cursor_source_name .. "_" .. scene_name
        item = obs.obs_scene_find_source(scene, scene_specific_name)
        if item then
            found_name = scene_specific_name
            found_item = item
        end
    end
    
    -- 优先级3：遍历场景查找以 cursor_source_name 开头的源
    if not found_item then
        local items = obs.obs_scene_enum_items(scene)
        if items then
            for _, scene_item in ipairs(items) do
                local item_source = obs.obs_sceneitem_get_source(scene_item)
                if item_source then
                    local item_name = obs.obs_source_get_name(item_source)
                    -- 检查是否以 cursor_source_name 开头
                    if item_name and string.sub(item_name, 1, #cursor_source_name) == cursor_source_name then
                        found_name = item_name
                        found_item = scene_item
                        break
                    end
                end
            end
            obs.sceneitem_list_release(items)
        end
    end
    
    obs.obs_source_release(scene_source)
    return found_name, found_item
end

-- 刷新当前场景中的鼠标源
function refresh_cursor_source()
    -- 释放旧的源引用
    if cursor_source then
        obs.obs_source_release(cursor_source)
        cursor_source = nil
    end
    
    -- 查找新的源
    local found_name, found_item = find_cursor_source_in_scene()
    
    if found_name then
        cursor_source_name_current = found_name
        cursor_source = obs.obs_get_source_by_name(found_name)
        if cursor_source then
            log("鼠标源已刷新: " .. found_name)
        end
    else
        -- 如果没找到鼠标源，且平滑鼠标已启用，尝试自动创建
        if is_cursor_enabled and cursor_source_name ~= "" and cursor_image_path ~= "" then
            log("当前场景中未找到匹配的鼠标源，正在尝试自动创建...")
            if create_cursor_source() then
                -- 再次查找新创建的源
                found_name, found_item = find_cursor_source_in_scene()
                if found_name then
                    cursor_source_name_current = found_name
                    cursor_source = obs.obs_get_source_by_name(found_name)
                    if cursor_source then
                        log("鼠标源自动创建成功: " .. found_name)
                    end
                end
            else
                log("自动创建鼠标源失败")
                cursor_source_name_current = ""
            end
        else
            cursor_source_name_current = ""
            log("当前场景中未找到匹配的鼠标源 (模式: " .. cursor_source_name .. ")")
        end
    end
end

function toggle_cursor()
    is_cursor_enabled = not is_cursor_enabled
    
    if is_cursor_enabled then
        if not win_api_available then
            init_windows_api()
        end
        
        if cursor_source then
            obs.obs_source_release(cursor_source)
            cursor_source = nil
        end
        
        -- 使用模式匹配查找当前场景中的鼠标源
        refresh_cursor_source()
        
        -- 确保 monitor_info 被初始化（如果缩放源已设置）
        if not monitor_info and source_name_current ~= "" then
            local temp_source = obs.obs_get_source_by_name(source_name_current)
            if temp_source then
                monitor_info = get_monitor_info(temp_source)
                obs.obs_source_release(temp_source)
            end
        end
        
        if cursor_source then
            local mouse = get_mouse_pos()
            if monitor_info then
                mouse.x = mouse.x - monitor_info.x
                mouse.y = mouse.y - monitor_info.y
                if monitor_info.scale_x and monitor_info.scale_y then
                    mouse.x = mouse.x * monitor_info.scale_x
                    mouse.y = mouse.y * monitor_info.scale_y
                end
            end
            
            current_pos.x = mouse.x
            current_pos.y = mouse.y
            target_pos.x = mouse.x
            target_pos.y = mouse.y
            current_click_scale = 1.0
            
            if not cursor_timer_running then
                obs.timer_add(on_cursor_timer, 16)
                cursor_timer_running = true
            end
            
            -- 输出调试信息
            local monitor_str = "nil"
            if monitor_info then
                monitor_str = string.format("x=%d, y=%d, w=%d, h=%d, sx=%.2f, sy=%.2f", 
                    monitor_info.x or 0, monitor_info.y or 0, 
                    monitor_info.width or 0, monitor_info.height or 0,
                    monitor_info.scale_x or 1, monitor_info.scale_y or 1)
            end
            log("平滑鼠标已启用，使用源: " .. cursor_source_name_current)
            log("监视器信息: " .. monitor_str)
            log("初始鼠标位置: " .. mouse.x .. ", " .. mouse.y)
        else
            -- 找不到鼠标源，尝试自动创建
            log("找不到鼠标源，正在尝试自动创建...")
            if cursor_source_name ~= "" and cursor_image_path ~= "" then
                if create_cursor_source() then
                    -- 重新尝试刷新源
                    refresh_cursor_source()
                    if cursor_source then
                        log("鼠标源创建成功，继续启用平滑鼠标")
                        -- 直接继续启用流程
                        local mouse = get_mouse_pos()
                        if monitor_info then
                            mouse.x = mouse.x - monitor_info.x
                            mouse.y = mouse.y - monitor_info.y
                            if monitor_info.scale_x and monitor_info.scale_y then
                                mouse.x = mouse.x * monitor_info.scale_x
                                mouse.y = mouse.y * monitor_info.scale_y
                            end
                        end
                        
                        current_pos.x = mouse.x
                        current_pos.y = mouse.y
                        target_pos.x = mouse.x
                        target_pos.y = mouse.y
                        current_click_scale = 1.0
                        
                        if not cursor_timer_running then
                            obs.timer_add(on_cursor_timer, 16)
                            cursor_timer_running = true
                        end
                        
                        -- 输出调试信息
                        local monitor_str = "nil"
                        if monitor_info then
                            monitor_str = string.format("x=%d, y=%d, w=%d, h=%d, sx=%.2f, sy=%.2f", 
                                monitor_info.x or 0, monitor_info.y or 0, 
                                monitor_info.width or 0, monitor_info.height or 0,
                                monitor_info.scale_x or 1, monitor_info.scale_y or 1)
                        end
                        log("平滑鼠标已启用，使用源: " .. cursor_source_name_current)
                        log("监视器信息: " .. monitor_str)
                        log("初始鼠标位置: " .. mouse.x .. ", " .. mouse.y)
                        return
                    else
                        log("鼠标源创建后仍找不到源")
                    end
                else
                    log("自动创建鼠标源失败")
                end
            else
                log("无法自动创建鼠标源：请先设置鼠标源名称和图标路径")
            end
            is_cursor_enabled = false
        end
    else
        if cursor_timer_running then
            obs.timer_remove(on_cursor_timer)
            cursor_timer_running = false
        end
        
        if cursor_source then
            obs.obs_source_release(cursor_source)
            cursor_source = nil
        end
        
        log("平滑鼠标已禁用")
    end
end

function on_toggle_cursor(pressed)
    if pressed then
        toggle_cursor()
    end
end

-- ========================================
-- 自动缩放逻辑
-- ========================================

-- 调试计数器（每秒输出一次）
local auto_zoom_debug_counter = 0
local auto_zoom_debug_interval = 60  -- 约每秒输出一次（16ms * 60 ≈ 1秒）

function check_auto_zoom()
    if not auto_zoom_enabled then
        return
    end
    
    local mouse_clicked = is_mouse_clicked()
    local current_time = get_time_ms()
    local mouse = get_mouse_pos()
    
    -- 调试输出（每秒一次）
    auto_zoom_debug_counter = auto_zoom_debug_counter + 1
    local should_debug = (auto_zoom_debug_counter >= auto_zoom_debug_interval)
    if should_debug then
        auto_zoom_debug_counter = 0
    end
    
    -- 检测点击触发自动放大
    if mouse_clicked and not auto_zoom_was_clicked then
        -- 刚刚点击
        if zoom_state == ZoomState.None and not auto_zoom_active then
            -- 当前没有缩放，触发放大
            -- 根据策略决定是否在点击时设置基准点
            if auto_zoom_center_follow_on_click then
                auto_zoom_start_pos.x = mouse.x
                auto_zoom_start_pos.y = mouse.y
            end
            on_toggle_zoom(true)
            auto_zoom_active = true
            auto_zoom_ready = false  -- 还没准备好，等待放大完成
            log("自动缩放: 点击触发放大，基准点: " .. mouse.x .. ", " .. mouse.y)
        elseif zoom_state == ZoomState.ZoomingOut then
            -- 正在缩小，点击打断并重新放大
            -- 根据策略决定是否重新设置基准点
            if auto_zoom_center_follow_on_click then
                auto_zoom_start_pos.x = mouse.x
                auto_zoom_start_pos.y = mouse.y
            end
            on_toggle_zoom(true)  -- 这会切换到 ZoomingIn
            auto_zoom_active = true
            auto_zoom_ready = false
            log("自动缩放: 点击打断缩小，重新放大，基准点: " .. mouse.x .. ", " .. mouse.y)
        end
    end
    
    -- 如果正在自动缩放且按住鼠标（长按），持续重置计时器
    if auto_zoom_active and mouse_clicked then
        auto_zoom_start_time = current_time
        -- 根据策略决定是否在长按时更新基准点
        if auto_zoom_center_follow_on_longpress then
            auto_zoom_start_pos.x = mouse.x
            auto_zoom_start_pos.y = mouse.y
        end
        if should_debug then
            log("[DEBUG] 按住鼠标，重置计时器，不重置位置")
        end
    end
    
    auto_zoom_was_clicked = mouse_clicked
    
    -- 当放大完成时，开始计时（但不重置基准点位置）
    if auto_zoom_active and not auto_zoom_ready and zoom_state == ZoomState.ZoomedIn then
        auto_zoom_ready = true
        auto_zoom_start_time = current_time
        -- 注意：不再重置 auto_zoom_start_pos，使用点击时设置的基准点
        log("自动缩放: 放大完成，开始计时。基准点: " .. auto_zoom_start_pos.x .. ", " .. auto_zoom_start_pos.y)
    end
    
    -- 策略1：立即检测 - 在放大过程中就检测距离
    if auto_zoom_active and auto_zoom_threshold_strategy == "immediate" and zoom_state == ZoomState.ZoomingIn then
        if auto_zoom_move_threshold > 0 then
            local dx = mouse.x - auto_zoom_start_pos.x
            local dy = mouse.y - auto_zoom_start_pos.y
            local distance = math.sqrt(dx * dx + dy * dy)
            
            if distance >= auto_zoom_move_threshold then
                log("自动缩放: 放大中检测到超出阈值 (" .. math.floor(distance) .. "px >= " .. auto_zoom_move_threshold .. "px)，立即恢复")
                on_toggle_zoom(true)  -- 触发缩小
                auto_zoom_active = false
                auto_zoom_ready = false
                return  -- 直接返回，不继续后续检测
            end
        end
    end
    
    -- 检测是否需要自动恢复（只在放大完成后检测）
    if auto_zoom_active and auto_zoom_ready and zoom_state == ZoomState.ZoomedIn then
        local should_zoom_out = false
        local reason = ""
        
        -- 检查超时
        local elapsed = current_time - auto_zoom_start_time
        if auto_zoom_timeout > 0 then
            if elapsed >= auto_zoom_timeout then
                should_zoom_out = true
                reason = "超时 (" .. math.floor(elapsed) .. "ms >= " .. auto_zoom_timeout .. "ms)"
            end
        end
        
        -- 检查移动距离
        local dx = mouse.x - auto_zoom_start_pos.x
        local dy = mouse.y - auto_zoom_start_pos.y
        local distance = math.sqrt(dx * dx + dy * dy)
        
        if not should_zoom_out and auto_zoom_move_threshold > 0 then
            if distance >= auto_zoom_move_threshold then
                should_zoom_out = true
                reason = "移动距离超过阈值 (" .. math.floor(distance) .. "px >= " .. auto_zoom_move_threshold .. "px)"
            end
        end
        
        -- 每秒输出调试信息
        if should_debug then
            local state_names = { [0] = "None", [1] = "ZoomingIn", [2] = "ZoomingOut", [3] = "ZoomedIn" }
            log("[DEBUG] active=" .. tostring(auto_zoom_active) .. 
                ", ready=" .. tostring(auto_zoom_ready) ..
                ", state=" .. (state_names[zoom_state] or "?") ..
                ", clicked=" .. tostring(mouse_clicked) ..
                ", elapsed=" .. math.floor(elapsed) .. "ms" ..
                ", timeout=" .. auto_zoom_timeout .. "ms" ..
                ", dist=" .. math.floor(distance) .. "px" ..
                ", threshold=" .. auto_zoom_move_threshold .. "px")
        end
        
        if should_zoom_out then
            log("自动缩放: " .. reason .. ", 自动恢复")
            on_toggle_zoom(true)  -- 触发缩小
            auto_zoom_active = false
            auto_zoom_ready = false
        end
    end
    
    -- 如果手动缩小了或正在缩小，重置自动缩放状态
    if auto_zoom_active and (zoom_state == ZoomState.None or zoom_state == ZoomState.ZoomingOut) then
        log("自动缩放: 手动恢复或缩小中，重置状态")
        auto_zoom_active = false
        auto_zoom_ready = false
    end
end

-- ========================================
-- 创建鼠标源
-- ========================================

function create_cursor_source()
    log("创建/检测鼠标源被调用，cursor_source_name=" .. tostring(cursor_source_name) .. ", cursor_image_path=" .. tostring(cursor_image_path))
    
    if cursor_source_name == "" or cursor_image_path == "" then
        log("请先设置鼠标图片路径和源名称")
        return false
    end
    
    local scene_source = obs.obs_frontend_get_current_scene()
    if not scene_source then
        log("没有当前场景")
        return false
    end
    
    local scene = obs.obs_scene_from_source(scene_source)
    if not scene then
        obs.obs_source_release(scene_source)
        return false
    end
    
    local scene_name = obs.obs_source_get_name(scene_source)
    
    -- 首先尝试查找当前场景中已存在的匹配源
    local found_name, found_item = find_cursor_source_in_scene()
    
    if found_item then
        -- 已有匹配的源，更新其图片
        local src = obs.obs_sceneitem_get_source(found_item)
        if src then
            local settings = obs.obs_source_get_settings(src)
            if settings then
                obs.obs_data_set_string(settings, "file", cursor_image_path)
                obs.obs_source_update(src, settings)
                obs.obs_data_release(settings)
                log("已更新鼠标源: " .. found_name)
            end
        end
        obs.obs_source_release(scene_source)
        
        -- 刷新当前使用的源
        refresh_cursor_source()
        return true
    end
    
    -- 生成场景专用的源名称: cursor_source_name_场景名
    local new_source_name = cursor_source_name .. "_" .. scene_name
    
    -- 检查这个名称的全局源是否已存在
    local existing_source = obs.obs_get_source_by_name(new_source_name)
    if existing_source then
        -- 源已存在，只需添加到场景中
        local scene_item = obs.obs_scene_add(scene, existing_source)
        if scene_item then
            obs.obs_sceneitem_set_order(scene_item, obs.OBS_ORDER_MOVE_TOP)
            log("已将鼠标源添加到场景: " .. new_source_name)
        end
        obs.obs_source_release(existing_source)
        obs.obs_source_release(scene_source)
        refresh_cursor_source()
        return true
    end
    
    -- 创建新的图片源
    local settings = obs.obs_data_create()
    obs.obs_data_set_string(settings, "file", cursor_image_path)
    
    local image_source = obs.obs_source_create("image_source", new_source_name, settings, nil)
    local result = false
    
    if image_source then
        local scene_item = obs.obs_scene_add(scene, image_source)
        if scene_item then
            obs.obs_sceneitem_set_order(scene_item, obs.OBS_ORDER_MOVE_TOP)
            log("已创建鼠标源: " .. new_source_name .. " (场景: " .. scene_name .. ")")
            result = true
        end
        obs.obs_source_release(image_source)
    end
    
    obs.obs_data_release(settings)
    obs.obs_source_release(scene_source)
    
    -- 刷新当前使用的源
    if result then
        refresh_cursor_source()
    end
    
    return result
end

-- ========================================
-- 场景切换
-- ========================================

function on_frontend_event(event)
    if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then
        if zoom_state ~= ZoomState.None then
            release_sceneitem()
        end
        if is_obs_loaded then
            refresh_sceneitem(true)
        end
        -- 场景切换时刷新鼠标源（在新场景中查找匹配的源）
        if is_cursor_enabled then
            refresh_cursor_source()
        end
    elseif event == obs.OBS_FRONTEND_EVENT_FINISHED_LOADING then
        is_obs_loaded = true
        refresh_sceneitem(true)
        
        -- OBS加载完成后，根据用户设置自动启用平滑鼠标
        if saved_settings then
            local should_cursor_enabled = obs.obs_data_get_bool(saved_settings, "is_cursor_enabled")
            if should_cursor_enabled and not is_cursor_enabled then
                toggle_cursor()
                log("平滑鼠标: 根据用户设置自动启用")
            end
        end
    end
end

-- ========================================
-- 设置回调
-- ========================================

function on_settings_modified(props, prop, settings)
    local name = obs.obs_property_name(prop)
    
    if name == "use_monitor_override" then
        local visible = obs.obs_data_get_bool(settings, "use_monitor_override")
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_x"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_y"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_w"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_h"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_sx"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_sy"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_dw"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_dh"), visible)
        return true
    elseif name == "zoom_ease_in_type" then
        local val = obs.obs_data_get_string(settings, "zoom_ease_in_type")
        obs.obs_property_set_visible(obs.obs_properties_get(props, "zoom_custom_ease_in_expr"), val == "Custom")
        return true
    elseif name == "zoom_ease_out_type" then
        local val = obs.obs_data_get_string(settings, "zoom_ease_out_type")
        obs.obs_property_set_visible(obs.obs_properties_get(props, "zoom_custom_ease_out_expr"), val == "Custom")
        return true
    end
    
    return false
end

-- ========================================
-- 脚本接口
-- ========================================

function script_description()
    return [[<center><h2>Focursor</h2></center>
<p><center>v]] .. VERSION .. [[</center></p>
<hr/>
<p>这是一个暂时闭源的 OBS 脚本插件（测试版），提供平滑的鼠标指针缩放和跟随功能。测试版完全免费，如果有人向你收取费用，请及时要求退款！</p>
<p>作者Github主页：https://github.com/Ethanout<br>作者B站用户名：伊桑桑桑桑桑</p>
<p>
使用方法：
<br>1. 设置鼠标外观。
<br>2. 依次设置 “核心设置 & 源控制” 的各项参数。
<br>3. 在“文件→设置→快捷键”中设置快捷键。
<br>4. 右键你设置的缩放目标源→设置→取消勾选“显示鼠标指针”
</p>
<hr/>]]
end

function script_properties()
    local props = obs.obs_properties_create()
    
    -- ═══════════════════════════════════════
    -- 核心控制与源设置
    -- ═══════════════════════════════════════
    obs.obs_properties_add_text(props, "core_control_header", 
        "<h3>核心控制 & 源设置</h3>", obs.OBS_TEXT_INFO)
    
    obs.obs_properties_add_text(props, "zoom_source_hint", 
    "<small>输入源名称或前缀，会自动匹配以名称开头的源</small>", 
    obs.OBS_TEXT_INFO)
    
    -- 1. 缩放源选择 (支持模式匹配)
    local source_prop = obs.obs_properties_add_text(props, "source_name", "缩放目标源名称/前缀", obs.OBS_TEXT_DEFAULT)
    obs.obs_property_set_long_description(source_prop, "留空则自动选择当前场景的第一个窗口/显示器采集源\n支持模式匹配：精确名称 → 名称_场景名 → 以名称开头的任意源")
    
    -- 2. 平滑鼠标源设置
    obs.obs_properties_add_text(props, "cursor_source_name", "鼠标源名称/前缀", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "cursor_source_hint", 
        "<small>启用时如果找不到匹配源会自动创建</small>", obs.OBS_TEXT_INFO)
    
    -- 3. 功能开关
    local cursor_status = is_cursor_enabled and "🟢 已启用" or "🟠 已禁用"
    obs.obs_properties_add_button(props, "toggle_cursor_btn", 
        is_cursor_enabled and "禁用平滑鼠标" or "启用平滑鼠标", 
        function(props_inner)
            -- 检查鼠标源图标是否设置
            if not is_cursor_enabled and cursor_image_path == "" then
                -- 显示提示信息
                obs.obs_property_set_description(obs.obs_properties_get(props_inner, "cursor_status"),
                    "❌ 请先设置鼠标外观")
                return true
            end
            
            toggle_cursor()
            -- 更新状态显示
            local new_status = is_cursor_enabled and "🟢 已启用" or "🟠 已禁用"
            obs.obs_property_set_description(obs.obs_properties_get(props_inner, "cursor_status"),
                "当前状态： " .. new_status)
            obs.obs_property_set_description(obs.obs_properties_get(props_inner, "toggle_cursor_btn"),
                is_cursor_enabled and "禁用平滑鼠标" or "启用平滑鼠标")
            return true
        end)
        
    obs.obs_properties_add_text(props, "cursor_status", 
        "当前状态： " .. cursor_status, obs.OBS_TEXT_INFO)

    obs.obs_properties_add_text(props, "separator_main", 
        "<hr/>", obs.OBS_TEXT_INFO)

    -- ═══════════════════════════════════════
    -- 缩放与跟随参数
    -- ═══════════════════════════════════════
    obs.obs_properties_add_text(props, "zoom_settings_header", 
        "<h3>缩放参数设置</h3>", obs.OBS_TEXT_INFO)

    obs.obs_properties_add_float(props, "zoom_value", "缩放倍数", 1.5, 5, 0.25)
    
    local ease_names = {
        "Linear", "EaseIn", "EaseOut", "EaseInOut",
        "EaseInCubic", "EaseOutCubic", "EaseInOutCubic",
        "EaseInQuart", "EaseOutQuart", "EaseInOutQuart",
        "EaseOutElastic", "EaseOutBack", "EaseOutBounce",
        "Custom"
    }

    -- 放大设置
    obs.obs_properties_add_text(props, "zoom_in_header", "<strong>:: 放大动画 (Zoom In) ::</strong>", obs.OBS_TEXT_INFO)
    obs.obs_properties_add_float_slider(props, "zoom_speed_in", "放大速度", 0.005, 0.5, 0.005)
    
    local list_in = obs.obs_properties_add_list(props, "zoom_ease_in_type", "放大缓动类型", 
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    for _, name in ipairs(ease_names) do
        obs.obs_property_list_add_string(list_in, name, name)
    end
    obs.obs_property_set_modified_callback(list_in, on_settings_modified)
    
    local custom_in = obs.obs_properties_add_text(props, "zoom_custom_ease_in_expr", "表达式 (t -> val)", obs.OBS_TEXT_DEFAULT)
    obs.obs_property_set_visible(custom_in, zoom_ease_in_type == "Custom")


    -- 缩小设置
    obs.obs_properties_add_text(props, "zoom_out_header", "<strong>:: 缩小动画 (Zoom Out) ::</strong>", obs.OBS_TEXT_INFO)
    obs.obs_properties_add_float_slider(props, "zoom_speed_out", "缩小速度", 0.005, 0.5, 0.005)
    
    local list_out = obs.obs_properties_add_list(props, "zoom_ease_out_type", "缩小缓动类型", 
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    for _, name in ipairs(ease_names) do
        obs.obs_property_list_add_string(list_out, name, name)
    end
    obs.obs_property_set_modified_callback(list_out, on_settings_modified)
    
    local custom_out = obs.obs_properties_add_text(props, "zoom_custom_ease_out_expr", "表达式 (t -> val)", obs.OBS_TEXT_DEFAULT)
    obs.obs_property_set_visible(custom_out, zoom_ease_out_type == "Custom")
    
    -- 自动缩放 (重要功能)
    obs.obs_properties_add_bool(props, "auto_zoom_enabled", "启用自动缩放 (点击时自动放大)")
    obs.obs_properties_add_int_slider(props, "auto_zoom_timeout", "自动恢复时间 (毫秒，0为禁用)", 0, 10000, 100)
    obs.obs_properties_add_int_slider(props, "auto_zoom_move_threshold", "移动缩小阈值 (像素，0为禁用)", 0, 1000, 10)
    
    local strategy_list = obs.obs_properties_add_list(props, "auto_zoom_threshold_strategy", "阈值检测时机",
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(strategy_list, "等待放大完成后检测 (推荐)", "wait_complete")
    obs.obs_property_list_add_string(strategy_list, "立即检测 (放大中就能触发)", "immediate")
    
    obs.obs_properties_add_text(props, "auto_zoom_center_header", "<br><strong>:: 基准点更新策略 ::</strong></br>", obs.OBS_TEXT_INFO)
    obs.obs_properties_add_bool(props, "auto_zoom_center_follow_on_click", "点击时基准点设为鼠标位置")
    obs.obs_properties_add_bool(props, "auto_zoom_center_follow_on_longpress", "长按时基准点跟随鼠标位置")
    obs.obs_properties_add_text(props, "spacer_after_auto_zoom_center", "<small>&nbsp;</small>", obs.OBS_TEXT_INFO)

    -- 跟随设置
    obs.obs_properties_add_text(props, "auto_zoom_follow_header", "<strong>:: 跟随设置 ::</strong>", obs.OBS_TEXT_INFO)
    obs.obs_properties_add_float_slider(props, "follow_speed", "跟随速度", 0.05, 0.5, 0.01)
    obs.obs_properties_add_int_slider(props, "follow_border", "跟随边界 %", 0, 50, 2)
    obs.obs_properties_add_bool(props, "use_auto_follow_mouse", "放大后自动跟随鼠标")
    
    obs.obs_properties_add_text(props, "separator_cursor", 
        "<hr/>", obs.OBS_TEXT_INFO)

    -- ═══════════════════════════════════════
    -- 鼠标外观
    -- ═══════════════════════════════════════
    obs.obs_properties_add_text(props, "cursor_look_header", 
        "<h3>鼠标外观</h3>", obs.OBS_TEXT_INFO)

    obs.obs_properties_add_path(props, "cursor_image_path", "默认图标", 
        obs.OBS_PATH_FILE, "图片文件 (*.png *.jpg *.gif *.bmp);;所有文件 (*.*)", nil)
    obs.obs_properties_add_path(props, "cursor_image_clicking", "点击图标 (可选)", 
        obs.OBS_PATH_FILE, "图片文件 (*.png *.jpg *.gif *.bmp);;所有文件 (*.*)", nil)
    obs.obs_properties_add_path(props, "cursor_image_dragging", "拖动图标 (可选)", 
        obs.OBS_PATH_FILE, "图片文件 (*.png *.jpg *.gif *.bmp);;所有文件 (*.*)", nil)

    obs.obs_properties_add_float_slider(props, "cursor_scale", "鼠标大小", 0.001, 3.0, 0.001)
    obs.obs_properties_add_int_slider(props, "hotspot_x", "X 偏移", -500, 500, 1)
    obs.obs_properties_add_int_slider(props, "hotspot_y", "Y 偏移", -500, 500, 1)

    obs.obs_properties_add_text(props, "separator_behavior", 
        "<hr/>", obs.OBS_TEXT_INFO)

    -- ═══════════════════════════════════════
    -- 鼠标行为
    -- ═══════════════════════════════════════
    obs.obs_properties_add_text(props, "cursor_behavior_header", 
        "<h3>鼠标行为</h3>", obs.OBS_TEXT_INFO)

    obs.obs_properties_add_float_slider(props, "smooth_factor", "移动平滑度", 0.01, 0.5, 0.01)
    obs.obs_properties_add_float_slider(props, "smooth_factor_clicking", "长按时移动紧致度", 0.0, 1.0, 0.01)
    obs.obs_properties_add_float_slider(props, "click_scale", "点击时缩放 (1=无)", 0.01, 2.0, 0.01)
    obs.obs_properties_add_float_slider(props, "click_anchor_x", "缩放中心点 X (0=左, 0.5=中, 1=右)", 0.0, 1.0, 0.01)
    obs.obs_properties_add_float_slider(props, "click_anchor_y", "缩放中心点 Y (0=上, 0.5=中, 1=下)", 0.0, 1.0, 0.01)
        obs.obs_properties_add_int_slider(props, "click_duration", "动画时长 (ms)", 0, 1000, 1)
    obs.obs_properties_add_bool(props, "cursor_follow_zoom", "图标随缩放变大")

    obs.obs_properties_add_text(props, "separator_adv", 
        "<hr/>", obs.OBS_TEXT_INFO)

    -- ═══════════════════════════════════════
    -- 高级设置
    -- ═══════════════════════════════════════
    obs.obs_properties_add_text(props, "zoom_adv_header", 
        "<h3>高级设置</h3>", obs.OBS_TEXT_INFO)
    
    obs.obs_properties_add_bool(props, "use_follow_auto_lock", "跟随自动锁定")
    obs.obs_properties_add_bool(props, "use_follow_outside_bounds", "允许跟随到边界外")
    obs.obs_properties_add_int_slider(props, "follow_safezone_sensitivity", "鼠标停止判定阈值", 1, 100, 1)

    
    local override = obs.obs_properties_add_bool(props, "use_monitor_override", "手动覆盖源位置/大小")
    obs.obs_property_set_modified_callback(override, on_settings_modified)
    
    local ox = obs.obs_properties_add_int(props, "monitor_override_x", "源 X", -10000, 10000, 1)
    local oy = obs.obs_properties_add_int(props, "monitor_override_y", "源 Y", -10000, 10000, 1)
    local ow = obs.obs_properties_add_int(props, "monitor_override_w", "源宽度", 0, 10000, 1)
    local oh = obs.obs_properties_add_int(props, "monitor_override_h", "源高度", 0, 10000, 1)
    local osx = obs.obs_properties_add_float(props, "monitor_override_sx", "X缩放比", 0, 10, 0.01)
    local osy = obs.obs_properties_add_float(props, "monitor_override_sy", "Y缩放比", 0, 10, 0.01)
    local odw = obs.obs_properties_add_int(props, "monitor_override_dw", "显示器宽", 0, 10000, 1)
    local odh = obs.obs_properties_add_int(props, "monitor_override_dh", "显示器高", 0, 10000, 1)
    
    obs.obs_property_set_visible(ox, use_monitor_override)
    obs.obs_property_set_visible(oy, use_monitor_override)
    obs.obs_property_set_visible(ow, use_monitor_override)
    obs.obs_property_set_visible(oh, use_monitor_override)
    obs.obs_property_set_visible(osx, use_monitor_override)
    obs.obs_property_set_visible(osy, use_monitor_override)
    obs.obs_property_set_visible(odw, use_monitor_override)
    obs.obs_property_set_visible(odh, use_monitor_override)
    
    -- 调试
    obs.obs_properties_add_bool(props, "debug_logs", "启用调试日志")
    obs.obs_properties_add_button(props, "status_btn", "输出状态到日志", function()
        local state_names = { [0] = "未缩放", [1] = "正在放大", [2] = "正在缩小", [3] = "已放大" }
        local status = "\n====== 状态 ======\n"
        status = status .. "缩放源: " .. (source_name ~= "" and source_name or "未设置") .. "\n"
        status = status .. "缩放状态: " .. (state_names[zoom_state] or tostring(zoom_state)) .. "\n"
        status = status .. "平滑鼠标: " .. (is_cursor_enabled and "启用" or "禁用") .. "\n"
        status = status .. "跟随鼠标: " .. (is_following_mouse and "是" or "否") .. "\n"
        status = status .. "自动缩放: " .. (auto_zoom_enabled and "启用" or "禁用") .. ", 活动: " .. (auto_zoom_active and "是" or "否") .. "\n"
        status = status .. "当前点击: " .. (is_clicking and "是" or "否") .. ", 拖动: " .. (is_dragging and "是" or "否") .. "\n"
        obs.script_log(obs.OBS_LOG_INFO, status)
        return true
    end)
    
    return props
end

function script_defaults(settings)
    obs.obs_data_set_default_double(settings, "zoom_value", 2.00)
    
    obs.obs_data_set_default_double(settings, "zoom_speed_in", 0.23)
    obs.obs_data_set_default_double(settings, "zoom_speed_out", 0.23)
    obs.obs_data_set_default_string(settings, "zoom_ease_in_type", "EaseInOut")
    obs.obs_data_set_default_string(settings, "zoom_ease_out_type", "EaseInOut")
    obs.obs_data_set_default_string(settings, "zoom_custom_ease_in_expr", "t * t * (3 - 2 * t)")
    obs.obs_data_set_default_string(settings, "zoom_custom_ease_out_expr", "t * (2 - t)")
    
    obs.obs_data_set_default_bool(settings, "use_auto_follow_mouse", true)
    obs.obs_data_set_default_bool(settings, "use_follow_outside_bounds", false)
    obs.obs_data_set_default_double(settings, "follow_speed", 0.30)
    obs.obs_data_set_default_int(settings, "follow_border", 50)
    obs.obs_data_set_default_int(settings, "follow_safezone_sensitivity", 4)
    obs.obs_data_set_default_bool(settings, "use_follow_auto_lock", false)
    obs.obs_data_set_default_bool(settings, "allow_all_sources", false)
    obs.obs_data_set_default_bool(settings, "use_monitor_override", false)
    obs.obs_data_set_default_int(settings, "monitor_override_x", 0)
    obs.obs_data_set_default_int(settings, "monitor_override_y", 0)
    obs.obs_data_set_default_int(settings, "monitor_override_w", 1920)
    obs.obs_data_set_default_int(settings, "monitor_override_h", 1080)
    obs.obs_data_set_default_double(settings, "monitor_override_sx", 1)
    obs.obs_data_set_default_double(settings, "monitor_override_sy", 1)
    obs.obs_data_set_default_int(settings, "monitor_override_dw", 1920)
    obs.obs_data_set_default_int(settings, "monitor_override_dh", 1080)
    obs.obs_data_set_default_bool(settings, "debug_logs", false)
    
    obs.obs_data_set_default_bool(settings, "auto_zoom_enabled", true)
    obs.obs_data_set_default_int(settings, "auto_zoom_timeout", 2000)
    obs.obs_data_set_default_int(settings, "auto_zoom_move_threshold", 0)
    obs.obs_data_set_default_string(settings, "auto_zoom_threshold_strategy", "wait_complete")
    obs.obs_data_set_default_bool(settings, "auto_zoom_center_follow_on_click", true)
    obs.obs_data_set_default_bool(settings, "auto_zoom_center_follow_on_longpress", false)
    
    obs.obs_data_set_default_string(settings, "cursor_source_name", "平滑鼠标")
    
    -- 默认鼠标图标路径将在 script_load 中设置
    -- 这是因为 obs_script_get_info 在 script_defaults 中可能不可用
    
    obs.obs_data_set_default_double(settings, "smooth_factor", 0.40)
    obs.obs_data_set_default_double(settings, "smooth_factor_clicking", 0.5)
    obs.obs_data_set_default_double(settings, "cursor_scale", 0.13)
    obs.obs_data_set_default_double(settings, "click_scale", 0.90)
    obs.obs_data_set_default_int(settings, "click_duration", 330)
    obs.obs_data_set_default_int(settings, "drag_threshold", 100)
    obs.obs_data_set_default_double(settings, "click_anchor_x", 0.1)
    obs.obs_data_set_default_double(settings, "click_anchor_y", 0.1)
    obs.obs_data_set_default_int(settings, "hotspot_x", 114)
    obs.obs_data_set_default_int(settings, "hotspot_y", 0)
    obs.obs_data_set_default_bool(settings, "cursor_follow_zoom", true)
end

function script_update(settings)
    local old_source = source_name
    source_name = obs.obs_data_get_string(settings, "source_name")
    zoom_value = obs.obs_data_get_double(settings, "zoom_value")
    
    zoom_speed_in = obs.obs_data_get_double(settings, "zoom_speed_in")
    zoom_speed_out = obs.obs_data_get_double(settings, "zoom_speed_out")
    zoom_ease_in_type = obs.obs_data_get_string(settings, "zoom_ease_in_type")
    zoom_ease_out_type = obs.obs_data_get_string(settings, "zoom_ease_out_type")
    
    local custom_in_expr = obs.obs_data_get_string(settings, "zoom_custom_ease_in_expr")
    local custom_out_expr = obs.obs_data_get_string(settings, "zoom_custom_ease_out_expr")
    
    if custom_in_expr ~= zoom_custom_ease_in_expr then
        zoom_custom_ease_in_expr = custom_in_expr
        custom_ease_in_func = create_custom_easing(zoom_custom_ease_in_expr)
    end
    
    if custom_out_expr ~= zoom_custom_ease_out_expr then
        zoom_custom_ease_out_expr = custom_out_expr
        custom_ease_out_func = create_custom_easing(zoom_custom_ease_out_expr)
    end
    
    use_auto_follow_mouse = obs.obs_data_get_bool(settings, "use_auto_follow_mouse")
    use_follow_outside_bounds = obs.obs_data_get_bool(settings, "use_follow_outside_bounds")
    follow_speed = obs.obs_data_get_double(settings, "follow_speed")
    follow_border = obs.obs_data_get_int(settings, "follow_border")
    follow_safezone_sensitivity = obs.obs_data_get_int(settings, "follow_safezone_sensitivity")
    use_follow_auto_lock = obs.obs_data_get_bool(settings, "use_follow_auto_lock")
    allow_all_sources = obs.obs_data_get_bool(settings, "allow_all_sources")
    use_monitor_override = obs.obs_data_get_bool(settings, "use_monitor_override")
    monitor_override_x = obs.obs_data_get_int(settings, "monitor_override_x")
    monitor_override_y = obs.obs_data_get_int(settings, "monitor_override_y")
    monitor_override_w = obs.obs_data_get_int(settings, "monitor_override_w")
    monitor_override_h = obs.obs_data_get_int(settings, "monitor_override_h")
    monitor_override_sx = obs.obs_data_get_double(settings, "monitor_override_sx")
    monitor_override_sy = obs.obs_data_get_double(settings, "monitor_override_sy")
    monitor_override_dw = obs.obs_data_get_int(settings, "monitor_override_dw")
    monitor_override_dh = obs.obs_data_get_int(settings, "monitor_override_dh")
    debug_logs = obs.obs_data_get_bool(settings, "debug_logs")
    
    auto_zoom_enabled = obs.obs_data_get_bool(settings, "auto_zoom_enabled")
    auto_zoom_timeout = obs.obs_data_get_int(settings, "auto_zoom_timeout")
    auto_zoom_move_threshold = obs.obs_data_get_int(settings, "auto_zoom_move_threshold")
    auto_zoom_threshold_strategy = obs.obs_data_get_string(settings, "auto_zoom_threshold_strategy")
    auto_zoom_center_follow_on_click = obs.obs_data_get_bool(settings, "auto_zoom_center_follow_on_click")
    auto_zoom_center_follow_on_longpress = obs.obs_data_get_bool(settings, "auto_zoom_center_follow_on_longpress")
    
    cursor_image_path = obs.obs_data_get_string(settings, "cursor_image_path")
    cursor_image_clicking = obs.obs_data_get_string(settings, "cursor_image_clicking")
    cursor_image_dragging = obs.obs_data_get_string(settings, "cursor_image_dragging")
    cursor_source_name = obs.obs_data_get_string(settings, "cursor_source_name")
    smooth_factor = obs.obs_data_get_double(settings, "smooth_factor")
    smooth_factor_clicking = obs.obs_data_get_double(settings, "smooth_factor_clicking")
    cursor_scale = obs.obs_data_get_double(settings, "cursor_scale")
    click_scale = obs.obs_data_get_double(settings, "click_scale")
    click_duration = obs.obs_data_get_int(settings, "click_duration")
    drag_threshold = obs.obs_data_get_int(settings, "drag_threshold")
    click_anchor_x = obs.obs_data_get_double(settings, "click_anchor_x")
    click_anchor_y = obs.obs_data_get_double(settings, "click_anchor_y")
    hotspot_x = obs.obs_data_get_int(settings, "hotspot_x")
    hotspot_y = obs.obs_data_get_int(settings, "hotspot_y")
    cursor_follow_zoom = obs.obs_data_get_bool(settings, "cursor_follow_zoom")
    
    if source_name ~= old_source and is_obs_loaded then
        refresh_sceneitem(true)
    end
    
    if use_monitor_override then
        monitor_info = get_monitor_info(nil)
    end
    
    -- 根据设置启动/停止自动缩放定时器
    if auto_zoom_enabled then
        start_auto_zoom_timer()
    else
        stop_auto_zoom_timer()
    end
end

local function delayed_init()
    if not win_api_available then
        init_windows_api()
    end
    obs.timer_remove(delayed_init)
end

function script_load(settings)
    -- 在加载时尝试设置默认鼠标图标路径
    -- 如果用户还没有设置过，就尝试使用脚本目录的默认图标
    if obs.obs_data_get_string(settings, "cursor_image_path") == "" then
        local success, script_info = pcall(function()
            return obs.obs_script_get_info(0)
        end)
        if success and script_info and script_info.path then
            local script_dir = script_info.path:match("(.*/)") or script_info.path:match("(.*\\)")
            if script_dir then
                local default_cursor = script_dir .. "icons/cursor.png"
                -- 只设置值，不覆盖用户的选择
                obs.obs_data_set_string(settings, "cursor_image_path", default_cursor)
            end
        end
    end
    
    local current_scene = obs.obs_frontend_get_current_scene()
    is_obs_loaded = current_scene ~= nil
    if current_scene then
        obs.obs_source_release(current_scene)
    end
    
    hotkey_zoom_id = obs.obs_hotkey_register_frontend("smooth_cursor_zoom_toggle", 
        "放大到鼠标开关", on_toggle_zoom)
    
    hotkey_follow_id = obs.obs_hotkey_register_frontend("smooth_cursor_follow_toggle", 
        "跟随鼠标开关", on_toggle_follow)
    
    hotkey_cursor_id = obs.obs_hotkey_register_frontend("smooth_cursor_cursor_toggle", 
        "平滑鼠标开关", on_toggle_cursor)
    
    local arr = obs.obs_data_get_array(settings, "hotkey.zoom")
    obs.obs_hotkey_load(hotkey_zoom_id, arr)
    obs.obs_data_array_release(arr)
    
    arr = obs.obs_data_get_array(settings, "hotkey.follow")
    obs.obs_hotkey_load(hotkey_follow_id, arr)
    obs.obs_data_array_release(arr)
    
    arr = obs.obs_data_get_array(settings, "hotkey.cursor")
    obs.obs_hotkey_load(hotkey_cursor_id, arr)
    obs.obs_data_array_release(arr)
    
    obs.obs_frontend_add_event_callback(on_frontend_event)
    obs.timer_add(delayed_init, 500)
    
    log("Smooth Cursor Zoom v" .. VERSION .. " loaded")
end

function script_save(settings)
    if hotkey_zoom_id then
        local arr = obs.obs_hotkey_save(hotkey_zoom_id)
        obs.obs_data_set_array(settings, "hotkey.zoom", arr)
        obs.obs_data_array_release(arr)
    end
    
    if hotkey_follow_id then
        local arr = obs.obs_hotkey_save(hotkey_follow_id)
        obs.obs_data_set_array(settings, "hotkey.follow", arr)
        obs.obs_data_array_release(arr)
    end
    
    if hotkey_cursor_id then
        local arr = obs.obs_hotkey_save(hotkey_cursor_id)
        obs.obs_data_set_array(settings, "hotkey.cursor", arr)
        obs.obs_data_array_release(arr)
    end
end

function script_unload()
    is_cursor_enabled = false
    
    if cursor_timer_running then
        obs.timer_remove(on_cursor_timer)
        cursor_timer_running = false
    end
    
    -- 停止自动缩放定时器
    if auto_zoom_timer_running then
        obs.timer_remove(on_auto_zoom_timer)
        auto_zoom_timer_running = false
    end
    
    obs.timer_remove(delayed_init)
    release_sceneitem()
    
    if cursor_source then
        obs.obs_source_release(cursor_source)
        cursor_source = nil
    end
    
    win_point = nil
    win_api_available = false
    ffi = nil
    
    log("Smooth Cursor Zoom unloaded")
end
