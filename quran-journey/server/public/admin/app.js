// The Quran Journey - content management dashboard (vanilla JS, CSP-safe: no inline code).
const state = { token: sessionStorage.getItem('qj_token'), user: null, view: 'overview', sources: [], scholars: [] };
const root = document.getElementById('root');

// ---------- helpers ----------
function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'class') el.className = v;
    else if (k === 'value') el.value = v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat()) {
    if (c === null || c === undefined || c === false) continue;
    el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return el;
}
async function api(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(state.token ? { Authorization: `Bearer ${state.token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (res.status === 401 && state.user) { logout(); throw new Error('Session expired. Please sign in again.'); }
  if (res.status === 204) return null;
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `Request failed (${res.status})`);
  return data;
}
const can = (role) => ({ user: 0, editor: 1, reviewer: 2, admin: 3 })[state.user?.role] >= ({ user: 0, editor: 1, reviewer: 2, admin: 3 })[role];
const fmt = (iso) => (iso ? new Date(iso).toLocaleString() : '—');
const pill = (s) => h('span', { class: `pill ${s}` }, s.replace(/_/g, ' '));
const ref = (i) => `${i.surah}:${i.start_ayah}${i.end_ayah !== i.start_ayah ? '–' + i.end_ayah : ''}`;
function message(el, text, ok = false) { el.replaceChildren(text ? h('div', { class: `msg ${ok ? 'ok' : 'err'}` }, text) : ''); }
function logout() { state.token = null; state.user = null; sessionStorage.removeItem('qj_token'); render(); }

// ---------- login ----------
function loginView() {
  const msg = h('div');
  const email = h('input', { type: 'email', autocomplete: 'username', required: true });
  const pw = h('input', { type: 'password', autocomplete: 'current-password', required: true });
  const form = h('form', {
    class: 'card login',
    onsubmit: async (e) => {
      e.preventDefault();
      try {
        const r = await api('POST', '/api/auth/login', { email: email.value, password: pw.value });
        if (!['editor', 'reviewer', 'admin'].includes(r.user.role)) throw new Error('This account has no content-management role.');
        state.token = r.token; state.user = r.user; sessionStorage.setItem('qj_token', r.token); render();
      } catch (err) { message(msg, err.message); }
    },
  },
  h('h1', {}, 'The Quran Journey'), h('p', { class: 'sub' }, 'Content management'),
  h('label', {}, 'Email'), email, h('label', {}, 'Password'), pw, msg,
  h('div', { class: 'row mt' }, h('button', { class: 'btn', type: 'submit' }, 'Sign in')));
  return form;
}

// ---------- shell ----------
const VIEWS = [
  ['overview', 'Review queue', 'editor'], ['content', 'Study content', 'editor'], ['sources', 'Sources', 'editor'],
  ['scholars', 'Scholars', 'editor'], ['groupings', 'Study groupings', 'editor'], ['surahs', 'Surahs & verses', 'editor'],
  ['translations', 'Translations', 'editor'], ['audio', 'Audio reciters', 'editor'], ['users', 'Users', 'admin'], ['audit', 'Audit log', 'admin'],
];
async function render() {
  if (!state.token) return root.replaceChildren(loginView());
  if (!state.user) {
    try { state.user = (await api('GET', '/api/auth/me')).user; } catch { return logout(); }
  }
  const main = h('main', {}, h('p', { class: 'muted' }, 'Loading…'));
  const nav = h('nav', {}, h('div', { class: 'brand' }, 'The Quran Journey', h('small', {}, 'Content management')),
    VIEWS.filter(([, , r]) => can(r)).map(([id, label]) =>
      h('button', { class: state.view === id ? 'active' : '', onclick: () => { state.view = id; render(); } }, label)),
    h('div', { class: 'who' }, state.user.email, h('br'), `Role: ${state.user.role}`, h('br'),
      h('a', { href: '#', onclick: (e) => { e.preventDefault(); api('POST', '/api/auth/logout').finally(logout); } }, 'Sign out')));
  root.replaceChildren(h('div', { class: 'layout' }, nav, main));
  try {
    const [s, sc] = await Promise.all([api('GET', '/api/admin/sources'), api('GET', '/api/admin/scholars')]);
    state.sources = s.sources; state.scholars = sc.scholars;
    main.replaceChildren(...[].concat(await VIEW_RENDER[state.view]()));
  } catch (e) { main.replaceChildren(h('div', { class: 'msg err' }, e.message)); }
}

// ---------- overview / review queue ----------
async function overviewView() {
  const [stats, q] = await Promise.all([api('GET', '/api/admin/stats'), api('GET', '/api/admin/review-queue')]);
  const section = (title, items, hint) => [h('h2', {}, `${title} (${items.length})`), h('p', { class: 'sub' }, hint), itemTable(items)];
  return [
    h('h1', {}, 'Review queue'),
    h('p', { class: 'sub' }, 'Only published items reach the app. Workflow: draft → source verified → reviewed → approved → published.'),
    h('div', { class: 'grid' }, Object.entries(stats.content_by_status).map(([k, n]) => h('div', { class: 'stat' }, h('b', {}, n), k.replace(/_/g, ' ')))),
    ...section('Awaiting review', q.awaiting_review, 'Source verified by an editor; a reviewer checks accuracy and attribution.'),
    ...section('Awaiting approval', q.awaiting_approval, 'Reviewed; a different reviewer than the author approves.'),
    ...section('Awaiting publication', q.awaiting_publication, 'Approved; an admin publishes.'),
    ...section('Drafts', q.drafts, 'Being written or edited. Any edit returns an item here.'),
  ];
}
function itemTable(items) {
  if (!items.length) return h('p', { class: 'muted' }, 'Nothing here.');
  return h('table', {}, h('tr', {}, h('th', {}, 'Ref'), h('th', {}, 'Type'), h('th', {}, 'Category'), h('th', {}, 'Title'), h('th', {}, 'Status'), h('th', {}, 'Updated')),
    items.map((i) => h('tr', { class: 'click', onclick: () => editItem(i.id) },
      h('td', {}, ref(i)), h('td', {}, i.type), h('td', {}, pill(i.category)), h('td', {}, i.title || i.body.slice(0, 60) + '…'),
      h('td', {}, pill(i.status)), h('td', {}, fmt(i.updated_at)))));
}

// ---------- content ----------
async function contentView() {
  const status = h('select', {}, h('option', { value: '' }, 'All statuses'), ['draft', 'source_verified', 'reviewed', 'approved', 'published', 'unpublished'].map((s) => h('option', { value: s }, s)));
  const type = h('select', {}, h('option', { value: '' }, 'All types'), ['context', 'tafsir', 'reflection', 'word_note', 'surah_intro'].map((s) => h('option', { value: s }, s)));
  const surah = h('input', { type: 'number', min: 1, max: 114, placeholder: 'Surah' });
  const q = h('input', { placeholder: 'Search text' });
  const list = h('div');
  const load = async () => {
    const p = new URLSearchParams();
    if (status.value) p.set('status', status.value);
    if (type.value) p.set('type', type.value);
    if (surah.value) p.set('surah', surah.value);
    if (q.value) p.set('q', q.value);
    try { list.replaceChildren(itemTable((await api('GET', `/api/admin/content?${p}`)).items)); } catch (e) { message(list, e.message); }
  };
  [status, type].forEach((el) => el.addEventListener('change', load));
  [surah, q].forEach((el) => el.addEventListener('change', load));
  await load();
  return [h('div', { class: 'row between' }, h('h1', {}, 'Study content'), h('button', { class: 'btn', onclick: () => editItem(null) }, 'New item')),
    h('p', { class: 'sub' }, 'Context, tafsir, reflections, word notes and surah introductions.'),
    h('div', { class: 'card fields' }, h('div', {}, h('label', {}, 'Status'), status), h('div', {}, h('label', {}, 'Type'), type), h('div', {}, h('label', {}, 'Surah'), surah), h('div', {}, h('label', {}, 'Search'), q)),
    list];
}

const TRANSITION_BUTTONS = {
  draft: [['source_verified', 'Mark source verified', 'editor']],
  source_verified: [['reviewed', 'Mark reviewed', 'reviewer'], ['draft', 'Return to draft', 'editor']],
  reviewed: [['approved', 'Approve', 'reviewer'], ['draft', 'Return to draft', 'editor']],
  approved: [['published', 'Publish', 'admin'], ['draft', 'Return to draft', 'editor']],
  published: [['unpublished', 'Unpublish', 'admin']],
  unpublished: [['published', 'Re-publish', 'admin'], ['draft', 'Return to draft', 'editor']],
};

async function editItem(id) {
  const main = document.querySelector('main');
  const item = id ? (await api('GET', `/api/admin/content/${id}`)).item : {
    type: 'reflection', category: 'editorial_summary', surah: 1, start_ayah: 1, end_ayah: 1, body: '', citation: {}, status: 'draft', language: 'en',
  };
  const f = {};
  const field = (key, label, el) => { f[key] = el; return h('div', {}, h('label', {}, label), el); };
  const sel = (vals, cur) => h('select', {}, vals.map(([v, l]) => h('option', { value: v, selected: v === (cur ?? '') }, l)));
  const msg = h('div');
  const versesBox = h('div');
  const showVerses = async () => {
    try {
      const r = await api('GET', `/api/admin/surahs/${f.surah.value}/verses`);
      const vs = r.verses.filter((v) => v.ayah >= Number(f.start_ayah.value) && v.ayah <= Number(f.end_ayah.value));
      versesBox.replaceChildren(h('div', { class: 'card' }, h('p', { class: 'notice' }, r.notice), vs.map((v) => h('div', {}, h('div', { class: 'ar', lang: 'ar' }, `${v.text_uthmani} (${v.ayah})`), h('p', { class: 'muted' }, v.translation)))));
    } catch (e) { versesBox.replaceChildren(h('p', { class: 'muted' }, e.message)); }
  };
  const form = h('div', { class: 'card' },
    h('div', { class: 'fields' },
      field('type', 'Type', sel([['context', 'Context'], ['tafsir', 'Tafsir'], ['reflection', 'Reflection'], ['word_note', 'Word note'], ['surah_intro', 'Surah introduction']], item.type)),
      field('category', 'Category', sel([['direct_quotation', 'Direct quotation'], ['paraphrase', 'Paraphrase'], ['editorial_summary', 'Editorial summary'], ['ai_assisted', 'AI-assisted']], item.category)),
      field('surah', 'Surah', h('input', { type: 'number', min: 1, max: 114, value: item.surah })),
      field('start_ayah', 'From ayah', h('input', { type: 'number', min: 1, value: item.start_ayah })),
      field('end_ayah', 'To ayah', h('input', { type: 'number', min: 1, value: item.end_ayah })),
      field('word_position', 'Word position (word notes)', h('input', { type: 'number', min: 1, value: item.word_position ?? '' })),
      field('language', 'Language', h('input', { value: item.language })),
      field('source_id', 'Source', sel([['', '— none —'], ...state.sources.map((s) => [s.id, s.title])], item.source_id)),
      field('scholar_id', 'Scholar', sel([['', '— none —'], ...state.scholars.map((s) => [s.id, s.name])], item.scholar_id)),
      field('volume', 'Volume', h('input', { value: item.citation.volume ?? '' })),
      field('page', 'Page', h('input', { value: item.citation.page ?? '' })),
      field('edition', 'Edition', h('input', { value: item.citation.edition ?? '' })),
      field('url', 'Source URL', h('input', { type: 'url', value: item.citation.url ?? '' }))),
    field('title', 'Title', h('input', { value: item.title ?? '' })),
    field('body', 'Body (plain text; blank line between paragraphs)', h('textarea', { value: item.body })),
    h('p', { class: 'notice' }, 'Direct quotations must be verbatim and cite a source. Never attribute AI-assisted or editorial text to a scholar. Saving any change returns the item to draft.'),
    msg,
    h('div', { class: 'row' },
      h('button', { class: 'btn', onclick: async () => {
        const body = {
          type: f.type.value, category: f.category.value, surah: Number(f.surah.value), start_ayah: Number(f.start_ayah.value),
          end_ayah: Number(f.end_ayah.value), word_position: f.word_position.value ? Number(f.word_position.value) : null,
          language: f.language.value, source_id: f.source_id.value || null, scholar_id: f.scholar_id.value || null,
          title: f.title.value || null, body: f.body.value,
          citation: { volume: f.volume.value || null, page: f.page.value || null, edition: f.edition.value || null, url: f.url.value || null },
        };
        try {
          const r = id ? await api('PUT', `/api/admin/content/${id}`, body) : await api('POST', '/api/admin/content', body);
          editItem(r.item.id);
        } catch (e) { message(msg, e.message); }
      } }, id ? 'Save (returns to draft)' : 'Create draft'),
      h('button', { class: 'btn secondary', onclick: showVerses }, 'Show verses'),
      h('button', { class: 'btn secondary', onclick: () => render() }, 'Back'),
      id && can('admin') ? h('button', { class: 'btn danger', onclick: async () => {
        if (!confirm('Delete this item permanently?')) return;
        await api('DELETE', `/api/admin/content/${id}`); render();
      } }, 'Delete') : null));

  const workflow = id ? h('div', { class: 'card' },
    h('div', { class: 'row' }, 'Status: ', pill(item.status), ` · version ${item.version}`, item.reviewer ? ` · reviewed by ${item.reviewer} on ${fmt(item.verified_at)}` : ''),
    h('div', { class: 'row mt' }, (TRANSITION_BUTTONS[item.status] || []).map(([to, label, role]) =>
      h('button', { class: 'btn secondary', disabled: !can(role), title: can(role) ? '' : `Requires ${role}`, onclick: async () => {
        try { await api('POST', `/api/admin/content/${id}/status`, { status: to }); editItem(id); } catch (e) { message(msg, e.message); }
      } }, label)))) : null;

  main.replaceChildren(h('h1', {}, id ? `Edit ${ref(item)}` : 'New content item'), h('p', { class: 'sub' }, id ? `Created ${fmt(item.created_at)} · updated ${fmt(item.updated_at)}` : 'New items start as drafts.'), workflow, form, versesBox);
}

// ---------- generic metadata tables ----------
function crudView(name, title, sub, cols, fields, { writeRole = 'editor' } = {}) {
  return async () => {
    const rows = (await api('GET', `/api/admin/${name}`))[name];
    const editor = h('div');
    const open = (row) => {
      const f = {};
      const msg = h('div');
      editor.replaceChildren(h('div', { class: 'card' },
        h('h2', {}, row ? 'Edit' : 'Add'),
        h('div', { class: 'fields' }, fields.map(([k, label, type]) => {
          const el = type === 'bool' ? h('select', {}, h('option', { value: 'true', selected: row?.[k] !== false }, 'Yes'), h('option', { value: 'false', selected: row?.[k] === false }, 'No'))
            : h('input', { type: type === 'int' ? 'number' : 'text', value: row?.[k] ?? '' });
          f[k] = [el, type];
          return h('div', {}, h('label', {}, label), el);
        })),
        msg,
        h('div', { class: 'row mt' },
          h('button', { class: 'btn', disabled: !can(writeRole), onclick: async () => {
            const body = {};
            for (const [k, [el, type]] of Object.entries(f)) {
              if (el.value === '') { body[k] = null; continue; }
              body[k] = type === 'int' ? Number(el.value) : type === 'bool' ? el.value === 'true' : el.value;
            }
            try { row ? await api('PUT', `/api/admin/${name}/${row.id}`, body) : await api('POST', `/api/admin/${name}`, body); render(); } catch (e) { message(msg, e.message); }
          } }, 'Save'),
          row && can('admin') ? h('button', { class: 'btn danger', onclick: async () => {
            if (!confirm('Delete?')) return;
            try { await api('DELETE', `/api/admin/${name}/${row.id}`); render(); } catch (e) { message(msg, e.message); }
          } }, 'Delete') : null)));
    };
    return [h('div', { class: 'row between' }, h('h1', {}, title), can(writeRole) ? h('button', { class: 'btn', onclick: () => open(null) }, 'Add') : null),
      h('p', { class: 'sub' }, sub), editor,
      h('table', {}, h('tr', {}, cols.map(([, l]) => h('th', {}, l))),
        rows.map((r) => h('tr', { class: 'click', onclick: () => open(r) }, cols.map(([k]) => h('td', {}, String(r[k] ?? '—'))))))];
  };
}

async function groupingsView() {
  const rows = (await api('GET', '/api/admin/groupings')).groupings;
  const msg = h('div');
  const s = h('input', { type: 'number', min: 1, max: 114, placeholder: 'Surah' });
  const a = h('input', { type: 'number', min: 1, placeholder: 'From' });
  const b = h('input', { type: 'number', min: 1, placeholder: 'To' });
  const r = h('input', { placeholder: 'Why this grouping keeps the meaning together' });
  return [h('h1', {}, 'Study groupings'),
    h('p', { class: 'sub' }, 'Overrides of the default rule (3 verses per study, never crossing a surah). Published overrides are sent to the app; they must not overlap.'),
    h('div', { class: 'card' }, h('div', { class: 'fields' }, h('div', {}, h('label', {}, 'Surah'), s), h('div', {}, h('label', {}, 'From ayah'), a), h('div', {}, h('label', {}, 'To ayah'), b)),
      h('label', {}, 'Rationale'), r, msg,
      h('div', { class: 'row mt' }, h('button', { class: 'btn', onclick: async () => {
        try { await api('POST', '/api/admin/groupings', { surah: Number(s.value), start_ayah: Number(a.value), end_ayah: Number(b.value), rationale: r.value }); render(); } catch (e) { message(msg, e.message); }
      } }, 'Add draft grouping'))),
    h('table', {}, h('tr', {}, h('th', {}, 'Range'), h('th', {}, 'Rationale'), h('th', {}, 'Status'), h('th', {}, '')),
      rows.map((g) => h('tr', {}, h('td', {}, ref(g)), h('td', {}, g.rationale), h('td', {}, pill(g.status)),
        h('td', {}, can('admin') ? h('div', { class: 'row' },
          g.status !== 'published' ? h('button', { class: 'btn secondary', onclick: async () => { try { await api('POST', `/api/admin/groupings/${g.id}/status`, { status: 'published' }); render(); } catch (e) { alert(e.message); } } }, 'Publish') : null,
          g.status === 'published' ? h('button', { class: 'btn secondary', onclick: async () => { await api('POST', `/api/admin/groupings/${g.id}/status`, { status: 'unpublished' }); render(); } }, 'Unpublish') : null,
          h('button', { class: 'btn danger', onclick: async () => { if (confirm('Delete?')) { await api('DELETE', `/api/admin/groupings/${g.id}`); render(); } } }, 'Delete')) : ''))))];
}

async function surahsView() {
  const r = await api('GET', '/api/admin/surahs');
  const box = h('div');
  return [h('h1', {}, 'Surahs & verses'),
    h('p', { class: 'notice' }, 'Quran text is verbatim Tanzil Uthmani text and is read-only here by design: the Tanzil licence forbids changes. To update it, replace the source file and rebuild with tools/build_content.py, which re-runs every integrity check.'),
    r.quran_db_loaded ? null : h('div', { class: 'msg err' }, 'Bundled quran.db not found on this server; only verse counts are shown.'),
    box,
    h('table', {}, h('tr', {}, h('th', {}, '#'), h('th', {}, 'Name'), h('th', {}, 'English'), h('th', {}, 'Type'), h('th', {}, 'Verses')),
      r.surahs.map((s) => h('tr', { class: 'click', onclick: async () => {
        try {
          const v = await api('GET', `/api/admin/surahs/${s.number}/verses`);
          box.replaceChildren(h('div', { class: 'card' }, h('h2', {}, `${s.number}. ${s.name_translit ?? ''}`), v.verses.map((x) => h('div', {}, h('div', { class: 'ar', lang: 'ar' }, `${x.text_uthmani} (${x.ayah})`), h('p', { class: 'muted' }, x.translation)))));
          window.scrollTo(0, 0);
        } catch (e) { message(box, e.message); }
      } }, h('td', {}, s.number), h('td', {}, s.name_translit ?? ''), h('td', {}, s.name_en ?? ''), h('td', {}, s.revelation_type ?? ''), h('td', {}, s.ayah_count))))];
}

async function usersView() {
  const rows = (await api('GET', '/api/admin/users')).users;
  return [h('h1', {}, 'Users'), h('p', { class: 'sub' }, 'Roles: user (app sync only), editor, reviewer, admin. Only admins assign roles.'),
    h('table', {}, h('tr', {}, h('th', {}, 'Email'), h('th', {}, 'Role'), h('th', {}, 'Created')),
      rows.map((u) => {
        const sel = h('select', { disabled: u.id === state.user.id }, ['user', 'editor', 'reviewer', 'admin'].map((r) => h('option', { value: r, selected: r === u.role }, r)));
        sel.addEventListener('change', async () => { try { await api('PUT', `/api/admin/users/${u.id}/role`, { role: sel.value }); } catch (e) { alert(e.message); render(); } });
        return h('tr', {}, h('td', {}, u.email), h('td', {}, sel), h('td', {}, fmt(u.created_at)));
      }))];
}

async function auditView() {
  const rows = (await api('GET', '/api/admin/audit?limit=300')).entries;
  return [h('h1', {}, 'Audit log'), h('p', { class: 'sub' }, 'Every administrative change, newest first.'),
    h('table', {}, h('tr', {}, h('th', {}, 'When'), h('th', {}, 'Who'), h('th', {}, 'Action'), h('th', {}, 'Entity'), h('th', {}, 'Detail')),
      rows.map((r) => h('tr', {}, h('td', {}, fmt(r.at)), h('td', {}, r.user_email), h('td', {}, r.action), h('td', {}, `${r.entity} ${r.entity_id ?? ''}`), h('td', {}, r.detail ? JSON.stringify(r.detail).slice(0, 160) : ''))))];
}

const VIEW_RENDER = {
  overview: overviewView,
  content: contentView,
  sources: crudView('sources', 'Sources', 'Works cited by study content. Record the licence for every source.',
    [['title', 'Title'], ['author', 'Author'], ['edition', 'Edition'], ['license', 'Licence']],
    [['title', 'Title'], ['author', 'Author'], ['edition', 'Edition'], ['publisher', 'Publisher'], ['year', 'Year'], ['url', 'URL'], ['license', 'Licence / permission'], ['notes', 'Notes']]),
  scholars: crudView('scholars', 'Scholars', 'Scholars to whom tafsir content is attributed. Factual data only.',
    [['name', 'Name'], ['death_year_ah', 'Died (AH)'], ['death_year_ce', 'Died (CE)']],
    [['name', 'Name'], ['death_year_ah', 'Death year AH', 'int'], ['death_year_ce', 'Death year CE', 'int'], ['bio_url', 'Biography URL']]),
  groupings: groupingsView,
  surahs: surahsView,
  translations: crudView('translations', 'Translations', 'Translation metadata and licences. Translation text itself is bundled in the app from verified sources.',
    [['code', 'Code'], ['name', 'Name'], ['translator', 'Translator'], ['license', 'Licence'], ['enabled', 'Enabled']],
    [['code', 'Code'], ['name', 'Name'], ['translator', 'Translator'], ['language', 'Language'], ['license', 'Licence'], ['source_url', 'Source URL'], ['enabled', 'Enabled', 'bool']], { writeRole: 'admin' }),
  audio: crudView('audio', 'Audio reciters', 'Recitation sources. URL = base_url + file_pattern ({surah3}{ayah3} → 001001).',
    [['name', 'Reciter'], ['style', 'Style'], ['base_url', 'Base URL'], ['enabled', 'Enabled']],
    [['name', 'Reciter'], ['style', 'Style'], ['base_url', 'Base URL (https)'], ['file_pattern', 'File pattern'], ['license', 'Licence'], ['source_url', 'Source URL'], ['enabled', 'Enabled', 'bool'], ['notes', 'Notes']], { writeRole: 'admin' }),
  users: usersView,
  audit: auditView,
};

render();
