const sourceUrl = process.env.BOOK_SOURCE_7268_URL ||
  'https://www.yckceo.com/yuedu/shuyuan/json/id/7268.json';
const sourceFile = process.env.BOOK_SOURCE_7268_FILE || '';
const email = process.env.SHUSHAN_EMAIL || '';
const password = process.env.SHUSHAN_PASSWORD || '';
const keyword = process.env.BOOK_SOURCE_KEYWORD || '我在精神病院学斩神';
const preferredSource = process.env.SHUSHAN_SOURCE || '番茄小说';
const timeoutMs = Number(process.env.BOOK_SOURCE_TIMEOUT_MS || '20000');

if (!email || !password) {
  console.error('Missing SHUSHAN_EMAIL or SHUSHAN_PASSWORD');
  process.exit(1);
}

function headers() {
  return {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Accept': 'application/json, text/plain, */*',
    'X-Novel-Token': 'SHUSAN_READ_2025'
  };
}

async function fetchWithTimeout(url, init = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { ...init, signal: controller.signal });
    const text = await response.text();
    if (!response.ok) throw new Error(`${response.status} ${response.statusText}: ${text.slice(0, 160)}`);
    return text;
  } finally {
    clearTimeout(timer);
  }
}

async function fetchJson(url, init = {}) {
  return JSON.parse(await fetchWithTimeout(url, init));
}

async function loadSource() {
  let text = '';
  if (sourceFile) {
    const fs = await import('node:fs/promises');
    text = await fs.readFile(sourceFile, 'utf8');
  } else {
    text = await fetchWithTimeout(sourceUrl, { headers: headers() });
  }
  const value = JSON.parse(text);
  return Array.isArray(value) ? value[0] : value;
}

function hostCandidates(source) {
  const raw = `${source.bookSourceUrl || ''}\n${source.loginUrl || ''}\n${source.jsLib || ''}`;
  const found = [...raw.matchAll(/https?:\/\/[^'"`\s,)]+vossc\.com/ig)].map(item => item[0]);
  return [...new Set([...found, 'https://v1.vossc.com', 'https://v2.vossc.com', 'https://v3.vossc.com',
    'https://v4.vossc.com', 'http://1.94.248.5:7001'])];
}

async function login(hosts) {
  const body = `email=${encodeURIComponent(email)}&password=${encodeURIComponent(password)}`;
  let lastError = '';
  for (const host of hosts) {
    try {
      const root = await fetchJson(`${host}/login`, {
        method: 'POST',
        headers: {
          ...headers(),
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        body
      });
      const apiKey = String(root?.data?.user?.api_key || '');
      if (root.code === 200 && apiKey) {
        return { host, apiKey, member: Boolean(root?.data?.user?.is_member) };
      }
      lastError = `${host} code=${root.code} message=${root.message || ''}`;
    } catch (error) {
      lastError = `${host} ${String(error?.message || error)}`;
    }
  }
  throw new Error(`login failed: ${lastError}`);
}

function arrayData(root) {
  if (Array.isArray(root?.data)) return root.data;
  if (root?.data) return [root.data];
  return [];
}

async function search(host, sourceName) {
  const url = `${host}/search?login=search&key=${encodeURIComponent(keyword)}&page=1` +
    (sourceName ? `&source=${encodeURIComponent(sourceName)}` : '');
  const root = await fetchJson(url, { headers: headers() });
  return arrayData(root);
}

function fanqieDetailUrl(bookId) {
  return `https://api5-normal-sinfonlineb.fqnovel.com/reading/bookapi/multi-detail/v/?aid=1967&iid=1` +
    `&version_code=999&book_id=${encodeURIComponent(bookId)}`;
}

function firstUsableBook(list) {
  return list.find(item => item && (item.book_url || item.book_id || item.bookId) && (item.title || item.book_name));
}

async function main() {
  const source = await loadSource();
  const loginState = await login(hostCandidates(source));
  console.log(`LOGIN ok host=${loginState.host} member=${loginState.member} apiKeyLength=${loginState.apiKey.length}`);

  let books = await search(loginState.host, preferredSource);
  console.log(`SEARCH preferredSource=${preferredSource || '(none)'} count=${books.length}`);
  if (books.length === 0 && preferredSource) {
    books = await search(loginState.host, '');
    console.log(`SEARCH fallbackSource=(none) count=${books.length}`);
  }
  const book = firstUsableBook(books);
  if (!book) throw new Error('search returned no usable book');
  const bookName = String(book.title || book.book_name || book.bookName || '');
  const bookSource = String(book.source || preferredSource || '');
  const bookId = String(book.book_id || book.bookId || '');
  const rawUrl = String(book.book_url || book.url || '') || (bookId ? fanqieDetailUrl(bookId) : '');
  console.log(`BOOK name=${bookName} source=${bookSource} hasUrl=${Boolean(rawUrl)} bookId=${bookId}`);

  const detail = await fetchJson(`${loginState.host}/details?source=${encodeURIComponent(bookSource)}` +
    `&url=${encodeURIComponent(rawUrl)}&name=${encodeURIComponent(bookName)}`, { headers: headers() });
  const detailData = detail.data || {};
  console.log(`DETAIL code=${detail.code} title=${detailData.title || detailData.book_name || ''} tab=${detailData.tab || ''}`);

  const tab = String(detailData.tab || book.tab || 'novel');
  const catalog = await fetchJson(`${loginState.host}/catalog`, {
    method: 'POST',
    headers: {
      ...headers(),
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ source: bookSource, url: rawUrl, name: bookName, tab })
  });
  const chapters = arrayData(catalog).filter(item => item && item.isVolume !== true && item.cid);
  console.log(`CATALOG code=${catalog.code} count=${chapters.length}`);
  const chapter = chapters[0];
  if (!chapter) throw new Error('catalog returned no readable chapter');

  const chapterUrl = String(chapter.url || '');
  const matchUrl = chapterUrl || rawUrl;
  const finalBookId = (matchUrl.match(/book_id=(\d{19})\b/) || [])[1] || bookId;
  const itemId = (matchUrl.match(/item_id=(\d+)/) || [])[1] || String(chapter.cid);
  const secret = Buffer.from(loginState.apiKey).toString('base64');
  const content = await fetchJson(`${loginState.host}/chapter?cid=${encodeURIComponent(String(chapter.cid))}` +
    `&source=${encodeURIComponent(bookSource)}&device=android&book_id=${encodeURIComponent(finalBookId)}` +
    `&item_id=${encodeURIComponent(itemId)}&key=${encodeURIComponent(secret)}&version=11`, { headers: headers() });
  const contentText = String(content?.content || content?.data?.content || content?.data || '');
  console.log(`CONTENT status=${content.status ?? ''} code=${content.code ?? ''} encryptedLength=${contentText.length}`);
  if (contentText.includes('版本不受支持') || contentText.length < 100) {
    throw new Error(`content response is not usable: ${contentText.slice(0, 80)}`);
  }
}

await main();
