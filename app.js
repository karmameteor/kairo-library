const state = {
  items: [],
  filtered: [],
  selectedType: 'All',
  selectedCategory: 'All',
  query: '',
  sort: 'az',
  onlyComplete: false,
  onlyMissing: false,
  activeId: null,
};

const els = {
  metaLine: document.querySelector('#metaLine'),
  searchInput: document.querySelector('#searchInput'),
  clearButton: document.querySelector('#clearButton'),
  totalItems: document.querySelector('#totalItems'),
  visibleItems: document.querySelector('#visibleItems'),
  clientItems: document.querySelector('#clientItems'),
  serverItems: document.querySelector('#serverItems'),
  typeFilters: document.querySelector('#typeFilters'),
  categoryFilters: document.querySelector('#categoryFilters'),
  onlyComplete: document.querySelector('#onlyComplete'),
  onlyMissing: document.querySelector('#onlyMissing'),
  sortSelect: document.querySelector('#sortSelect'),
  resultLine: document.querySelector('#resultLine'),
  itemList: document.querySelector('#itemList'),
  detailPanel: document.querySelector('#detailPanel'),
};

function formatNumber(value) {
  return new Intl.NumberFormat().format(value);
}

function sortItems(items) {
  const sorted = [...items];
  const byName = (a, b) => a.name.localeCompare(b.name) || a.id - b.id;

  if (state.sort === 'az') sorted.sort(byName);
  if (state.sort === 'za') sorted.sort((a, b) => b.name.localeCompare(a.name) || b.id - a.id);
  if (state.sort === 'idAsc') sorted.sort((a, b) => a.id - b.id);
  if (state.sort === 'idDesc') sorted.sort((a, b) => b.id - a.id);

  return sorted;
}

function countBy(items, key) {
  const map = new Map();
  for (const item of items) {
    map.set(item[key], (map.get(item[key]) || 0) + 1);
  }
  return [...map.entries()].sort((a, b) => a[0].localeCompare(b[0]));
}

function renderChips(target, entries, selected, onSelect) {
  target.innerHTML = '';
  const allCount = state.items.length;
  const allButton = document.createElement('button');
  allButton.className = `chip ${selected === 'All' ? 'active' : ''}`;
  allButton.type = 'button';
  allButton.innerHTML = `<span>All</span><small>${formatNumber(allCount)}</small>`;
  allButton.addEventListener('click', () => onSelect('All'));
  target.appendChild(allButton);

  for (const [name, count] of entries) {
    const button = document.createElement('button');
    button.className = `chip ${selected === name ? 'active' : ''}`;
    button.type = 'button';
    button.innerHTML = `<span>${name}</span><small>${formatNumber(count)}</small>`;
    button.addEventListener('click', () => onSelect(name));
    target.appendChild(button);
  }
}

function renderFilters() {
  renderChips(els.typeFilters, countBy(state.items, 'type'), state.selectedType, (value) => {
    state.selectedType = value;
    applyFilters();
  });

  renderChips(els.categoryFilters, countBy(state.items, 'category'), state.selectedCategory, (value) => {
    state.selectedCategory = value;
    applyFilters();
  });
}

function itemMatches(item) {
  if (state.selectedType !== 'All' && item.type !== state.selectedType) return false;
  if (state.selectedCategory !== 'All' && item.category !== state.selectedCategory) return false;
  if (state.onlyComplete && (!item.clientAsset || !item.serverAsset)) return false;
  if (state.onlyMissing && item.clientAsset && item.serverAsset) return false;
  if (state.query && !item.search.includes(state.query)) return false;
  return true;
}

function applyFilters() {
  state.filtered = sortItems(state.items.filter(itemMatches));
  els.visibleItems.textContent = formatNumber(state.filtered.length);
  els.resultLine.textContent = `${formatNumber(state.filtered.length)} result${state.filtered.length === 1 ? '' : 's'}`;
  renderList();
}

function renderList() {
  const limit = 900;
  const items = state.filtered.slice(0, limit);
  els.itemList.innerHTML = '';

  if (!items.length) {
    const empty = document.createElement('div');
    empty.className = 'emptyState';
    empty.textContent = 'No items match the current search.';
    els.itemList.appendChild(empty);
    return;
  }

  const fragment = document.createDocumentFragment();
  for (const item of items) {
    const row = document.createElement('div');
    row.className = `itemRow ${state.activeId === item.id ? 'active' : ''}`;
    row.tabIndex = 0;
    row.dataset.id = item.id;
    row.innerHTML = `
      <div class="itemId">${item.id}</div>
      <div class="itemName">
        <strong>${escapeHtml(item.name)}</strong>
        <span>${escapeHtml(item.type)} / ${escapeHtml(item.category)}</span>
      </div>
      <div class="badges">
        <span class="badge ${item.clientAsset ? 'ok' : 'missing'}">Client</span>
        <span class="badge ${item.serverAsset ? 'ok' : 'missing'}">Server</span>
      </div>
    `;

    row.addEventListener('mouseenter', () => selectItem(item.id));
    row.addEventListener('focus', () => selectItem(item.id));
    row.addEventListener('click', () => selectItem(item.id));
    fragment.appendChild(row);
  }

  els.itemList.appendChild(fragment);

  if (state.filtered.length > limit) {
    const note = document.createElement('div');
    note.className = 'emptyState';
    note.textContent = `Showing first ${formatNumber(limit)} results. Keep typing to narrow the catalog.`;
    els.itemList.appendChild(note);
  }
}

function selectItem(id) {
  const item = state.items.find(entry => entry.id === Number(id));
  if (!item) return;
  state.activeId = item.id;

  for (const row of els.itemList.querySelectorAll('.itemRow.active')) {
    row.classList.remove('active');
  }
  const activeRow = els.itemList.querySelector(`.itemRow[data-id="${item.id}"]`);
  if (activeRow) activeRow.classList.add('active');

  renderDetails(item);
}

function renderDetails(item) {
  const desc = item.desc || 'No description available in String.wz.';
  els.detailPanel.className = 'detailPanel';
  els.detailPanel.innerHTML = `
    <p class="eyebrow">${escapeHtml(item.type)} / ${escapeHtml(item.category)}</p>
    <h2>${escapeHtml(item.name)}</h2>
    <div class="detailId">ID ${item.id}</div>
    <div class="detailMeta">
      <div class="metaBox">
        <label>Client Data</label>
        <span class="${item.clientAsset ? 'assetOk' : 'assetMissing'}">${item.clientAsset ? 'Found' : 'Missing'}</span>
      </div>
      <div class="metaBox">
        <label>Server XML</label>
        <span class="${item.serverAsset ? 'assetOk' : 'assetMissing'}">${item.serverAsset ? 'Found' : 'Missing'}</span>
      </div>
    </div>
    <div class="descBox">${escapeHtml(desc)}</div>
  `;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function wireEvents() {
  let searchTimer = null;
  els.searchInput.addEventListener('input', () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => {
      state.query = els.searchInput.value.trim().toLowerCase();
      applyFilters();
    }, 80);
  });

  els.clearButton.addEventListener('click', () => {
    els.searchInput.value = '';
    state.query = '';
    applyFilters();
    els.searchInput.focus();
  });

  els.onlyComplete.addEventListener('change', () => {
    state.onlyComplete = els.onlyComplete.checked;
    if (state.onlyComplete) {
      state.onlyMissing = false;
      els.onlyMissing.checked = false;
    }
    applyFilters();
  });

  els.onlyMissing.addEventListener('change', () => {
    state.onlyMissing = els.onlyMissing.checked;
    if (state.onlyMissing) {
      state.onlyComplete = false;
      els.onlyComplete.checked = false;
    }
    applyFilters();
  });

  els.sortSelect.addEventListener('change', () => {
    state.sort = els.sortSelect.value;
    applyFilters();
  });
}

async function init() {
  wireEvents();
  const response = await fetch('data/items.json', { cache: 'no-store' });
  if (!response.ok) throw new Error('Unable to load data/items.json');

  const payload = await response.json();
  state.items = payload.items || [];
  state.filtered = [...state.items];

  els.metaLine.textContent = `Generated ${payload.generatedAt} from KairoMS data`;
  els.totalItems.textContent = formatNumber(state.items.length);
  els.clientItems.textContent = formatNumber(state.items.filter(item => item.clientAsset).length);
  els.serverItems.textContent = formatNumber(state.items.filter(item => item.serverAsset).length);

  renderFilters();
  applyFilters();
}

init().catch((error) => {
  els.metaLine.textContent = 'Database failed to load';
  els.itemList.innerHTML = `<div class="emptyState">${escapeHtml(error.message)}</div>`;
});
