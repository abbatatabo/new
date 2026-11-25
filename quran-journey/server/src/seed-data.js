// Factual reference data only. Licensing notes mirror tools/build_content.py.
const SOURCES = [
  { id: 'tanzil-uthmani', title: 'Tanzil Quran Text (Uthmani)', author: 'Tanzil Project', edition: '1.1', publisher: 'Tanzil Project', year: '2007-2026', url: 'https://tanzil.net/download/', license: 'CC BY 3.0 with Tanzil terms: verbatim copies only (changing the text is not allowed), attribute Tanzil, link to tanzil.net.' },
  { id: 'tanzil-metadata', title: 'Tanzil Quran Metadata', author: 'Tanzil Project', edition: '1.0', publisher: 'Tanzil Project', year: '2008', url: 'https://tanzil.net/docs/Quran_Metadata', license: 'CC BY 3.0' },
  { id: 'en.pickthall', title: 'The Meaning of the Glorious Koran', author: 'Mohammed Marmaduke William Pickthall (1875-1936)', edition: '1930 translation; Tanzil digital edition (2010-09-04)', publisher: 'Tanzil Project (digital text)', year: '1930', url: 'https://tanzil.net/trans/en.pickthall', license: 'Public domain (translator died 1936). Digital text from Tanzil.' },
  { id: 'en.yusufali', title: "The Holy Qur'an: Text, Translation and Commentary", author: 'Abdullah Yusuf Ali (1872-1953)', edition: '1934-1938 original; Tanzil digital edition (2013-05-10)', publisher: 'Tanzil Project (digital text)', year: '1934-1938', url: 'https://tanzil.net/trans/en.yusufali', license: 'Public domain in life+70 jurisdictions since 2024 (translator died 1953). Later revised editions are a different, copyrighted text.' },
  { id: 'en.transliteration', title: 'English Transliteration', author: 'Tanzil Project (contributors)', edition: 'Tanzil digital edition (2010-09-06)', publisher: 'Tanzil Project', year: '2010', url: 'https://tanzil.net/trans/en.transliteration', license: 'Distributed by Tanzil for use with attribution.' },
  { id: 'qac-morphology', title: 'Quranic Arabic Corpus - Morphology', author: 'Kais Dukes, University of Leeds', edition: '0.4', publisher: 'corpus.quran.com', year: '2011', url: 'https://corpus.quran.com/', license: 'GNU GPL with corpus terms: verbatim copies, attribute and link to corpus.quran.com.' },
  { id: 'tafsir-ibn-kathir-ar', title: "Tafsir al-Qur'an al-'Azim", author: 'Ismail ibn Kathir', edition: 'Arabic digital edition via Quran.com API (resource 14); volume/page not provided', publisher: 'Quran.com (digital text)', year: null, url: 'https://quran.com/', license: 'Classical work (author d. 774 AH / 1373 CE), public domain. Digital edition terms per Quran.com.' },
  { id: 'tafsir-tabari-ar', title: "Jami' al-Bayan 'an Ta'wil Ay al-Qur'an", author: 'Muhammad ibn Jarir al-Tabari', edition: 'Arabic digital edition via Quran.com API (resource 15); volume/page not provided', publisher: 'Quran.com (digital text)', year: null, url: 'https://quran.com/', license: 'Classical work (author d. 310 AH / 923 CE), public domain. Digital edition terms per Quran.com.' },
  { id: 'tafsir-qurtubi-ar', title: "Al-Jami' li-Ahkam al-Qur'an", author: 'Muhammad ibn Ahmad al-Qurtubi', edition: 'Arabic digital edition via Quran.com API (resource 90); volume/page not provided', publisher: 'Quran.com (digital text)', year: null, url: 'https://quran.com/', license: 'Classical work (author d. 671 AH / 1273 CE), public domain. Digital edition terms per Quran.com.' },
  { id: 'tafsir-baghawi-ar', title: "Ma'alim al-Tanzil", author: 'al-Husayn ibn Mas‘ud al-Baghawi', edition: 'Arabic digital edition via Quran.com API (resource 94); volume/page not provided', publisher: 'Quran.com (digital text)', year: null, url: 'https://quran.com/', license: 'Classical work (author d. 516 AH / 1122 CE), public domain. Digital edition terms per Quran.com.' },
];

const SCHOLARS = [
  { id: 'ibn-kathir', name: 'Ibn Kathir', death_year_ah: 774, death_year_ce: 1373, bio_url: 'https://en.wikipedia.org/wiki/Ibn_Kathir' },
  { id: 'al-tabari', name: 'al-Tabari', death_year_ah: 310, death_year_ce: 923, bio_url: 'https://en.wikipedia.org/wiki/Al-Tabari' },
  { id: 'al-qurtubi', name: 'al-Qurtubi', death_year_ah: 671, death_year_ce: 1273, bio_url: 'https://en.wikipedia.org/wiki/Al-Qurtubi' },
  { id: 'al-baghawi', name: 'al-Baghawi', death_year_ah: 516, death_year_ce: 1122, bio_url: 'https://en.wikipedia.org/wiki/Al-Baghawi' },
];

const RECITERS = [
  { id: 'alafasy-128', name: 'Mishary Rashid Alafasy', style: 'Murattal', base_url: 'https://everyayah.com/data/Alafasy_128kbps/', file_pattern: '{surah3}{ayah3}.mp3', license: 'Streamed from EveryAyah.com. No formal licence is published; verify permission before any commercial distribution.', source_url: 'https://everyayah.com/', notes: 'Per-verse MP3 files.' },
  { id: 'husary-128', name: 'Mahmoud Khalil Al-Husary', style: 'Murattal', base_url: 'https://everyayah.com/data/Husary_128kbps/', file_pattern: '{surah3}{ayah3}.mp3', license: 'Streamed from EveryAyah.com. No formal licence is published; verify permission before any commercial distribution.', source_url: 'https://everyayah.com/', notes: 'Per-verse MP3 files.' },
];

const TRANSLATIONS = [
  { id: 'en.pickthall', code: 'en.pickthall', name: 'Pickthall', translator: 'Mohammed Marmaduke William Pickthall', language: 'en', license: 'Public domain', source_url: 'https://tanzil.net/trans/en.pickthall' },
  { id: 'en.yusufali', code: 'en.yusufali', name: 'Yusuf Ali', translator: 'Abdullah Yusuf Ali', language: 'en', license: 'Public domain (1934-38 text)', source_url: 'https://tanzil.net/trans/en.yusufali' },
  { id: 'en.transliteration', code: 'en.transliteration', name: 'Transliteration', translator: 'Tanzil Project', language: 'en-Latn', license: 'Tanzil, with attribution', source_url: 'https://tanzil.net/trans/en.transliteration' },
];

const EXAMPLE_ITEM = {
  id: 'example-draft-fatiha-reflection',
  type: 'reflection', category: 'ai_assisted', surah: 1, start_ayah: 1, end_ayah: 4,
  title: 'EXAMPLE DRAFT - not reviewed',
  body: 'This is an example AI-assisted draft created by the seed script to demonstrate the review workflow. It must be checked by a qualified reviewer, rewritten as needed, and approved before it can be published.\n\nReflection prompt: The passage opens by praising Allah before any request is made. What does beginning with praise change about how you approach the rest of your day?',
};

export function seed(db) {
  const now = new Date().toISOString();
  const ins = (table, row) => {
    const cols = Object.keys(row);
    db.prepare(`INSERT OR IGNORE INTO ${table} (${cols.join(',')}, created_at, updated_at) VALUES (${cols.map(() => '?').join(',')}, ?, ?)`)
      .run(...cols.map((c) => row[c] ?? null), now, now);
  };
  SOURCES.forEach((s) => ins('sources', { notes: null, ...s }));
  SCHOLARS.forEach((s) => ins('scholars', s));
  RECITERS.forEach((r) => ins('audio_reciters', r));
  TRANSLATIONS.forEach((t) => ins('translations_meta', t));
  ins('content_items', { ...EXAMPLE_ITEM, status: 'draft', citation: '{}', language: 'en', version: 1 });
  return { sources: SOURCES.length, scholars: SCHOLARS.length, reciters: RECITERS.length, translations: TRANSLATIONS.length, items: 1 };
}
