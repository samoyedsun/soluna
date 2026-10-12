/*
 * soluna_http.js - run emscripten_fetch() on the main browser thread.
 *
 * Why this file has to exist:
 *
 * The wasm-side extension module (ext.network) runs on an ltask pthread worker, and that worker
 * never returns to its JS event loop - it sits in Atomics.wait inside the futex layer. Measured
 * directly: a plain setTimeout() scheduled from the worker never fires, ever. Without Asyncify or
 * JSPI there is no way to yield out of the wasm frame, so *no* JS event can be delivered on that
 * thread.
 *
 * emscripten_fetch() delivers its result through exactly such an event (an XHR handler), and
 * emscripten_fetch_attr_t has no "run this callback on another thread" option the way
 * emscripten_websocket_* does. So a worker-side call gets its request onto the wire and then
 * never hears back - onsuccess simply never runs. (Also measured, the hard way.)
 *
 * The fix is the same one libwebsocket.js uses: get onto the main thread. Every
 * emscripten_websocket_* entry point is `__proxy: 'sync'`, which is why worker calls to them
 * land on the main browser thread. This is that trick, for fetch, in one function.
 *
 * So the pattern is: the worker builds the emscripten_fetch_attr_t (plain memory writes, no
 * thread constraint - wasm memory is shared), calls soluna_http_start(), and emscripten_fetch()
 * actually runs on the main thread. The onsuccess/onerror callbacks therefore also run on the
 * main thread, which is the same place libwebsocket delivers to. The extension module's callback
 * writes into a C11 atomic ring there, and the Lua worker drains it in poll().
 *
 * The attr pointer is the worker's; the main thread only reads it through the shared heap.
 */

mergeInto(LibraryManager.library, {
  // 'sync' + no __deps: this must not pull in the Fetch JS machinery, only call the C entry
  // point that is already linked in (-lfetch, see soluna_force_link_fetch.c).
  soluna_http_start__proxy: 'sync',
  soluna_http_start__sig: 'ppp',
  soluna_http_start: function (attrPtr, urlPtr) {
    return _emscripten_fetch(attrPtr, urlPtr);
  }
});
