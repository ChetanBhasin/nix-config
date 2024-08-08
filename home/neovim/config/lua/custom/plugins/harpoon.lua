local module = {}

local conf = require("telescope.config").values

local function show_harpoon(harpoon_files)
    local file_paths = {}
    for _, item in ipairs(harpoon_files.items) do
        table.insert(file_paths, item.value)
    end

    require("telescope.pickers").new({}, {
        prompt_title = "Harpoon",
        finder = require("telescope.finders").new_table({ results = file_paths }),
        previewer = conf.file_previewer({}),
        sorter = conf.generic_sorter({}),
    }):find()
end

function module.show()
    local harpoon = require('harpoon')
    show_harpoon(harpoon:list())
end

function module.setup()
    require('harpoon'):setup()
end

function module.add()
    require('harpoon'):list():add()
end

function module.remove()
    require('harpoon'):list():remove()
end

function module.left()
    require('harpoon'):list():prev()
end

function module.right()
    require('harpoon'):list():next()
end

return module
