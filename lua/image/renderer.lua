local utils = require("image/utils")
local magick = require("image/magick")

---@param window_id number
---@return { x: number, y: number }
local get_global_offsets = function(window_id)
  local x = 0
  local y = 0
  -- if vim.opt.number then x = x + vim.opt.numberwidth:get() end
  -- if vim.opt.signcolumn ~= "no" then x = x + 2 end

  local opts = vim.wo[window_id]
  if not opts then return { x = x, y = y } end

  -- tabline
  if vim.opt.showtabline == 2 then y = y + 1 end

  -- winbar
  if opts.winbar ~= "" then y = y + 1 end

  -- gutters
  local wininfo = vim.fn.getwininfo(window_id)
  if wininfo and wininfo[1] then x = x + wininfo[1].textoff end

  return { x = x, y = y }
end

---@param term_size { cell_width: number, cell_height: number }
---@param image_width number
---@param image_height number
---@param width number
---@param height number
local adjust_to_aspect_ratio = function(term_size, image_width, image_height, width, height)
  local aspect_ratio = image_width / image_height
  local pixel_width = width * term_size.cell_width
  local pixel_height = height * term_size.cell_height
  local percent_orig_width = pixel_width / image_width
  local percent_orig_height = pixel_height / image_height

  if width == 0 and height ~= 0 then
    width = math.floor(height * aspect_ratio)
    return width, height
  end

  if height == 0 and width ~= 0 then
    height = math.floor(width / aspect_ratio)
    return width, height
  end

  if percent_orig_height > percent_orig_width then
    local new_height = math.ceil(pixel_width / aspect_ratio / term_size.cell_height)
    return width, new_height
  else
    local new_width = math.ceil(pixel_height * aspect_ratio / term_size.cell_width)
    return new_width, height
  end
end

-- Images get resized and cropped to fit in the context they are rendered in.
-- Each of these versions are written to the temp directory and cleared on reboot (on Linux at least).
-- This is where we keep track of the hashes of the resized and cropped versions of the images so we
-- can avoid processing and writing the same cropped/resized image variant multiple times.
local cache = {
  resized = {}, -- { [`${original_path}:${resize_hash}`]: string }
  cropped = {}, -- { [`${original_path}:${crop_hash}`]: string }
}

---@param image Image
local render = function(image)
  local state = image.global_state
  local term_size = utils.term.get_size()
  local image_rows = math.floor(image.image_height / term_size.cell_height)
  local image_columns = math.floor(image.image_width / term_size.cell_width)

  local original_x = image.geometry.x or 0
  local original_y = image.geometry.y or 0
  local x_offset = 0
  local y_offset = 0
  local width = image.geometry.width or 0
  local height = image.geometry.height or 0
  local window_offset_x = 0
  local window_offset_y = 0
  local bounds = {
    top = 0,
    right = term_size.screen_cols,
    bottom = term_size.screen_rows,
    left = 0,
  }
  local topfill = 0

  -- infer missing w/h component
  if width == 0 and height ~= 0 then width = math.ceil(height * image.image_width / image.image_height) end
  if height == 0 and width ~= 0 then height = math.ceil(width * image.image_height / image.image_width) end

  -- if both w/h are missing, use the image dimensions
  if width == 0 and height == 0 then
    width = image_columns
    height = image_rows
  end

  -- rendered size cannot be larger than the image itself
  width = math.min(width, image_columns)
  height = math.min(height, image_rows)

  -- screen max width/height
  width = math.min(width, term_size.screen_cols)
  height = math.min(height, term_size.screen_rows)

  -- utils.debug(("(1) x: %d, y: %d, width: %d, height: %d y_offset: %d"):format(original_x, original_y, width, height, y_offset))

  if image.window ~= nil then
    -- bail if the window is invalid
    local window = utils.window.get_window(image.window, {
      with_masks = state.options.window_overlap_clear_enabled,
      ignore_masking_filetypes = state.options.window_overlap_clear_ft_ignore,
    })
    if window == nil then return false end

    -- bail if the window is not visible
    if not window.is_visible then return false end

    -- bail if the window is overlapped
    if state.options.window_overlap_clear_enabled and #window.masks > 0 then return false end

    -- if the image is tied to a buffer the window must be displaying that buffer
    if image.buffer ~= nil and window.buffer ~= image.buffer then return false end

    -- get topfill and check fold status
    local current_win = vim.api.nvim_get_current_win()
    vim.api.nvim_command("noautocmd call nvim_set_current_win(" .. image.window .. ")")
    topfill = vim.fn.winsaveview().topfill
    local is_folded = vim.fn.foldclosed(original_y) ~= -1
    vim.api.nvim_command("noautocmd call nvim_set_current_win(" .. current_win .. ")")

    -- bail if the image is inside a fold
    if image.buffer and is_folded then
      -- utils.debug("inside fold", image.id)
      return false
    end

    -- global offsets
    local global_offsets = get_global_offsets(window.id)
    x_offset = global_offsets.x - window.scroll_x
    y_offset = global_offsets.y - window.scroll_y

    -- window offsets
    window_offset_x = window.x
    window_offset_y = window.y

    -- window bounds
    bounds = {
      top = window.y + global_offsets.y,
      right = window.x + window.width - global_offsets.x,
      bottom = window.y + window.height - global_offsets.y,
      left = window.x + global_offsets.x,
    }

    -- w/h can take at most 100% of the window
    width = math.min(width, window.width - original_x - x_offset)
    height = math.min(height, window.height - original_y - y_offset)

    -- global max window width/height percentage
    if type(state.options.max_width_window_percentage) == "number" then
      width = math.min(width, math.floor(window.width * state.options.max_width_window_percentage / 100))
    end
    if type(state.options.max_height_window_percentage) == "number" then
      height = math.min(height, math.floor(window.height * state.options.max_height_window_percentage / 100))
    end
  end

  -- utils.debug(("(2) x: %d, y: %d, width: %d, height: %d y_offset: %d"):format(original_x, original_y, width, height, y_offset))

  -- global max width/height
  if type(state.options.max_width) == "number" then width = math.min(width, state.options.max_width) end
  if type(state.options.max_height) == "number" then height = math.min(height, state.options.max_height) end

  width, height = adjust_to_aspect_ratio(term_size, image.image_width, image.image_height, width, height)

  if width <= 0 or height <= 0 then return false end

  -- utils.debug(("(3) x: %d, y: %d, width: %d, height: %d y_offset: %d"):format(original_x, original_y, width, height, y_offset))

  local absolute_x = original_x + x_offset + window_offset_x
  local absolute_y = original_y + y_offset + window_offset_y
  local prevent_rendering = false

  -- utils.debug(("(4) x: %d, y: %d, width: %d, height: %d y_offset: %d absolute_x: %d absolute_y: %d"):format( original_x, original_y, width, height, y_offset, absolute_x, absolute_y))

  if image.window and image.buffer then
    local win_info = vim.fn.getwininfo(image.window)[1]
    if not win_info then return false end
    local topline = win_info.topline
    local botline = win_info.botline

    -- bail if out of bounds
    if original_y + 1 < topline or original_y > botline then
      -- utils.debug("prevent rendering 1", image.id)
      prevent_rendering = true
    end

    -- extmark offsets
    if image.with_virtual_padding then
      -- bail if the image is above the top of the window at least by one line
      if topfill == 0 and original_y < topline then
        -- utils.debug("prevent rendering 2", image.id)
        prevent_rendering = true
      end

      -- bail if the image + its height is above the top of the window + topfill
      -- if y + height + 1 < topline + topfill then
      --   utils.debug("prevent rendering 3", image.id, {
      --     y = y,
      --     height = height,
      --     topline = topline,
      --     topfill = topfill,
      --   })
      --   prevent_rendering = true
      -- end

      -- bail if the image is below the bottom of the window
      if original_y > botline then
        -- utils.debug("prevent rendering 4", image.id)
        prevent_rendering = true
      end

      -- offset by topfill if the image started above the top of the window
      if not prevent_rendering then
        if topfill > 0 and original_y < topline then
          --
          absolute_y = absolute_y - (height - topfill)
        else
          -- offset by any pre-y virtual lines
          local extmarks = vim.tbl_map(
            function(mark)
              ---@diagnostic disable-next-line: deprecated
              local mark_id, mark_row, mark_col, mark_opts = unpack(mark)
              local virt_height = #(mark_opts.virt_lines or {})
              return { id = mark_id, row = mark_row, col = mark_col, height = virt_height }
            end,
            vim.api.nvim_buf_get_extmarks(
              image.buffer,
              -1,
              { topline - 1, 0 },
              { original_y - 1, 0 },
              { details = true }
            )
          )

          local offset = topfill
          for _, mark in ipairs(extmarks) do
            if mark.row + 1 ~= original_y then offset = offset + mark.height end
          end

          absolute_y = absolute_y + offset
        end
      end
    end

    -- folds
    local offset = 0
    local current_win = vim.api.nvim_get_current_win()
    -- TODO: can this be done without switching windows?
    vim.api.nvim_command("noautocmd call nvim_set_current_win(" .. image.window .. ")")

    if vim.wo.foldenable then
      local i = topline
      while i <= original_y do
        local fold_start, fold_end = vim.fn.foldclosed(i), vim.fn.foldclosedend(i)
        if fold_start ~= -1 and fold_end ~= -1 then
          -- utils.debug(("i: %d fold start: %d, fold end: %d"):format(i, fold_start, fold_end))
          offset = offset + (fold_end - fold_start)
          i = fold_end + 1
        else
          i = i + 1
        end
      end
    end
    vim.api.nvim_command("noautocmd call nvim_set_current_win(" .. current_win .. ")")
    -- utils.debug(("fold offset: %d"):format(offset))
    absolute_y = absolute_y - offset
  end

  if prevent_rendering then absolute_y = -999999 end

  -- clear out of bounds images
  if
    absolute_y + height <= bounds.top
    or absolute_y >= bounds.bottom
    or absolute_x + width <= bounds.left
    or absolute_x >= bounds.right
  then
    if image.is_rendered then
      -- utils.debug("deleting out of bounds image", { id = image.id, x = absolute_x, y = absolute_y, width = width, height = height, bounds = bounds })
      state.backend.clear(image.id, true)
    else
      state.images[image.id] = image
    end
    return true
  end

  -- compute final geometry and prevent useless rerendering
  local rendered_geometry = { x = absolute_x, y = absolute_y, width = width, height = height }

  -- handle crop/resize
  local pixel_width = width * term_size.cell_width
  local pixel_height = height * term_size.cell_height
  local crop_offset_top = 0
  local cropped_pixel_height = height * term_size.cell_height
  local needs_crop = false
  local needs_resize = false
  local initial_crop_hash = image.crop_hash
  local initial_resize_hash = image.resize_hash

  -- compute crop top/bottom
  -- crop top
  if absolute_y < bounds.top then
    local visible_rows = height - (bounds.top - absolute_y)
    cropped_pixel_height = visible_rows * term_size.cell_height
    crop_offset_top = (bounds.top - absolute_y) * term_size.cell_height
    if not state.backend.features.crop then absolute_y = bounds.top end
    needs_crop = true
  end

  -- crop bottom
  if absolute_y + height > bounds.bottom then
    cropped_pixel_height = (bounds.bottom - absolute_y + 1) * term_size.cell_height
    needs_crop = true
  end

  -- compute resize
  local resize_hash = ("%d-%d"):format(pixel_width, pixel_height)
  if image.image_width > pixel_width then needs_resize = true end

  -- TODO make this non-blocking

  -- resize
  if needs_resize then
    if image.resize_hash ~= resize_hash then
      local cached_path = cache.resized[image.path .. ":" .. resize_hash]

      -- try cache
      if cached_path then
        -- utils.debug(("using cached resized image %s"):format(cached_path))
        image.resized_path = cached_path
        image.resize_hash = resize_hash
      else
        -- perform resize
        local resized_image = magick.load_image(image.path)
        if resized_image then
          -- utils.debug(("resizing image %s to %dx%d"):format(image.path, pixel_width, pixel_height))
          --
          resized_image:set_format("png")
          resized_image:scale(pixel_width, pixel_height)

          local tmp_path = state.tmp_dir .. "/" .. utils.base64.encode(image.id) .. "-resized.png"
          resized_image:write(tmp_path)
          resized_image:destroy()

          image.resized_path = tmp_path
          image.resize_hash = resize_hash

          cache.resized[image.path .. ":" .. resize_hash] = tmp_path
        end
      end
    end
  else
    image.resized_path = image.path
    image.resize_hash = nil
  end

  -- crop
  local crop_hash = ("%d-%d-%d-%d"):format(0, crop_offset_top, pixel_width, cropped_pixel_height)
  if needs_crop then
    if (needs_resize and image.resize_hash ~= resize_hash) or image.crop_hash ~= crop_hash then
      local cached_path = cache.cropped[image.path .. ":" .. crop_hash]

      -- try cache;
      if cached_path then
        -- utils.debug(("using cached cropped image %s"):format(cached_path))
        image.cropped_path = cached_path
        image.crop_hash = crop_hash
      else
        -- perform crop
        if not state.backend.features.crop then
          -- utils.debug(("cropping image %s to %dx%d"):format(image.path, pixel_width, cropped_pixel_height))

          local cropped_image = magick.load_image(image.resized_path or image.path)
          cropped_image:set_format("png")
          cropped_image:crop(pixel_width, cropped_pixel_height, 0, crop_offset_top)

          local tmp_path = state.tmp_dir .. "/" .. utils.base64.encode(image.id) .. "-cropped.png"
          cropped_image:write(tmp_path)
          cropped_image:destroy()

          image.cropped_path = tmp_path
        end
        image.crop_hash = crop_hash

        cache.cropped[image.path .. ":" .. crop_hash] = image.cropped_path
      end
    end
  else
    image.cropped_path = image.resized_path
    image.crop_hash = nil
  end

  if
    image.is_rendered
    and image.rendered_geometry.x == rendered_geometry.x
    and image.rendered_geometry.y == rendered_geometry.y
    and image.rendered_geometry.width == rendered_geometry.width
    and image.rendered_geometry.height == rendered_geometry.height
    and image.crop_hash == initial_crop_hash
    and image.resize_hash == initial_resize_hash
  then
    -- utils.debug("skipping render", image.id)
    return true
  end

  -- utils.debug("redering to backend", image.id, { x = absolute_x, y = absolute_y, width = width, height = height, resize_hash = image.resize_hash, crop_hash = image.crop_hash, })

  image.bounds = bounds
  state.backend.render(image, absolute_x, absolute_y, width, height)
  image.rendered_geometry = rendered_geometry
  -- utils.debug("rendered", image)

  return true
end

return {
  get_global_offsets = get_global_offsets,
  render = render,
}
