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

vim.api.nvim_create_user_command("YtPlaylistNew", function(o)
  local name = o.args
  if name == "" then
    vim.ui.input({ prompt = "New playlist name: " }, function(input)
      if input and input ~= "" then
        require("yt").create_playlist(input)
      end
    end)
  else
    require("yt").create_playlist(name)
  end
end, { nargs = "*", desc = "Create a new empty yt.nvim playlist" })

vim.api.nvim_create_user_command("YtInstall", function()
  require("yt").install()
end, { desc = "Download the highlighted video for offline playback" })
