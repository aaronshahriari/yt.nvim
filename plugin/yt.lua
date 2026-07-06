if vim.g.loaded_yt_nvim then
  return
end
vim.g.loaded_yt_nvim = true

vim.api.nvim_create_user_command("Yt", function(o)
  require("yt").open(o.args)
end, { nargs = "*", desc = "Search YouTube (yt.nvim)" })
