local api = vim.api;
local commands = {
    test = "cargo test --no-run --message-format=json",
    build = "cargo build --message-format=json"
}

local function compile(command)
    local res = io.popen(command, "r")
    local eof = false

    local filename = nil

    while not eof do
        local chunk = res:read()
        if not chunk then
            eof = true
        else
            local parsed = api.nvim_call_function("json_decode", { chunk })
            --tprint(parsed, 0)
            if parsed.reason == "compiler-message" then
                print(parsed.message.rendered)
            elseif parsed.reason == "compiler-artifact" then
                if parsed.executable then
                    filename = parsed["executable"]
                end
            elseif parsed.reason == "build-finished" then
                if not parsed.success then
                    return nil
                end
            end
        end
    end
    
    return filename
end

local function start_vimspector(filename)
    vim.call("vimspector#LaunchWithSettings", { executable = filename } )
end

local function debug(kind)
    if commands[kind] == nil then
        error("Invalid kind. Supported: [test, build]")
    end

    local file = compile(commands[kind])
    if file == nil then
        error("Executable file not found")
    end
    start_vimspector(file)
end

return {
    debug = debug
}
