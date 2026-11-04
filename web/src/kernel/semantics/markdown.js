// markdown 文本级语义（唯一实现）：宽松捕获、装载改写、保存还原、引用收集、落盘命名。
// 纯函数：不碰文件系统、不碰 DOM、不依赖宿主。存在性由壳通过 resolveResources 作答。
import { fileUrlFromPath, joinBase, normalizePath, percentDecodedPath } from './paths.js';

const IMAGE_PATTERN = /(!\[[^\]]*\]\()((?:[^()]|\([^()]*\))*?)\)/g;
const TITLE_PATTERN = /^\s*(.*?)\s+("[^"]*"|'[^']*')\s*$/;

export function isRemoteDestination(trimmed) {
  return trimmed === ''
    || trimmed.startsWith('http://')
    || trimmed.startsWith('https://')
    || trimmed.startsWith('data:')
    || trimmed.startsWith('#');
}

function unquoted(text) {
  if (typeof text !== 'string' || text.length < 2) return null;
  const first = text[0];
  const last = text[text.length - 1];
  if (first !== last || (first !== '"' && first !== "'")) return null;
  return text.slice(1, -1);
}

/** inner → {path, title}；解析不出合法形态返回 null（调用方保持原文） */
export function splitInner(inner) {
  const text = String(inner);
  if (text.startsWith('<')) {
    const close = text.indexOf('>');
    if (close < 0) return null;
    const path = text.slice(1, close);
    if (path.length === 0) return null;
    const rest = text.slice(close + 1).trim();
    if (rest.length === 0) return { path, title: '' };
    const title = unquoted(rest);
    if (title === null) return null;
    return { path, title };
  }
  const matched = TITLE_PATTERN.exec(text);
  if (matched) {
    const path = matched[1].trim();
    if (path.length === 0) return null;
    return { path, title: unquoted(matched[2]) ?? '' };
  }
  const path = text.trim();
  return path.length === 0 ? null : { path, title: '' };
}

export function wrappedIfNeeded(path) {
  return /[ ()]/.test(path) ? `<${path}>` : path;
}

/** 逐行处理，跳过 ``` / ~~~ 围栏内的内容（结束行须同字符且全为该字符） */
export function mapLinesOutsideFences(markdown, transform) {
  const lines = String(markdown).split('\n');
  const out = [];
  let inFence = false;
  let marker = '`';
  for (const line of lines) {
    const trimmed = line.trim();
    if (!inFence) {
      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        inFence = true;
        marker = trimmed[0];
        out.push(line);
        continue;
      }
      out.push(transform(line));
      continue;
    }
    if (trimmed.startsWith(marker) && [...trimmed].every((ch) => ch === marker)) {
      inFence = false;
    }
    out.push(line);
  }
  return out.join('\n');
}

/**
 * 对一行内所有 `![alt](path "title")` 应用 transform 并重组整行。
 * transform 返回 null/undefined 表示「不必改写」，该段保持原文（不做无害重组）。
 */
export function replaceImagesInLine(line, transform) {
  const matches = [...line.matchAll(IMAGE_PATTERN)];
  if (matches.length === 0) return line;
  let out = '';
  let cursor = 0;
  for (const match of matches) {
    const index = match.index ?? 0;
    const inner = splitInner(match[2]);
    if (!inner) continue;
    const newPath = transform(inner.path, inner.title);
    if (newPath === null || newPath === undefined) continue;
    out += line.slice(cursor, index);
    out += match[1];
    out += wrappedIfNeeded(newPath);
    if (inner.title.length > 0) out += ` "${inner.title}"`;
    out += ')';
    cursor = index + match[0].length;
  }
  out += line.slice(cursor);
  return out;
}

/** 装载前批量收集候选引用（去重、保持出现顺序），供壳 resolveResources 作答 */
export function collectImageRefs(markdown) {
  const refs = [];
  const seen = new Set();
  mapLinesOutsideFences(markdown, (line) => {
    replaceImagesInLine(line, (rawPath) => {
      const trimmed = rawPath.trim();
      if (!isRemoteDestination(trimmed) && !trimmed.startsWith('file://') && !seen.has(trimmed)) {
        seen.add(trimmed);
        refs.push(trimmed);
      }
      return null;
    });
    return line;
  });
  return refs;
}

/**
 * 装载改写：相对/根相对引用 → 壳给出的可加载 URL；缺失/远程/已 file:// 保持原文。
 * resources: { [ref]: {url, exists, isImage, paths} }，由壳以文件系统为准作答。
 */
export function applyForLoad(markdown, { resources = {} } = {}) {
  return mapLinesOutsideFences(markdown, (line) => replaceImagesInLine(line, (rawPath) => {
    const trimmed = rawPath.trim();
    if (isRemoteDestination(trimmed) || trimmed.startsWith('file://')) return null;
    const hit = resources[trimmed];
    if (!hit || !hit.exists || !hit.url) return null;
    return hit.url;
  }));
}

/** 保存还原：file:// → 文档目录内相对路径；目录外保留绝对路径（I2 的保存取值点） */
export function restoreForSave(markdown, { baseDir, style = 'posix' } = {}) {
  const base = normalizePath(baseDir, { style });
  const separator = style === 'win32' ? '\\' : '/';
  return mapLinesOutsideFences(markdown, (line) => replaceImagesInLine(line, (rawPath) => {
    const trimmed = rawPath.trim();
    if (!trimmed.startsWith('file://')) return null;
    const path = normalizePath(percentDecodedPath(trimmed.slice('file://'.length)), { style });
    if (base.length > 0 && path.startsWith(base + separator)) {
      return path.slice(base.length + 1);
    }
    return path;
  }));
}

/**
 * GC 引用收集：宁多保护不误删。
 * 壳为每个引用返回所有「真实存在」的候选绝对路径（字面写法 + 解码写法），这里取并集。
 */
export function collectResourceRefs(markdown, { resources = {}, style = 'posix' } = {}) {
  const paths = new Set();
  const addRef = (rawPath) => {
    const trimmed = rawPath.trim();
    if (trimmed.startsWith('file://')) {
      paths.add(normalizePath(percentDecodedPath(trimmed.slice('file://'.length)), { style }));
      return null;
    }
    if (isRemoteDestination(trimmed)) return null;
    const hit = resources[trimmed];
    const candidates = hit && Array.isArray(hit.paths) ? hit.paths : [];
    if (candidates.length > 0) {
      for (const candidate of candidates) {
        if (typeof candidate === 'string' && candidate.length > 0) {
          paths.add(normalizePath(candidate, { style }));
        }
      }
    }
    return null;
  };
  mapLinesOutsideFences(markdown, (line) => {
    replaceImagesInLine(line, addRef);
    return line;
  });
  return [...paths];
}

/** 壳计算引用候选时使用的绝对路径（字面 + 解码两个口径），与 last 实现同规则 */
export function refCandidates(ref, { baseDir, style = 'posix' } = {}) {
  const literal = joinBase(baseDir, ref, { style });
  const decoded = joinBase(baseDir, percentDecodedPath(ref), { style });
  return literal === decoded ? [literal] : [literal, decoded];
}

const MIME_EXTENSIONS = {
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/png': 'png',
  'image/gif': 'gif',
  'image/webp': 'webp',
  'image/bmp': 'bmp',
};

function extensionForMime(mime) {
  const normalized = String(mime || '').toLowerCase();
  if (MIME_EXTENSIONS[normalized]) return MIME_EXTENSIONS[normalized];
  const subtype = normalized.startsWith('image/') ? normalized.slice('image/'.length) : '';
  return subtype.replace(/[^a-z0-9]/g, '') || 'png';
}

/** 落盘命名：blob → img_NNN.ext（目录内最大序号 +1）；file → 保留原名，冲突加 -2/-3 */
export function nextResourceName({ existing = [], kind = 'blob', mime = '', preferredName = '' } = {}) {
  const taken = new Set(existing);
  if (kind === 'file' && preferredName.length > 0) {
    const dot = preferredName.lastIndexOf('.');
    const stem = dot > 0 ? preferredName.slice(0, dot) : preferredName;
    const ext = dot > 0 ? preferredName.slice(dot) : '';
    let candidate = preferredName;
    let index = 2;
    while (taken.has(candidate)) {
      candidate = `${stem}-${index}${ext}`;
      index += 1;
    }
    return candidate;
  }
  let maxSeq = 0;
  for (const name of taken) {
    const matched = /^img_(\d+)\./.exec(name);
    if (matched) maxSeq = Math.max(maxSeq, Number(matched[1]));
  }
  return `img_${String(maxSeq + 1).padStart(3, '0')}.${extensionForMime(mime)}`;
}

export { fileUrlFromPath, joinBase, normalizePath, percentDecodedPath };
