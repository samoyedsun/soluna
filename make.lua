local lm = require "luamake"
local fs = require "bee.filesystem"

lm:required_version "1.11"

local function detect_emcc()
	if lm.compiler == "emcc" then
		return true
	end
	if type(lm.cc) == "string" and lm.cc:find("emcc", 1, true) then
		return true
	end
	return false
end

local osplat = (function()
	if lm.os == "windows" then
		if lm.compiler == "gcc" then
			return "mingw"
		end
		if lm.cc == "clang-cl" then
			return "clang-cl"
		end
		return "msvc"
	end
	return lm.os
end)()

local plat = (function()
	if detect_emcc() then
		return "emcc"
	end
	return osplat
end)()

lm.platform = plat
lm.basedir = lm:path "."
lm.fs_basedir = fs.path(tostring(lm.basedir))
lm.bindir = ("bin/%s/%s"):format(plat, lm.mode)
lm.osbindir = ("bin/%s/%s"):format(osplat, lm.mode)

lm:conf {
	cxx = "c++20",
	clang = {
		c = "c11",
	},
	flags = {
		lm.mode ~= "debug" and "-O2",
	},
	msvc = {
		c = "c11",
		flags = {
			"-W3",
			"-utf-8",
			"-experimental:c11atomics",
			"/wd4244",
			"/wd4267",
			"/wd4305",
			"/wd4996",
			"/wd4018",
			"/wd4113",
		},
		defines = {
			"_CRT_SECURE_NO_WARNINGS",
			"_CRT_NONSTDC_NO_DEPRECATE",
			"_CRT_SECURE_NO_DEPRECATE"
		},
	},
	mingw = {
		c = "c99",
	},
	gcc = {
		c = "c11",
		flags = {
			"-Wall",
		},
		defines = {
			"_POSIX_C_SOURCE=199309L",
			"_GNU_SOURCE",
		},
		links = {
			"m",
			(lm.os ~= "windows" and lm.platform ~= "emcc") and "fontconfig",
		},
	},
	emcc = {
		c = "gnu11",
		flags = {
			"-Wall",
			"-pthread",
			"-fPIC",
			"--use-port=emdawnwebgpu",
			"-fwasm-exceptions",
		},
		links = {
			"idbfs.js",
		},
		ldflags = {
			"--use-port=emdawnwebgpu",
			"-s ALLOW_MEMORY_GROWTH",
			"-s FORCE_FILESYSTEM=1",
			"-s USE_PTHREADS=1",
			"-fwasm-exceptions",

			lm.mode == "debug" and "-gsource-map",
			lm.mode == "debug" and "-s EXCEPTION_STACK_TRACES=1",
			lm.mode == "debug" and "-s ASSERTIONS=2",
			-- lm.mode == "debug" and "-s SAFE_HEAP=1",
			lm.mode == "debug" and "-s STACK_OVERFLOW_CHECK=1",
			lm.mode == "debug" and "-s PTHREADS_DEBUG=1",
		},
		defines = {
			"_POSIX_C_SOURCE=200809L",
			"_GNU_SOURCE",
		},
	},
	defines = {
		-- lm.mode == "debug" and "DEBUGLOG",
		lm.mode == "debug" and "SOKOL_DEBUG",
	}
}

local deps = { "soluna_src" }

for path in fs.pairs(lm.fs_basedir / "clibs") do
	local name = path:stem():string()
	if name ~= "soluna" and name ~= "sample" and fs.exists(path / "make.lua") then
		local makefile = ("clibs/%s/make.lua"):format(name)
		lm:import(makefile)
		deps[#deps + 1] = name .. "_src"
	end
end

lm:import "clibs/soluna/make.lua"
lm:import "clibs/sample/make.lua"

lm:exe "soluna" {
	deps = deps,
	emcc = {
		-- `websocket` turns into -lwebsocket, which link.py maps to libwebsocket.js
		-- (tools/link.py, map_to_js_libs). 3rd/httpcli/ws_proto_wasm.c calls
		-- emscripten_websocket_* directly, so those are real references from wasm
		-- code and the library stays linked on its own.
		-- `fetch` is the same story for HTTP: libfetch.js for the JS side plus
		-- libfetch.a (system/lib/fetch/emscripten_fetch.c) for the C entry points.
		-- Both are needed by the module itself (it is compiled into this exe), not
		-- by any side module.
		links = {
			"websocket",
			"fetch",
		},
		ldflags = {
			"--js-library=src/platform/wasm/soluna_ime.js",
			"--js-library=src/platform/wasm/soluna_openurl.js",
			"--js-library=src/platform/wasm/soluna_http.js",
			"-s MODULARIZE=1",
			"-s EXPORT_ES6=1",
			"-s EXPORT_NAME=createApp",
			[=[-s EXPORTED_FUNCTIONS=[\"_main\"]]=],
			[=[-s EXPORTED_RUNTIME_METHODS=[\"FS\",\"FS_createPath\",\"FS_createDataFile\",\"IDBFS\"]]=],
			[=[-s "PTHREAD_POOL_SIZE=Math.max(2,navigator.hardwareConcurrency)"]=],
			"-s PTHREAD_POOL_SIZE_STRICT=2",
			"-s MAIN_MODULE=2",
			"-Wl,-u,emscripten_builtin_memalign",
			"-Wl,--export=emscripten_builtin_memalign",
			-- emscripten_fetch 得导出，是因为引擎自己的 JS 库要调它：soluna_http.js 的
			-- soluna_http_start 从 JS 侧调 `_emscripten_fetch(...)`，而 JS 调 wasm 得走
			-- 导出表。`-u` 也要留：C 侧没人调它，不钉住会被当成死代码丢掉。
			"-Wl,-u,emscripten_fetch", "-Wl,--export=emscripten_fetch",
			-- 这里以前还有另外 4 个 emscripten_fetch_* 和 6 个 musl 函数
			-- （snprintf / strcmp / strncmp / memchr / strlen / clock_gettime）
			-- 的 `-u` + `--export` 钉子，那是给 side module 解析导入用的。
			-- 现在另外 4 个 fetch 符号是 httpcli 里的 C 代码直接调的（有真实引用，
			-- 不用钉），那 6 个 musl 函数谁都不调，所以整块删掉。
		},
	},
}

lm:import "script/act_targets.lua"

lm:runlua "cc" {
	script = "script/compile_commands.lua",
	args = {
		"build/build.ninja",
		"compile_commands.json",
	},
	inputs = {
		"build/build.ninja",
		"script/compile_commands.lua",
	},
	outputs = {
		"compile_commands.json",
	},
}

lm:default "soluna"
