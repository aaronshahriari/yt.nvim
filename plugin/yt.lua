if vim.g.loaded_yt_nvim then
  return
end
vim.g.loaded_yt_nvim = true

vim.api.nvim_create_user_command("Yt", function(o)
  require("yt").open(o.args)
end, { nargs = "*", desc = "Open YouTube home/search (yt.nvim)" })

vim.api.nvim_create_user_command("YtBuild", function()
  require("yt.download").download_or_build()
end, { desc = "Download or build the yt.nvim helper binary" })
