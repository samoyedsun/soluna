/*
 * soluna_force_link_websocket.c - force emscripten's WebSocket JS library into the main module.
 *
 * This file exists for exactly one reason, and it is not dead code: do not delete it.
 *
 * `-lwebsocket` (see the `links` entry in make.lua) only *registers* libwebsocket.js as a
 * candidate; what actually decides whether it ends up in soluna.js is whether any wasm code
 * references its symbols. The engine itself has no WebSocket code at all, so nothing does -
 * and at -O2 the whole library gets tree-shaken away (measured: 0 websocket symbols in the
 * generated glue with `-lwebsocket` alone). But the wasm-side extension module has to resolve
 * emscripten_websocket_* out of the main module, so the library must be linked in first.
 *
 * Taking the address of every entry point below emits one wasm relocation per symbol, which is
 * precisely the "someone uses this" signal the linker looks for. The array itself is never
 * called; only its initializer matters.
 *
 * The signatures differ, so there is no single function-pointer type to use - everything is
 * cast to void*. Only addresses are taken, never called, which makes the conversion legal in
 * GNU C (-Wall is silent about it).
 */

#include <emscripten.h>
#include <emscripten/websocket.h>

EMSCRIPTEN_KEEPALIVE
void *soluna_force_link_websocket[] = {
	(void *)emscripten_websocket_is_supported,
	(void *)emscripten_websocket_new,
	(void *)emscripten_websocket_send_utf8_text,
	(void *)emscripten_websocket_send_binary,
	(void *)emscripten_websocket_close,
	(void *)emscripten_websocket_delete,
	(void *)emscripten_websocket_get_ready_state,
	(void *)emscripten_websocket_set_onopen_callback_on_thread,
	(void *)emscripten_websocket_set_onerror_callback_on_thread,
	(void *)emscripten_websocket_set_onclose_callback_on_thread,
	(void *)emscripten_websocket_set_onmessage_callback_on_thread,
};
