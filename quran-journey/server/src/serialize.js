export const serializeItem = (r) => ({
  id: r.id,
  type: r.type,
  category: r.category,
  surah: r.surah,
  start_ayah: r.start_ayah,
  end_ayah: r.end_ayah,
  word_position: r.word_position ?? null,
  title: r.title ?? null,
  body: r.body,
  language: r.language,
  source_id: r.source_id ?? null,
  scholar_id: r.scholar_id ?? null,
  citation: JSON.parse(r.citation || '{}'),
  status: r.status,
  reviewer: r.reviewer ?? null,
  verified_at: r.verified_at ?? null,
  version: r.version,
  updated_at: r.updated_at,
});

export const serializeItemAdmin = (r) => ({
  ...serializeItem(r),
  created_by: r.created_by ?? null,
  updated_by: r.updated_by ?? null,
  created_at: r.created_at,
});

export const serializeGrouping = (r) => ({
  id: r.id,
  surah: r.surah,
  start_ayah: r.start_ayah,
  end_ayah: r.end_ayah,
  rationale: r.rationale,
  status: r.status,
  updated_at: r.updated_at,
});

export const serializeSource = (r) => ({
  id: r.id,
  title: r.title,
  author: r.author ?? null,
  edition: r.edition ?? null,
  publisher: r.publisher ?? null,
  year: r.year ?? null,
  url: r.url ?? null,
  license: r.license,
  notes: r.notes ?? null,
});

export const serializeScholar = (r) => ({
  id: r.id,
  name: r.name,
  death_year_ah: r.death_year_ah ?? null,
  death_year_ce: r.death_year_ce ?? null,
  bio_url: r.bio_url ?? null,
});
