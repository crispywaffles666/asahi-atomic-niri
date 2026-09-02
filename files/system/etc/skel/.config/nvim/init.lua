-- filetype detection for sudoedit temp files
vim.filetype.add({
	pattern = {
		["/var/tmp/.*"] = function(path, bufnr)
			local basename = vim.fn.fnamemodify(path, ":t")
			local original = basename:match("^(.-)%.[^.]+$")
			if original then
				return vim.filetype.match({ filename = "/etc/" .. original, buf = bufnr })
			end
		end,
	},
})
vim.treesitter.language.register("javascript", "strudel")
vim.g.mapleader = " "

-- bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

-- plugins
require("lazy").setup({
	{ "junegunn/fzf", build = false },
	"junegunn/fzf.vim",
	"tpope/vim-commentary",
	"tpope/vim-surround",
	"mbbill/undotree",
	"Aasim-A/scrollEOF.nvim",
	"stevearc/conform.nvim",
	"sphamba/smear-cursor.nvim",
	{ "saghen/blink.cmp", version = "1.*" },
	{ "akinsho/bufferline.nvim", dependencies = "nvim-tree/nvim-web-devicons" },
	{ "Mofiqul/dracula.nvim", priority = 1000 },

	{
		"romus204/tree-sitter-manager.nvim",
		config = function()
			require("tree-sitter-manager").setup({
				ensure_installed = {
					"lua",
					"python",
					"bash",
					"html",
					"css",
					"json",
					"yaml",
					"toml",
					"javascript",
					"typescript",
					"tsx",
					"markdown",
					"markdown_inline",
				},
			})
		end,
	},

	{
		"mikavilpas/yazi.nvim",
		version = "*",
		event = "VeryLazy",
		dependencies = {
			{ "nvim-lua/plenary.nvim", lazy = true },
		},
	},

	{
		"MeanderingProgrammer/render-markdown.nvim",
		ft = "markdown",
		dependencies = {
			"nvim-tree/nvim-web-devicons",
		},
		config = function()
			require("render-markdown").setup({})
		end,
	},

	{
		"goolord/alpha-nvim",
		config = function()
			local dashboard = require("alpha.themes.dashboard")
			dashboard.section.header.val = {
				" ███▄    █ ▓█████  ▒█████   ██▒   █▓ ██▓ ███▄ ▄███▓",
				" ██ ▀█   █ ▓█   ▀ ▒██▒  ██▒▓██░   █▒▓██▒▓██▒▀█▀ ██▒",
				"▓██  ▀█ ██▒▒███   ▒██░  ██▒ ▓██  █▒░▒██▒▓██    ▓██░",
				"▓██▒  ▐▌██▒▒▓█  ▄ ▒██   ██░  ▒██ █░░░██░▒██    ▒██ ",
				"▒██░   ▓██░░▒████▒░ ████▓▒░   ▒▀█░  ░██░▒██▒   ░██▒",
				"░ ▒░   ▒ ▒ ░░ ▒░ ░░ ▒░▒░▒░    ░ ▐░  ░▓  ░ ▒░   ░  ░",
				"░ ░░   ░ ▒░ ░ ░  ░  ░ ▒ ▒░    ░ ░░   ▒ ░░ ░░      ░",
				"   ░   ░ ░    ░   ░ ░ ░ ▒       ░░   ▒ ░   ░      ░ ",
			}
			dashboard.section.buttons.val = {
				dashboard.button("n", "  New file", "<cmd>ene <BAR> startinsert<CR>"),
				dashboard.button("b", "  Browse files", "<cmd>lua require('yazi').yazi()<CR>"),
				dashboard.button("r", "  Recent files", "<cmd>History<CR>"),
				dashboard.button("f", "  Find file", "<cmd>Files<CR>"),
				dashboard.button("t", "  Find text", "<cmd>Rg<CR>"),
				dashboard.button("c", "  Config", "<cmd>e ~/.config/nvim/init.lua<CR>"),
				dashboard.button("q", "  Quit", "<cmd>qa<CR>"),
			}
			dashboard.config.layout = {
				{ type = "padding", val = 9 },
				dashboard.section.header,
				{ type = "padding", val = 1 },
				dashboard.section.buttons,
			}
			vim.api.nvim_set_hl(0, "AlphaHeader", { fg = "#bd93f9" })
			dashboard.section.header.opts.hl = "AlphaHeader"
			vim.api.nvim_set_hl(0, "DashGreen", { fg = "#50fa7b", bold = true })
			for _, button in ipairs(dashboard.section.buttons.val) do
				button.opts.hl_shortcut = "DashGreen"
			end
			require("alpha").setup(dashboard.config)
		end,
	},

	-- lsp
	"williamboman/mason.nvim",
	{
		"neovim/nvim-lspconfig",
		config = function()
			local capabilities = require("blink.cmp").get_lsp_capabilities()
			vim.lsp.config("pyright", { capabilities = capabilities })
			vim.lsp.config("bashls", { capabilities = capabilities })
			vim.lsp.config("cssls", { capabilities = capabilities })
			vim.lsp.config("html", { capabilities = capabilities })
			vim.lsp.config("yamlls", { capabilities = capabilities })
			vim.lsp.config("jsonls", { capabilities = capabilities })
			vim.lsp.config("taplo", { capabilities = capabilities })
			vim.lsp.config("vtsls", { capabilities = capabilities })
			vim.lsp.enable({ "pyright", "bashls", "cssls", "html", "yamlls", "jsonls", "taplo", "vtsls" })
		end,
	},

	{
		"crispywaffles666/nvim-strudel",
		ft = "strudel",
		build = 'cd server && npm install --ignore-scripts && printf \'%s\' \'var E=require("events").EventEmitter;function I(){E.call(this)}I.prototype=Object.create(E.prototype);I.prototype.getPortCount=function(){return 0};I.prototype.getPortName=function(){return""};I.prototype.openPort=function(){};I.prototype.closePort=function(){};I.prototype.ignoreTypes=function(){};function O(){}O.prototype.getPortCount=function(){return 0};O.prototype.getPortName=function(){return""};O.prototype.openPort=function(){};O.prototype.closePort=function(){};O.prototype.sendMessage=function(){};module.exports={Input:I,Output:O,input:I,output:O};\' > node_modules/midi/midi.js && npm run build',
		config = function()
			require("strudel").setup({
				audio = { output = "none" },
				lsp = { enabled = false },
			})
			-- Browser sends highlight data synced to audio; disable nvim-strudel's own text highlights
			require("strudel.client").clear_callbacks("active")
		end,
	},

	{
		"crispywaffles666/strudel.nvim",
		name = "strudel-browser",
		build = "PUPPETEER_SKIP_DOWNLOAD=1 npm install && npm install yargs@18",
		lazy = true,
	},
})

-- settings
vim.opt.mouse = "a"
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.incsearch = true
vim.opt.hlsearch = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.autoindent = true
vim.opt.termguicolors = true
vim.opt.completeopt = "menuone,noselect"
vim.opt.backspace = "indent,eol,start"
vim.opt.clipboard = "unnamedplus"
vim.opt.guicursor = "a:block"
vim.opt.undofile = true
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.g.undotree_SetFocusWhenToggle = 1
vim.opt.scrolloff = 7
vim.opt.wrap = false

vim.g.clipboard = {
	name = "OSC 52",
	copy = {
		["+"] = require("vim.ui.clipboard.osc52").copy("+"),
		["*"] = require("vim.ui.clipboard.osc52").copy("*"),
	},
	paste = {
		["+"] = require("vim.ui.clipboard.osc52").paste("+"),
		["*"] = require("vim.ui.clipboard.osc52").paste("*"),
	},
}

vim.cmd("colorscheme dracula")
vim.cmd("filetype plugin indent on")

require("smear_cursor").setup()
require("scrollEOF").setup({
	insert_mode = true,
})
require("bufferline").setup({
	options = {
		always_show_bufferline = false,
	},
})

-- transparent bg
vim.api.nvim_set_hl(0, "Normal", { bg = "NONE" })
vim.api.nvim_set_hl(0, "NormalFloat", { bg = "NONE" })
vim.api.nvim_set_hl(0, "Pmenu", { bg = "#1a1b26", fg = "#f8f8f2" })
vim.api.nvim_set_hl(0, "PmenuSel", { bg = "#44475a", fg = "#f8f8f2", bold = true })

-- fix md rendering
vim.api.nvim_set_hl(0, "RenderMarkdownH1Bg", { bg = "#44475a", fg = "#bd93f9", bold = true })
vim.api.nvim_set_hl(0, "RenderMarkdownH2Bg", { bg = "#44475a" })
vim.api.nvim_set_hl(0, "RenderMarkdownH3Bg", { bg = "#44475a" })
vim.api.nvim_set_hl(0, "RenderMarkdownH4Bg", { bg = "#44475a" })
vim.api.nvim_set_hl(0, "RenderMarkdownH5Bg", { bg = "#44475a", fg = "#f1fa8c" })
vim.api.nvim_set_hl(0, "RenderMarkdownH6Bg", { bg = "#44475a" })

-- strudel treesitter highlighting + comment syntax
vim.api.nvim_create_autocmd("FileType", {
	pattern = "strudel",
	callback = function()
		vim.treesitter.start(0, "javascript")
		vim.bo.commentstring = "// %s"
	end,
})

-- line wrapping for markdown
vim.api.nvim_create_autocmd("FileType", {
	pattern = "markdown",
	callback = function()
		vim.opt_local.wrap = true
		vim.opt_local.linebreak = true
	end,
})

-- mason setup
require("mason").setup()

-- completion setup
require("blink.cmp").setup({
	keymap = {
		["<Tab>"] = { "select_next", "fallback" },
		["<S-Tab>"] = { "select_prev", "fallback" },
		["<CR>"] = { "accept", "fallback" },
		["<C-\\>"] = { "cancel", "fallback" },
	},
	sources = {
		default = { "lsp", "path", "buffer" },
	},
	completion = {
		menu = {
			auto_show = false,
		},
		trigger = {
			show_on_backspace = false,
			show_on_backspace_in_keyword = false,
			show_on_backspace_after_accept = false,
			show_on_backspace_after_insert_enter = false,
		},
	},
	fuzzy = { implementation = "lua" },
	enabled = function()
		return vim.bo.filetype ~= "strudel"
	end,
})


require("conform").setup({
	formatters_by_ft = {
		python = { "ruff_format" },
		sh = { "shfmt" },
		bash = { "shfmt" },
		css = { "prettierd" },
		html = { "prettierd" },
		json = { "prettierd" },
		yaml = { "prettierd" },
		toml = { "taplo" },
		lua = { "stylua" },
		javascript = { "prettierd" },
		typescript = { "prettierd" },
		javascriptreact = { "prettierd" },
		typescriptreact = { "prettierd" },
	},
	format_on_save = function(bufnr)
		if vim.bo[bufnr].filetype == "strudel" then
			return false
		end
		return { timeout_ms = 500, lsp_format = "fallback" }
	end,
})

-- keybinds
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")
vim.keymap.set("n", "<C-z>", "u")
vim.keymap.set("i", "<C-z>", "<Esc>ui")
vim.keymap.set("n", "<C-s>", "<cmd>w<CR>")
vim.keymap.set("i", "<C-s>", "<Esc><cmd>w<CR>a")
vim.keymap.set("n", "<S-Tab>", "<cmd>BufferLineCyclePrev<CR>")
vim.keymap.set("n", "<C-t>", function()
	require("yazi").yazi()
end)
-- ctrl-q closes buffers/tabs if any, quits otherwise
vim.keymap.set("n", "<C-q>", function()
	if #vim.fn.getbufinfo({ buflisted = 1 }) > 1 then
		vim.cmd("bd")
	else
		vim.cmd("q")
	end
end)
vim.keymap.set("i", "<C-q>", function()
	if #vim.fn.getbufinfo({ buflisted = 1 }) > 1 then
		vim.cmd("bd")
	else
		vim.cmd("q")
	end
end)

-- less functions touch clipboard
vim.keymap.set("n", "x", '"_x')
vim.keymap.set("n", "s", '"_s')
vim.keymap.set("v", "<BS>", '"_d')

-- line jump (ctrl+arrows and ctrl+h/l)
vim.keymap.set("n", "<C-Left>", "^")
vim.keymap.set("n", "<C-Right>", "$")
vim.keymap.set("n", "<C-h>", "^")
vim.keymap.set("n", "<C-l>", "$")
vim.keymap.set("i", "<C-Left>", "<Esc>^i")
vim.keymap.set("i", "<C-Right>", "<Esc>$a")
vim.keymap.set("i", "<C-h>", "<Esc>^i")
vim.keymap.set("i", "<C-l>", "<Esc>$a")
vim.keymap.set("v", "<C-Left>", "^")
vim.keymap.set("v", "<C-Right>", "$")
vim.keymap.set("v", "<C-h>", "^")
vim.keymap.set("v", "<C-l>", "$")

-- scrolling
vim.keymap.set("n", "<C-Up>", "<C-u>")
vim.keymap.set("n", "<C-Down>", "<C-d>")
vim.keymap.set("n", "<C-k>", "<C-u>")
vim.keymap.set("n", "<C-j>", "<C-d>")
vim.keymap.set("i", "<C-Up>", "<Esc><C-u>i")
vim.keymap.set("i", "<C-Down>", "<Esc><C-d>i")
vim.keymap.set("i", "<C-k>", "<Esc><C-u>i")
vim.keymap.set("i", "<C-j>", "<Esc><C-d>i")
vim.keymap.set("v", "<C-Up>", "<C-u>")
vim.keymap.set("v", "<C-Down>", "<C-d>")
vim.keymap.set("v", "<C-k>", "<C-u>")
vim.keymap.set("v", "<C-j>", "<C-d>")
vim.keymap.set({ "n", "i", "v" }, "<M-Up>", "<Esc>gg")
vim.keymap.set({ "n", "i", "v" }, "<M-Down>", "<Esc>G")

-- undotree
vim.keymap.set("n", "<C-u>", "<cmd>UndotreeToggle<CR>")
vim.keymap.set("v", "<C-u>", "<cmd>UndotreeToggle<CR>")
vim.api.nvim_create_autocmd("FileType", {
	pattern = "undotree",
	callback = function()
		vim.keymap.set("n", "<Esc>", "<cmd>UndotreeToggle<CR>", { buffer = true })
	end,
})
-- tab: switch between undotree panel and buffer if open, otherwise cycle tabs
vim.keymap.set("n", "<Tab>", function()
	local undotree_open = false
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].filetype == "undotree" then
			undotree_open = true
			break
		end
	end

	if undotree_open then
		if vim.bo.filetype == "undotree" or vim.bo.filetype == "diff" then
			vim.cmd("wincmd l")
		else
			vim.cmd("UndotreeFocus")
		end
	else
		vim.cmd("BufferLineCycleNext")
	end
end)

-- format
vim.keymap.set("n", "<C-f>", function()
	require("conform").format()
end)
vim.keymap.set("i", "<C-f>", function()
	require("conform").format()
end)

-- cycle search results with enter
vim.keymap.set("n", "<CR>", function()
	if vim.v.hlsearch == 1 then
		return "n"
	else
		return "<CR>"
	end
end, { expr = true })

vim.keymap.set("n", "<S-CR>", function()
	if vim.v.hlsearch == 1 then
		return "N"
	else
		return "<S-CR>"
	end
end, { expr = true })

-- hide line numbers
vim.keymap.set("n", "<C-n>", function()
	vim.opt.number = not vim.opt.number:get()
	vim.opt.relativenumber = not vim.opt.relativenumber:get()
end)

-- select all
vim.keymap.set("n", "<C-a>", "ggVG")
vim.keymap.set("i", "<C-a>", "<Esc>ggVG")
vim.keymap.set("v", "<C-a>", "ggVG")

-- cut+copy
vim.keymap.set("v", "<C-x>", "d")
vim.keymap.set("v", "<C-c>", "y")

-- strudel browser audio (talks directly to gruvw/strudel.nvim's launch.js)
local sb = { job_id = nil, ready = false, bufnr = nil, last_content = nil, preview_job = nil }
local sb_hl_ns = vim.api.nvim_create_namespace("strudel_browser_hl")
local function sb_send(msg)
	if sb.job_id then
		vim.fn.chansend(sb.job_id, msg .. "\n")
	end
end
local function sb_apply_highlights(json_str)
	if not sb.bufnr or not vim.api.nvim_buf_is_valid(sb.bufnr) then
		return
	end
	vim.api.nvim_buf_clear_namespace(sb.bufnr, sb_hl_ns, 0, -1)
	local ok, locs = pcall(vim.json.decode, json_str)
	if not ok or type(locs) ~= "table" then
		return
	end
	local line_count = vim.api.nvim_buf_line_count(sb.bufnr)
	for _, loc in ipairs(locs) do
		local sl, sc, el, ec = loc[1] - 1, loc[2] - 1, loc[3] - 1, loc[4] - 1
		if sl >= 0 and sl < line_count and el < line_count then
			local line_text = vim.api.nvim_buf_get_lines(sb.bufnr, sl, sl + 1, false)[1] or ""
			sc = math.min(sc, #line_text)
			ec = math.min(ec, #line_text)
			if sc < ec or sl ~= el then
				pcall(vim.api.nvim_buf_set_extmark, sb.bufnr, sb_hl_ns, sl, sc, {
					end_row = el,
					end_col = ec,
					hl_group = "StrudelActive",
					priority = 200,
				})
			end
		end
	end
end
local function sb_sync_buffer()
	if not sb.job_id or not sb.ready or not sb.bufnr then
		return
	end
	if not vim.api.nvim_buf_is_valid(sb.bufnr) then
		return
	end
	local lines = vim.api.nvim_buf_get_lines(sb.bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")
	if content ~= sb.last_content then
		sb.last_content = content
		sb_send("STRUDEL_CONTENT:" .. vim.base64.encode(content))
	end
end
local function sb_launch_browser()
	local script = vim.fn.stdpath("data") .. "/lazy/strudel-browser/js/launch-core.js"
	local cache = vim.fn.expand("~/.cache/strudel-nvim")
	vim.fn.delete(cache .. "/SingletonLock")
	vim.fn.delete(cache .. "/SingletonCookie")
	vim.fn.delete(cache .. "/SingletonSocket")
	sb.job_id = vim.fn.jobstart({ "node", script, "--browser-exec-path=/usr/bin/brave" }, {
		on_stdout = function(_, data)
			for _, line in ipairs(data or {}) do
				if line:match("^STRUDEL_HIGHLIGHTS:") then
					sb_apply_highlights(line:sub(#"STRUDEL_HIGHLIGHTS:" + 1))
				elseif line:match("^STRUDEL_EVAL_ERROR:") then
					local err_b64 = line:sub(#"STRUDEL_EVAL_ERROR:" + 1)
					local ok, decoded = pcall(function()
						return vim.base64.decode(err_b64)
					end)
					vim.notify("strudel-browser eval error: " .. (ok and decoded or err_b64), vim.log.levels.ERROR)
				elseif line:match("^STRUDEL_READY") then
					sb.ready = true
					vim.notify("strudel-browser: ready", vim.log.levels.INFO)
					sb_sync_buffer()
					vim.api.nvim_create_augroup("StrudelBrowserSync", { clear = true })
					vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
						group = "StrudelBrowserSync",
						buffer = sb.bufnr,
						callback = sb_sync_buffer,
					})
				end
			end
		end,
		on_stderr = function(_, data)
			for _, line in ipairs(data or {}) do
				if line ~= "" then
					vim.notify("strudel-browser: " .. line, vim.log.levels.ERROR)
				end
			end
		end,
		on_exit = function()
			if sb.bufnr and vim.api.nvim_buf_is_valid(sb.bufnr) then
				vim.api.nvim_buf_clear_namespace(sb.bufnr, sb_hl_ns, 0, -1)
			end
			sb.job_id = nil
			sb.ready = false
			sb.bufnr = nil
			sb.last_content = nil
			pcall(vim.api.nvim_del_augroup_by_name, "StrudelBrowserSync")
		end,
	})
end
function sb.launch()
	if sb.job_id then
		return
	end
	local script = vim.fn.stdpath("data") .. "/lazy/strudel-browser/js/launch-core.js"
	if vim.fn.filereadable(script) == 0 then
		vim.notify("strudel-browser not installed — run :Lazy install strudel-browser", vim.log.levels.ERROR)
		return
	end
	sb.bufnr = vim.api.nvim_get_current_buf()
	if sb.preview_job then
		sb_launch_browser()
		return
	end
	sb.preview_job = vim.fn.jobstart({ "pnpm", "run", "preview" }, {
		cwd = vim.fn.expand("~/strudel"),
		on_stdout = function(_, data)
			for _, line in ipairs(data or {}) do
				if line:match("localhost") and not sb.job_id then
					vim.schedule(sb_launch_browser)
				end
			end
		end,
		on_stderr = function(_, data)
			for _, line in ipairs(data or {}) do
				if line:match("localhost") and not sb.job_id then
					vim.schedule(sb_launch_browser)
				end
			end
		end,
		on_exit = function()
			sb.preview_job = nil
		end,
	})
end
function sb.update()
	sb_sync_buffer()
	sb_send("STRUDEL_UPDATE")
end
function sb.stop()
	sb_send("STRUDEL_STOP")
	if sb.bufnr and vim.api.nvim_buf_is_valid(sb.bufnr) then
		vim.api.nvim_buf_clear_namespace(sb.bufnr, sb_hl_ns, 0, -1)
	end
end
function sb.quit()
	sb_send("STRUDEL_QUIT")
	if sb.preview_job then
		vim.fn.jobstop(sb.preview_job)
		sb.preview_job = nil
	end
end

-- strudel (nvim-strudel for highlighting, strudel-browser for audio)
vim.keymap.set("n", "<leader>sl", function()
	vim.cmd("StrudelPlay")
	if not sb.job_id then
		sb.launch()
	end
end)
vim.keymap.set("n", "<leader>sq", function()
	vim.cmd("StrudelDisconnect")
	if sb.job_id then
		sb.quit()
	end
end)
vim.keymap.set("n", "<leader>st", "<cmd>StrudelPause<CR>")
vim.keymap.set("n", "<leader>ss", function()
	vim.cmd("StrudelStop")
	if sb.job_id then
		sb.stop()
	end
end)
vim.keymap.set("n", "<leader>se", "<cmd>StrudelEval<CR>")
vim.keymap.set("n", "<leader>sp", "<cmd>StrudelPianoroll<CR>")
local function strudel_eval()
	vim.cmd("StrudelEval")
	if not sb.job_id then
		sb.launch()
	elseif sb.ready then
		sb.update()
	end
end
local function strudel_stop()
	vim.cmd("StrudelStop")
	if sb.job_id then
		sb.stop()
	end
end
vim.keymap.set({ "n", "i" }, "<C-CR>", strudel_eval)
vim.keymap.set({ "n", "i" }, "<C-BS>", strudel_stop)

-- toggle comments (C-_ is how most terminals encode C-/)
vim.keymap.set("n", "<C-/>", "<cmd>Commentary<CR>")
vim.keymap.set("n", "<C-_>", "<cmd>Commentary<CR>")
vim.keymap.set("v", "<C-/>", ":Commentary<CR>")
vim.keymap.set("v", "<C-_>", ":Commentary<CR>")
vim.keymap.set("i", "<C-/>", "<Esc><cmd>Commentary<CR>a")
vim.keymap.set("i", "<C-_>", "<Esc><cmd>Commentary<CR>a")
