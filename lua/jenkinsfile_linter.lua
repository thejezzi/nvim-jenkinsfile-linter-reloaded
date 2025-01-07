local Job = require("plenary.job")
local log = require("plenary.log").new({ plugin = "jenkinsfile-linter", level = "info" })

local user = os.getenv("JENKINS_USER_ID") or os.getenv("JENKINS_USERNAME")
local password = os.getenv("JENKINS_PASSWORD")
local token = os.getenv("JENKINS_API_TOKEN") or os.getenv("JENKINS_TOKEN")
local jenkins_url = os.getenv("JENKINS_URL") or os.getenv("JENKINS_HOST")
local namespace_id = vim.api.nvim_create_namespace("jenkinsfile-linter")
local insecure = os.getenv("JENKINS_INSECURE") and "--insecure" or ""
local validated_msg = "Jenkinsfile successfully validated."

local function on_error(err)
  if err then
    log.error(err)
  end
end

local function on_success(err, data)
  if not err then
    if data == validated_msg then
      vim.diagnostic.reset(namespace_id, 0)
      vim.notify(validated_msg, vim.log.levels.INFO)
    else
      -- We only want to grab the msg, line, and col. We just throw
      -- everything else away. NOTE: That only one seems to ever be
      -- returned so this in theory will only ever match at most once per
      -- call.
      --WorkflowScript: 46: unexpected token: } @ line 46, column 1.
      local msg, line_str, col_str = data:match("WorkflowScript.+%d+: (.+) @ line (%d+), column (%d+).")
      if line_str and col_str then
        local line = tonumber(line_str) - 1
        local col = tonumber(col_str) - 1

        local diag = {
          bufnr = vim.api.nvim_get_current_buf(),
          lnum = line,
          end_lnum = line,
          col = col,
          end_col = col,
          severity = vim.diagnostic.severity.ERROR,
          message = msg,
          source = "jenkinsfile linter",
        }

        vim.diagnostic.set(namespace_id, vim.api.nvim_get_current_buf(), { diag })
      end
    end
  else
    vim.notify("Something went wront when trying to valide your file, check the logs.", vim.log.levels.ERROR)
    log.error(err)
  end
end

local validate_job = function()
  local args = {
    "--user",
    user .. ":" .. (token or password),
    "-X",
    "POST",
    "-F",
    "jenkinsfile=<" .. vim.fn.expand("%:p"),
    jenkins_url .. "/pipeline-model-converter/validate",
  }

  if #insecure > 0 then
    table.insert(args, 1, insecure)
  end

  return Job:new({
    command = "curl",
    args = args,
    on_stderr = vim.schedule_wrap(on_error),
    on_stdout = vim.schedule_wrap(on_success),
  })
end

local function check_creds()
  if user == nil then
    return false, "JENKINS_USER_ID is not set, please set it"
  end
  if password == nil and token == nil then
    return false, "JENKINS_PASSWORD or JENKINS_API_TOKEN need to be set, please set one"
  end
  if jenkins_url == nil then
    return false, "JENKINS_URL is not set, please set it"
  end
  return true
end

local function validate()
  local ok, msg = check_creds()
  if not ok and msg then
    vim.notify(msg, vim.log.levels.ERROR)
    return
  end
  validate_job():start()
end

return {
  validate = validate,
  check_creds = check_creds,
}
