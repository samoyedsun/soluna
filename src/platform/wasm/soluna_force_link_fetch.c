/*
 * soluna_force_link_fetch.c - force emscripten's Fetch library into the main module.
 *
 * This file exists for exactly one reason, and it is not dead code: do not delete it.
 *
 * Same trick as soluna_force_link_websocket.c, and for the same reason. The engine has no HTTP
 * client of its own; the wasm-side extension module does the fetching, and a side module can
 * only resolve imports out of the main module's export table. So the library has to be linked
 * into soluna.wasm even though no engine code calls it - and `-lfetch` on its own is not
 * enough, because at -O2 nothing references these symbols and the linker drops them.
 *
 * Taking the address of each entry point emits one wasm relocation per symbol, which is the
 * "someone uses this" signal the linker wants. The array is never called.
 *
 * `fetch` is both a system library (system/lib/fetch/emscripten_fetch.c, giving the C
 * entry points) and a JS library (libfetch.js, giving the response-header readers), which is
 * why the list below mixes the two.
 *
 * The signatures differ, so everything is cast to void*. Only addresses are taken, never
 * called, which makes the conversion legal in GNU C (-Wall is silent about it).
 */

#include <emscripten.h>
#include <emscripten/fetch.h>

/* Provided by soluna_http.js. Declared here because the only thing that has to reference it is
 * the address-taken array below - nothing calls it from the engine itself. */
emscripten_fetch_t *soluna_http_start(emscripten_fetch_attr_t *attr, const char *url);

EMSCRIPTEN_KEEPALIVE
void *soluna_force_link_fetch[] = {
	(void *)emscripten_fetch_attr_init,
	(void *)emscripten_fetch,
	(void *)emscripten_fetch_close,
	(void *)emscripten_fetch_get_response_headers_length,
	(void *)emscripten_fetch_get_response_headers,
	/* The JS shim that puts emscripten_fetch on the main browser thread; without a reference
	 * here the --js-library function is dead code and gets dropped, and the side module's
	 * import of it fails to resolve. */
	(void *)soluna_http_start,
};
