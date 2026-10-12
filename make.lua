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
		-- (tools/link.py, map_to_js_libs). The wasm extension modules load their
		-- WebSocket through it, so it has to be in the main module.
		-- `fetch` is the same story for HTTP: libfetch.js for the JS side plus
		-- libfetch.a (system/lib/fetch/emscripten_fetch.c) for the C entry points.
		links = {
			"websocket",
			"fetch",
		},
		sources = {
			-- Nothing here is called; they only pin the libraries against tree-shaking.
			"src/platform/wasm/soluna_force_link_websocket.c",
			"src/platform/wasm/soluna_force_link_fetch.c",
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
			-- Side modules resolve every import out of the main module's export
			-- table (libdylink.js: `prop in wasmImports` first, else
			-- moduleExports). These are musl functions the wasm-side extension
			-- modules call; wasm-ld leaves them out of that table unless asked,
			-- and the dylink stub then throws "resolved is not a function" the
			-- first time the side module reaches one. `-u` pins them against
			-- GC (a main module that never calls snprintf would otherwise drop
			-- it), `--export` puts them in the table.
			"-Wl,-u,snprintf", "-Wl,--export=snprintf",
			"-Wl,-u,strcmp", "-Wl,--export=strcmp",
			"-Wl,-u,strncmp", "-Wl,--export=strncmp",
			"-Wl,-u,memchr", "-Wl,--export=memchr",
			"-Wl,-u,strlen", "-Wl,--export=strlen",
			"-Wl,-u,clock_gettime", "-Wl,--export=clock_gettime",
			-- Same reason, for the HTTP half of ext.network: these resolve out of
			-- the main module from the side module.
			"-Wl,-u,emscripten_fetch", "-Wl,--export=emscripten_fetch",
			"-Wl,-u,emscripten_fetch_attr_init", "-Wl,--export=emscripten_fetch_attr_init",
			"-Wl,-u,emscripten_fetch_close", "-Wl,--export=emscripten_fetch_close",
			"-Wl,-u,emscripten_fetch_get_response_headers_length", "-Wl,--export=emscripten_fetch_get_response_headers_length",
			"-Wl,-u,emscripten_fetch_get_response_headers", "-Wl,--export=emscripten_fetch_get_response_headers",
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
