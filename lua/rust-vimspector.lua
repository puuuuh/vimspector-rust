local api = vim.api
local uv = vim.loop
local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local sorters = require('telescope.sorters')
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')

local commands = {
    test = { "test", "--no-run", "--message-format=json"},
    build = {"build", "--message-format=json"}
}

local function start_vimspector(filenames, args)
    local filename = nil;
    if #filenames == 1 then
        filename = filenames[1]
    else
        print("\n\n")
        local option_strings = {
            "Targets: "
        }
        for i, v in ipairs(filenames) do
            table.insert(option_strings, string.format("%d. %s", i, v))
        end
        local choice = vim.fn.inputlist(option_strings)
        if choice < 1 or choice > #filenames then
            return
        else
            filename = filenames[choice]
        end
    end

    if filename == nil then
        return
    end

    print(filename)

    vim.call("vimspector#LaunchWithSettings", { executable = filename, executable_args = table.concat(args, " ") } )
end

local function compile(command, args)
    table.insert(command, 2, "--message-format=json")
    if command[1] == "run" then
        command[1] = "build"
    elseif command[1] == "test" then
        table.insert(command, 3, "--no-run")
    end
    print(vim.inspect(command))

    local stdout = nil
    local stderr = nil
    local uv_err
    stdout, uv_err = uv.new_pipe(false)
    if uv_err then
        print('Failed to open stdout pipe: ' .. uv_err)
        return
    end

    stderr, uv_err = uv.new_pipe(false)
    if uv_err then
        print('Failed to open stderr pipe: ' .. uv_err)
        return
    end

    local handle, pid = uv.spawn("cargo",
        { stdio = { nil, stdout, stderr }, args = command},
        function(code, signal)
        end
    )

    local files = {}

    uv.read_start(stdout, function(err, data)
        assert(not err, err)
        if data then
            vim.schedule(vim.schedule_wrap(function()
                for line in data:gmatch("[^\n]+") do
                    local status, parsed = pcall(api.nvim_call_function,"json_decode", { line })
                    if not status then
                        print(line)
                        error(parsed)
                        return
                    end
                    if parsed.reason == "compiler-message" then
                        print(parsed.message.rendered)
                    elseif parsed.reason == "compiler-artifact" then
                        if parsed.executable then
                            files[#files+1] = parsed.executable
                        end
                    elseif parsed.reason == "build-finished" then
                        if not parsed.success then
                            error("Build failed, check messages")
                        end
                        if #files == 0 then
                            error("Executable file not found")
                        end
                        start_vimspector(files, args)
                    end
                end
            end))
        end
    end)

    return
end

local function getOptions(result, withTitle, withIndex)
    local option_strings = withTitle and {"Runnables: "} or {}

    for i, runnable in ipairs(result) do
        local str = withIndex and string.format("%d: %s", i, runnable.label) or
                        runnable.label
        table.insert(option_strings, str)
    end

    return option_strings
end

local function choose_target()
    local uri = vim.uri_from_bufnr(0)
    vim.lsp.buf_request(0, 'experimental/runnables', { textDocument = { uri = uri } },
        function (err, result)
            if err then error(tostring(err)) end

            local choices = getOptions(result, false, false)

            local function attach_mappings(bufnr, map)
                local function on_select()
                    local choice = action_state.get_selected_entry().index
                    compile(result[choice].args.cargoArgs, result[choice].args.executableArgs)

                    actions.close(bufnr)
                end

                map('n', '<CR>', on_select)
                map('i', '<CR>', on_select)

                -- Additional mappings don't push the item to the tagstack.
                return true
            end

            pickers.new({}, {
                prompt_title = "Runnables",
                finder = finders.new_table({results = choices}),
                sorter = sorters.get_generic_fuzzy_sorter(),
                previewer = nil,
                attach_mappings = attach_mappings
            }):find()
            for _, run in pairs(result) do
                print(run.label)
            end
        end
    )
end

local function debug(kind)
    choose_target()
    error()
    if commands[kind] == nil then
        error("Invalid kind. Supported: [test, build]")
    end

    compile(commands[kind])
end

return {
    debug = debug
}
