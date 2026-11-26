const LIMIT = 20000;
const entries = new Map();
let native = null;
let nativeBroken = false;

function keyOf(request) {
  return typeof request === 'string' ? request : request.url;
}

function maxAge(response) {
  const match = /max-age=(\d+)/.exec(response.headers.get('cache-control') || '');
  return match ? Number(match[1]) : 60;
}

const memory = {
  async match(request) {
    const key = keyOf(request);
    const entry = entries.get(key);
    if (!entry) {
      return undefined;
    }
    if (entry.expires <= Date.now()) {
      entries.delete(key);
      return undefined;
    }
    return new Response(entry.body.slice(0), { status: entry.status, headers: entry.headers });
  },
  async put(request, response) {
    const key = keyOf(request);
    const body = await response.arrayBuffer();
    entries.delete(key);
    if (body.byteLength > 262144) {
      return;
    }
    entries.set(key, { body, status: response.status, headers: [...response.headers], expires: Date.now() + maxAge(response) * 1000 });
    while (entries.size > LIMIT) {
      entries.delete(entries.keys().next().value);
    }
  },
  async delete(request) {
    return entries.delete(keyOf(request));
  },
};

function fallback(name) {
  return async (...args) => {
    if (!nativeBroken && native) {
      try {
        return await native[name](...args);
      } catch (error) {
        if (!String(error && error.message).includes('No Cache')) {
          throw error;
        }
        nativeBroken = true;
      }
    }
    return memory[name](...args);
  };
}

const wrapped = { match: fallback('match'), put: fallback('put'), delete: fallback('delete') };

export function sharedCache() {
  if (!native && typeof caches !== 'undefined' && caches.default) {
    native = caches.default;
  }
  return wrapped;
}
