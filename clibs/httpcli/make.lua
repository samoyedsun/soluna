-- httpcli.http / httpcli.websocket 的构建胶水。源码在 3rd/httpcli/，形状照 clibs/datalist/make.lua。
--
-- 这个目录被根 make.lua:125-132 的循环自动发现，并把下面那个 `httpcli_src`
-- 无条件塞进 soluna.exe 的 deps —— 所以目标名必须正好是 "<目录名>_src"，
-- 对不上会在 configure 阶段 fatal（writer.lua:389）。
--
-- 模块**直接编进引擎**，不再是一个单独加载的 side module：所以这里
--   没有 lm:dll、没有产物拷贝、也不编 extlua/extlua.c。
-- 最后一条是硬要求：extlua.c 定义了一整套 lua_* 包装函数，编进来会跟引擎真正的
-- Lua 符号撞成重复定义。模块现在直接链真正的 lua_*，那个函数指针桥接用不着了。
--
-- 原来模块自己的 make.lua 里还有一件事没了：emcc 下要往主模块的导出表里
-- 塞一批 musl 函数（-Wl,-u/--export），那是给 side module 解析导入用的。
-- 现在同在一个模块里，直接链上就行。根 make.lua 里那段白名单也一起删掉了
-- （只留下 emscripten_fetch 一对，那是给引擎自己的 JS 库要的，跟这里无关）。

local lm = require "luamake"

lm.rootdir = lm.basedir / "3rd/httpcli"

-- Windows 上跑 -compiler emcc 时 lm.os 仍然是 windows，所以 emcc 要单独认，
-- 否则会按 msvc 走、把 winsock 那份编进 wasm。与模块原来的 make.lua 判法一致。
local function is_emcc()
	if lm.compiler == "emcc" then
		return true
	end
	if type(lm.cc) == "string" and lm.cc:find("emcc", 1, true) then
		return true
	end
	return false
end

local emcc = is_emcc()

-- net_sock / ws_common / http_common 是协议无关的那层，两个平台都要编。
-- 只有传输层分家：原生走 winsock / 手写 HTTP，web 走浏览器内建的 WebSocket
-- 和 emscripten_fetch。
local sources = {
	"net_sock.c",
	"websocket.c",
	"ws_common.c",
	"http.c",
	"http_common.c",
}
if emcc then
	sources[#sources + 1] = "ws_proto_wasm.c"
	sources[#sources + 1] = "http_proto_wasm.c"
else
	sources[#sources + 1] = "ws_proto.c"
	sources[#sources + 1] = "http_proto.c"
end

lm:source_set "httpcli_src" {
	sources = sources,
	includes = {
		-- Lua 头文件不在默认包含路径上，datalist / ltask 也都显式加这一条。
		-- 模块自己那几个 .h 是同目录的，靠 #include "" 的规则就能找到，不用加。
		lm.basedir / "3rd/lua",
	},
	-- winsock。web 上不要：emcc 分支编的是 ws_proto_wasm.c，根本不用 winsock。
	-- source_set 的 links 会经 writer.lua:353-358 收进 ldflags，
	-- 再经 update_ldflags 并给 exe，所以根 make.lua 不用为它加一个字。
	links = (lm.os == "windows" and not emcc) and { "Ws2_32" } or nil,
}
