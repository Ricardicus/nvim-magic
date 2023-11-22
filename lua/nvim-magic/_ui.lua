-- interacting with the user
local ui = {}

local Input = require('nui.input')
local Popup = require('nui.popup')
local event = require('nui.utils.autocmd').event

function ui.notify(msg, log_level, opts)
	vim.notify('nvim-magic: ' .. msg, log_level, opts)
end

function ui.pop_up(lines, filetype, border_text, keymaps)
	local popup = Popup({
		enter = true,
		focusable = true,
		border = {
			style = 'rounded',
			highlight = 'Bold',
			text = border_text,
		},
		position = '50%',
		size = {
			width = '80%',
			height = '60%',
		},
		buf_options = {
			modifiable = true,
			readonly = false,
			--filetype = filetype,
			buftype = 'nofile',
		},
		win_options = {
			number = true,
		},
	})
	popup:mount()
	popup:on(event.BufLeave, function()
		popup:unmount()
	end)

	for _, v in ipairs(keymaps) do
		popup:map(unpack(v))
	end

	vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, lines)
end

function ui.prompt_input(title, keymaps, backend, on_submit)
	local input = Input({
		position = '20%',
		size = {
			width = '60%',
			height = '60%',
		},
		relative = 'editor',
		border = {
			-- highlight = 'MyHighlightGroup',
			style = 'single',
			text = {
				top = title,
				top_align = 'center',
			},
		},
		win_options = {
			winblend = 0,
			winhighlight = 'Normal:Normal',
		},
	}, {
		prompt = '> ',
		default_value = '',
		on_close = function() end,
		on_submit = on_submit,
	})
	input:mount()
	input:on(event.BufLeave, function()
		input:unmount()
	end)

  -- Function to update buffer content
  local function update_buffer_content(content)
    local bufnr = input.bufnr 
    vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, {content})
  end

  -- Additional keymaps for Up and Down arrow keys
  local additional_keymaps = {
    -- Up arrow key
    {'n', '<Up>', function()
      -- Logic for when Up arrow is pressed
      local suggestion = backend:get_suggestions_arrow_up()
      if suggestion then
        suggestion = "> " .. suggestion
        update_buffer_content(suggestion)
      end
    end},

    -- Down arrow key
    {'n', '<Down>', function()
      -- Logic for when Down arrow is pressed
      local suggestion = backend:get_suggestions_arrow_down()
      if suggestion then
        suggestion = "> " .. suggestion
        update_buffer_content(suggestion)
      end
    end},
  }

  -- Adding your original keymaps
  for _, v in ipairs(keymaps) do
    input:map(unpack(v))
  end

	for _, v in ipairs(additional_keymaps) do
		input:map(unpack(v))
	end
end

return ui
