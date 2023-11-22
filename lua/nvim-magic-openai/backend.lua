local backend = {}

local completion = require('nvim-magic-openai._completion')
local log = require('nvim-magic-openai._log')
local buffer = require('nvim-magic._buffer')
local BackendMethods = {}

function BackendMethods:complete(lines, max_tokens, stops, success, fail)
   if type(stops) == 'table' and #stops == 0 then
      stops = nil -- OpenAI API does not accept empty array for stops
   end
   local prompt = table.concat(lines, '\n')
   log.fmt_debug(
      'Fetching async completion prompt_length=%s max_tokens=%s stops=%s',
      #prompt,
      max_tokens,
      tostring(stops)
   )

   local req_body = completion.new_request(prompt, self.model, max_tokens, stops)
   local req_body_json = vim.fn.json_encode(req_body)

   self.http:post(self.api_endpoint, req_body_json, self.get_api_key(), function(body)
      local compl = completion.extract_from(body)
      success(compl)
   end, fail)
end

function BackendMethods:chat(prompt, max_tokens, success, fail)
   stops = nil -- OpenAI API does not accept empty array for stops
   log.fmt_debug(
      'Fetching async completion prompt_length=%s max_tokens=%s stops=%s',
      #prompt,
      max_tokens,
      tostring(stops)
   )

   local req_body = completion.new_chat_request(self.chat_history, prompt, self.model, max_tokens, stops)
   local req_body_json = vim.fn.json_encode(req_body)

   self.http:post(self.api_endpoint, req_body_json, self.get_api_key(), function(body)
      local compl = completion.extract_from(body)
      table.insert(self.chat_history, {
         role = "user",
         content = prompt
      })
      table.insert(self.chat_history, {
         role = "assistant",
         content = compl
      })
      --print(compl)
      success(compl)
   end, fail)
end

function BackendMethods:chat_content_QA(prompt, filename, chunks, chunk_index, max_tokens, success, fail)
   stops = nil -- OpenAI API does not accept empty array for stops
   log.fmt_debug(
      'Fetching async completion prompt_length=%s max_tokens=%s stops=%s',
      #prompt,
      max_tokens,
      tostring(stops)
   )

   if chunk_index > #chunks then
      return
   end

   local req_body = completion.new_indexer_request(self.chat_index, chunks[chunk_index], prompt, self.model, max_tokens,
      stops)
   local req_body_json = vim.fn.json_encode(req_body)

   self.http:post(self.api_endpoint, req_body_json, self.get_api_key(), function(body)
      local compl = completion.extract_from(body)

      local ok, compl = pcall(vim.fn.json_decode, compl)

      if ok and compl.action == "add" then
         if compl.info then
            -- If the table is not full, insert the item
            if #self.chat_index < self.chat_index_max then
               table.insert(self.chat_index, compl.info)
            else
               -- If the table is full, overwrite the item at the current position
               self.chat_index[self.chat_index_pos + 1] = compl.info -- Lua uses 1-based indexing
            end

            -- Increment the pointer and take modulo 15 to ensure it stays within [0, 14]
            self.pointer = (self.chat_index_pos + 1) % self.chat_index_max
         end
      elseif ok and compl.action == "update" then
         if compl.item and compl.info then
            if type(compl.item) == "string" then
               compl.item = tonumber(compl.item)
            end
            if compl.info and self.chat_index[compl.item] then
               self.chat_index[compl.item] = compl.info -- update the content at this index
            end
         end
      elseif ok and compl.action == "nothing" then
         -- print("Action is 'nothing'")
      end

      if chunk_index == #chunks then
         -- Now, use the index and answer the question
         local req_body = completion.new_doc_qa_answer(self.chat_index, filename, prompt, self.model, max_tokens, stops)
         local req_body_json = vim.fn.json_encode(req_body)
         local percentage = (chunk_index / #chunks) * 100
         local formatted_percentage = string.format("%.2f%%", percentage)
         local update_msg = "Processed " ..
             chunk_index .. " out of " .. #chunks .. " chunks of the document... (" .. formatted_percentage .. ")"
         if chunk_index == 1 then
            buffer.append_end(self:get_chat_buffer(), update_msg)
         else
            buffer.reset_last(self:get_chat_buffer(), update_msg)
         end

         self.http:post(self.api_endpoint, req_body_json, self.get_api_key(), function(body)
            local compl = completion.extract_from(body)
            success(compl)
            table.insert(self.chat_history, {
               role = "user",
               content = prompt
            })
            table.insert(self.chat_history, {
               role = "assistant",
               content = compl
            })
         end, fail)
      elseif chunk_index < #chunks then
         local percentage = (chunk_index / #chunks) * 100
         local formatted_percentage = string.format("%.2f%%", percentage)
         local update_msg = "Processed " ..
             chunk_index .. " out of " .. #chunks .. " chunks of the document... (" .. formatted_percentage .. ")"
         if chunk_index == 1 then
            buffer.append_end(self:get_chat_buffer(), update_msg)
         else
            buffer.reset_last(self:get_chat_buffer(), update_msg)
         end
         self:chat_content_QA(prompt, filename, chunks, chunk_index + 1, max_tokens, success, fail)
      end
   end, fail)
end

function BackendMethods:gen_codebase_clarify_questions(prompt, max_tokens, success, fail)
   stops = nil -- OpenAI API does not accept empty array for stops
   log.fmt_debug(
      'Fetching async completion prompt_length=%s max_tokens=%s stops=%s',
      #prompt,
      max_tokens,
      tostring(stops)
   )
   local req_body = completion.new_codebase_gen_clarify_request(prompt, self.model, max_tokens,
      stops)
   local req_body_json = vim.fn.json_encode(req_body)

   self.http:post(self.api_endpoint, req_body_json, self.get_api_key(), function(body)
      local compl = completion.extract_from(body)
      print(compl)
      local ok, compl = pcall(vim.fn.json_decode, compl)
      --print(compl)
      if ok then
         success(compl)
      else
         fail(compl)
      end
   end, fail)
end

function BackendMethods:gen_codebase_file_listing(prompt, clarify, max_tokens, success, fail)
   stops = nil -- OpenAI API does not accept empty array for stops
   log.fmt_debug(
      'Fetching async completion prompt_length=%s max_tokens=%s stops=%s',
      #prompt,
      max_tokens,
      tostring(stops)
   )
   local req_body = completion.new_codebase_gen_file_listing(prompt, clarify, self.model, max_tokens,
      stops)
   local req_body_json = vim.fn.json_encode(req_body)

   self.http:post(self.api_endpoint, req_body_json, self.get_api_key(), function(body)
      local compl = completion.extract_from(body)
      local ok, compl = pcall(vim.fn.json_decode, compl)
      --print(compl)
      if ok then
         success(compl)
      else
         fail(compl)
      end
   end, fail)
end

-- Create the folder or subfolder if it doesn't already exist
local function create_folder(path)
   local folder = path:match("(.-)[^%/]+$") -- Extract folder path from file path
   print("create_folder path: " .. path .. ", folder: " .. folder)
   if folder then
      -- Use the os.execute function to run the mkdir shell command
      os.execute("mkdir -p " .. path)
   end
end

-- Write JSON string to file
local function write_string_to_file(file_name, string)
   -- Check if file_name contains any slashes
   if file_name:find("/") then
      -- Strip away the last part after the last slash to get the directory path
      local dir_path = file_name:match("(.*)/")
      create_folder(dir_path) -- Create folder if it doesn't exist
   end

   local file = io.open(file_name, "w") -- Open a file in write mode
   if file then                         -- if file successfully opened
      -- Check if the string has three occurrences of the character "`"
      file:write(string)
      file:close()
   else
      print("Couldn't open file for writing")
   end
end

function BackendMethods:gen_codebase_file(prompt, clarify, listing, index, max_tokens, success, fail)
   stops = nil -- OpenAI API does not accept empty array for stops
   log.fmt_debug(
      'Fetching async completion prompt_length=%s max_tokens=%s stops=%s',
      #prompt,
      max_tokens,
      tostring(stops)
   )

   local files = listing.files
   local file = files[index]

   local req_body = completion.new_codebase_gen_file_request(prompt, clarify, files, file, self.model, max_tokens,
      stops)
   local req_body_json = vim.fn.json_encode(req_body)
   local count = index
   local percentage = ((count-1) / #files) * 100
   local formatted_percentage = string.format("%.2f%%", percentage)

   buffer.reset_last(self:get_chat_buffer(), "Processing - building (" .. formatted_percentage .. ") " .. file.name)
   self.http:post(self.api_endpoint, req_body_json, self.get_api_key(), function(body)
      local compl = completion.extract_from(body)
      local count = index
      write_string_to_file(file.name, compl)
      local percentage = ((count) / #files) * 100
      local formatted_percentage = string.format("%.2f%%", percentage)

      buffer.reset_last(self:get_chat_buffer(), "Processing - building (" .. formatted_percentage .. ") writing to file: " .. file.name)
      self:gen_codebase_file_doc(prompt, compl, listing, index, max_tokens, function()
         buffer.reset_last(self:get_chat_buffer(), "Processing - building (" .. formatted_percentage .. ") generated doc for: " .. file.name)

         -- Write JSON string to file
         local data = {}
         data["QA"] = clarify
         data["listing"] = listing

         local json = vim.fn.json_encode(data)
         local file = io.open(".magic_file_listing.json", "w") -- Open a file in write mode
         if file then                                          -- if file successfully opened
            file:write(json)
            file:close()
         else
            print("Couldn't open file for writing")
         end

         if index >= #files then
            success()
         else
            os.execute("sleep 50")
            self:gen_codebase_file(prompt, clarify, listing, index + 1, max_tokens, success, fail)
         end
      end, fail)
   end, fail)
end

function BackendMethods:gen_codebase_file_doc(prompt, content, listing, index, max_tokens, success, fail)
   stops = nil -- OpenAI API does not accept empty array for stops
   log.fmt_debug(
      'Fetching async completion prompt_length=%s max_tokens=%s stops=%s',
      #prompt,
      max_tokens,
      tostring(stops)
   )
   local files = listing.files
   local file = files[index]

   local req_body = completion.new_codebase_gen_minify_file_request(file.name, content, self.model, max_tokens,
      stops)
   local req_body_json = vim.fn.json_encode(req_body)

   self.http:post(self.api_endpoint, req_body_json, self.get_api_key(), function(body)
      local compl = completion.extract_from(body)
      local count = index
      local percentage = ((2 * count + 1) / (#files * 2)) * 100
      local formatted_percentage = string.format("%.2f%%", percentage)

      listing.files[index]["info"] = compl
      buffer.reset_last(self:get_chat_buffer(), "Processing - building (" .. formatted_percentage .. ") documented: " .. file.name)
      success()
   end, fail)
end

function BackendMethods:get_chat_length()
   return #self.chat_history
end

function BackendMethods:set_chat_buffer(bufno)
   self.chat_buffer = bufno
end

function BackendMethods:get_chat_buffer(bufno)
   return self.chat_buffer
end

function BackendMethods:chat_reset()
   self.chat_history = {}
   self.chat_index = {}
   self.chat_index_pos = 0
end

function BackendMethods:indexer_reset()
   self.chat_index = {}
   self.chat_index_pos = 0
end

function BackendMethods:add_to_suggestions_history(suggestion)
    local already_exists = false

    -- Check if the suggestion already exists in the history
    for _, existing_suggestion in ipairs(self.suggestions_history) do
        if existing_suggestion == suggestion then
            already_exists = true
            break
        end
    end

    -- Insert the suggestion only if it doesn't exist
    if not already_exists then
        table.insert(self.suggestions_history, 1, suggestion)
        self.suggestions_index = nil 
    end
end

function BackendMethods:get_suggestion_by_index(index)
    if index >= 1 and index <= #self.suggestions_history then
        return self.suggestions_history[index]
    else
        return nil -- or some error handling
    end
end

function BackendMethods:get_suggestions_history_length()
    return #self.suggestions_history
end

function BackendMethods:get_suggestions_arrow_down()
    if #self.suggestions_history == 0 then return nil end
    if self.suggestions_index == nil or self.suggestions_index <= 1 then
        self.suggestions_index = #self.suggestions_history
    else
        self.suggestions_index = self.suggestions_index - 1
    end
    return self.suggestions_history[self.suggestions_index]
end

function BackendMethods:get_suggestions_arrow_up()
    if #self.suggestions_history == 0 then return nil end
    if self.suggestions_index == nil or self.suggestions_index >= #self.suggestions_history then
        self.suggestions_index = 1
    else
        self.suggestions_index = self.suggestions_index + 1
    end
    return self.suggestions_history[self.suggestions_index]
end

local BackendMt = { __index = BackendMethods }

function backend.new(api_endpoint, model, http, api_key_fn)
   return setmetatable({
      api_endpoint = api_endpoint,
      get_api_key = api_key_fn,
      http = http,
      model = model,
      chat_history = {},
      chat_index = {},
      chat_index_pos = 0,
      chat_index_max = 16,
      chat_buffer = 0,
      suggestions_history = {},
      suggestions_index = nil,
   }, BackendMt)
end

return backend
