<?php
declare(strict_types=1);

namespace QJ;

use PDO;

/** Read-only access to the verified bundled database (shared with the mobile app). */
final class Quran
{
    public PDO $db;
    /** @var list<array> */
    public array $surahs;
    /** @var array<int,int> */
    public array $wordCounts = [];
    public array $meta = [];
    public array $translations = [];

    public function __construct(string $path)
    {
        if (!is_file($path)) {
            throw new \RuntimeException("Quran database not found at $path");
        }
        $this->db = new PDO('sqlite:' . $path, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
        $this->db->exec('PRAGMA query_only = 1');
        $this->surahs = array_map(fn($r) => array_map(fn($v) => is_numeric($v) ? (int)$v : $v, $r),
            $this->db->query('SELECT * FROM surahs ORDER BY number')->fetchAll(PDO::FETCH_ASSOC));
        foreach ($this->db->query('SELECT verse_id, COUNT(*) c FROM words GROUP BY verse_id') as $r) {
            $this->wordCounts[(int)$r['verse_id']] = (int)$r['c'];
        }
        foreach ($this->db->query('SELECT key, value FROM meta') as $r) {
            $this->meta[$r['key']] = $r['value'];
        }
        $this->translations = $this->db->query('SELECT * FROM translations ORDER BY id')->fetchAll(PDO::FETCH_ASSOC);
    }

    public function surah(int $n): array
    {
        return $this->surahs[max(1, min(114, $n)) - 1];
    }

    public function englishTranslations(): array
    {
        return array_values(array_filter($this->translations, fn($t) => $t['kind'] === 'translation'));
    }

    public function transliterationId(): int
    {
        foreach ($this->translations as $t) {
            if ($t['kind'] === 'transliteration') {
                return (int)$t['id'];
            }
        }
        return 3;
    }

    public function translation(int $id): array
    {
        foreach ($this->englishTranslations() as $t) {
            if ((int)$t['id'] === $id) {
                return $t;
            }
        }
        return $this->englishTranslations()[0];
    }

    public function verses(int $start, int $end): array
    {
        $q = $this->db->prepare('SELECT * FROM verses WHERE id BETWEEN ? AND ? ORDER BY id');
        $q->execute([$start, $end]);
        return $q->fetchAll(PDO::FETCH_ASSOC);
    }

    public function text(int $translationId, int $start, int $end): array
    {
        $q = $this->db->prepare('SELECT verse_id, text FROM translation_text WHERE translation_id = ? AND verse_id BETWEEN ? AND ?');
        $q->execute([$translationId, $start, $end]);
        $out = [];
        foreach ($q as $r) {
            $out[(int)$r['verse_id']] = $r['text'];
        }
        return $out;
    }

    public function words(int $verseId): array
    {
        $q = $this->db->prepare('SELECT * FROM words WHERE verse_id = ? ORDER BY position');
        $q->execute([$verseId]);
        $out = [];
        foreach ($q as $r) {
            $r['segments'] = array_map(fn($l) => explode("\t", $l), explode("\n", $r['segments']));
            $out[] = $r;
        }
        return $out;
    }

    public function rootCount(string $rootBw): int
    {
        $q = $this->db->prepare('SELECT COUNT(*) FROM words WHERE root_bw = ?');
        $q->execute([$rootBw]);
        return (int)$q->fetchColumn();
    }

    public function sources(): array
    {
        return $this->db->query('SELECT * FROM sources')->fetchAll(PDO::FETCH_ASSOC);
    }

    public static function normaliseArabic(string $t): string
    {
        $t = preg_replace('/[\x{0610}-\x{061A}\x{064B}-\x{065F}\x{0670}\x{06D6}-\x{06ED}\x{0640}]/u', '', $t) ?? '';
        $t = strtr($t, ['ٱ' => 'ا', 'أ' => 'ا', 'إ' => 'ا', 'آ' => 'ا', 'ى' => 'ي']);
        return trim(preg_replace('/\s+/u', ' ', $t) ?? '');
    }

    /** @return list<int> verse ids */
    public function search(string $query, int $translationId, int $limit = 60): array
    {
        $q = trim($query);
        if ($q === '') {
            return [];
        }
        if (preg_match('/^(\d{1,3})\s*[:.\s]\s*(\d{1,3})$/', $q, $m)) {
            $st = $this->db->prepare('SELECT id FROM verses WHERE surah = ? AND ayah = ?');
            $st->execute([(int)$m[1], (int)$m[2]]);
            $id = $st->fetchColumn();
            return $id === false ? [] : [(int)$id];
        }
        $like = '%' . str_replace(['\\', '%', '_'], ['\\\\', '\\%', '\\_'], $q) . '%';
        if (preg_match('/\p{Arabic}/u', $q)) {
            $like = '%' . str_replace(['\\', '%', '_'], ['\\\\', '\\%', '\\_'], self::normaliseArabic($q)) . '%';
            $st = $this->db->prepare("SELECT id FROM verses WHERE search_ar LIKE ? ESCAPE '\\' ORDER BY id LIMIT $limit");
            $st->execute([$like]);
        } else {
            $st = $this->db->prepare("SELECT verse_id FROM translation_text WHERE translation_id = ? AND text LIKE ? ESCAPE '\\' ORDER BY verse_id LIMIT $limit");
            $st->execute([$translationId, $like]);
        }
        return array_map('intval', $st->fetchAll(PDO::FETCH_COLUMN));
    }
}

/** Private per-browser profile store (anonymous, no account). */
final class UserStore
{
    public PDO $db;

    public function __construct(string $path)
    {
        $dir = dirname($path);
        if (!is_dir($dir)) {
            mkdir($dir, 0700, true);
        }
        $this->db = new PDO('sqlite:' . $path, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
        $this->db->exec('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 3000');
        $this->db->exec(<<<SQL
CREATE TABLE IF NOT EXISTS profiles (
  id TEXT PRIMARY KEY,            -- sha256 of the browser's secret token
  settings TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  seen_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS completions (
  id INTEGER PRIMARY KEY, profile TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  start_id INTEGER NOT NULL, end_id INTEGER NOT NULL, completed_at INTEGER NOT NULL, journey INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS notes (
  id INTEGER PRIMARY KEY, profile TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  study_start INTEGER NOT NULL, study_end INTEGER NOT NULL, text TEXT NOT NULL,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS bookmarks (
  id INTEGER PRIMARY KEY, profile TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  type TEXT NOT NULL, verse_start INTEGER NOT NULL, verse_end INTEGER NOT NULL, label TEXT, created_at INTEGER NOT NULL,
  UNIQUE(profile, type, verse_start, verse_end)
);
CREATE TABLE IF NOT EXISTS cache (key TEXT PRIMARY KEY, value TEXT NOT NULL, fetched_at INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS idx_c_profile ON completions(profile);
CREATE INDEX IF NOT EXISTS idx_n_profile ON notes(profile, study_start);
SQL);
    }

    public function ensureProfile(string $id, array $defaults): array
    {
        $q = $this->db->prepare('SELECT settings FROM profiles WHERE id = ?');
        $q->execute([$id]);
        $row = $q->fetchColumn();
        $now = time();
        if ($row === false) {
            $this->db->prepare('INSERT INTO profiles (id, settings, created_at, seen_at) VALUES (?,?,?,?)')
                ->execute([$id, json_encode($defaults), $now, $now]);
            return $defaults;
        }
        $this->db->prepare('UPDATE profiles SET seen_at = ? WHERE id = ? AND seen_at < ?')->execute([$now, $id, $now - 3600]);
        return array_replace_recursive($defaults, json_decode($row, true) ?: []);
    }

    public function profileExists(string $id): bool
    {
        $q = $this->db->prepare('SELECT 1 FROM profiles WHERE id = ?');
        $q->execute([$id]);
        return $q->fetchColumn() !== false;
    }

    public function saveSettings(string $id, array $settings): void
    {
        $this->db->prepare('UPDATE profiles SET settings = ? WHERE id = ?')->execute([json_encode($settings), $id]);
    }

    public function completions(string $p, int $journey): array
    {
        $q = $this->db->prepare('SELECT start_id, end_id, completed_at FROM completions WHERE profile = ? AND journey = ? ORDER BY completed_at');
        $q->execute([$p, $journey]);
        return array_map(fn($r) => array_map('intval', $r), $q->fetchAll(PDO::FETCH_ASSOC));
    }

    public function addCompletion(string $p, int $start, int $end, int $journey): void
    {
        $this->db->prepare('INSERT INTO completions (profile, start_id, end_id, completed_at, journey) VALUES (?,?,?,?,?)')
            ->execute([$p, $start, $end, (int)(microtime(true) * 1000), $journey]);
    }

    public function notes(string $p, ?int $start = null, ?int $end = null): array
    {
        if ($start === null) {
            $q = $this->db->prepare('SELECT * FROM notes WHERE profile = ? ORDER BY updated_at DESC');
            $q->execute([$p]);
        } else {
            $q = $this->db->prepare('SELECT * FROM notes WHERE profile = ? AND study_start <= ? AND study_end >= ? ORDER BY created_at');
            $q->execute([$p, $end, $start]);
        }
        return $q->fetchAll(PDO::FETCH_ASSOC);
    }

    public function saveNote(string $p, ?int $id, int $start, int $end, string $text): void
    {
        $now = time();
        if ($id) {
            $this->db->prepare('UPDATE notes SET text = ?, updated_at = ? WHERE id = ? AND profile = ?')->execute([$text, $now, $id, $p]);
        } else {
            $this->db->prepare('INSERT INTO notes (profile, study_start, study_end, text, created_at, updated_at) VALUES (?,?,?,?,?,?)')
                ->execute([$p, $start, $end, $text, $now, $now]);
        }
    }

    public function deleteNote(string $p, int $id): void
    {
        $this->db->prepare('DELETE FROM notes WHERE id = ? AND profile = ?')->execute([$id, $p]);
    }

    public function bookmarks(string $p): array
    {
        $q = $this->db->prepare('SELECT * FROM bookmarks WHERE profile = ? ORDER BY created_at DESC, id DESC');
        $q->execute([$p]);
        return $q->fetchAll(PDO::FETCH_ASSOC);
    }

    public function hasBookmark(string $p, string $type, int $a, int $b): bool
    {
        $q = $this->db->prepare('SELECT 1 FROM bookmarks WHERE profile = ? AND type = ? AND verse_start = ? AND verse_end = ?');
        $q->execute([$p, $type, $a, $b]);
        return $q->fetchColumn() !== false;
    }

    public function toggleBookmark(string $p, string $type, int $a, int $b, string $label): bool
    {
        if ($this->hasBookmark($p, $type, $a, $b)) {
            $this->db->prepare('DELETE FROM bookmarks WHERE profile = ? AND type = ? AND verse_start = ? AND verse_end = ?')->execute([$p, $type, $a, $b]);
            return false;
        }
        $this->db->prepare('INSERT INTO bookmarks (profile, type, verse_start, verse_end, label, created_at) VALUES (?,?,?,?,?,?)')
            ->execute([$p, $type, $a, $b, $label, time()]);
        return true;
    }

    public function export(string $p, array $settings): array
    {
        $all = function (string $t) use ($p) {
            $q = $this->db->prepare("SELECT * FROM $t WHERE profile = ?");
            $q->execute([$p]);
            return array_map(function ($r) { unset($r['profile']); return $r; }, $q->fetchAll(PDO::FETCH_ASSOC));
        };
        return ['exported_at' => gmdate('c'), 'settings' => $settings, 'completions' => $all('completions'), 'notes' => $all('notes'), 'bookmarks' => $all('bookmarks')];
    }

    public function deleteProfile(string $p): void
    {
        $this->db->prepare('DELETE FROM profiles WHERE id = ?')->execute([$p]);
    }

    public function cacheGet(string $k, int $maxAge = 0): ?string
    {
        $q = $this->db->prepare('SELECT value, fetched_at FROM cache WHERE key = ?');
        $q->execute([$k]);
        $r = $q->fetch(PDO::FETCH_ASSOC);
        if (!$r || ($maxAge > 0 && $r['fetched_at'] < time() - $maxAge)) {
            return null;
        }
        return $r['value'];
    }

    public function cachePut(string $k, string $v): void
    {
        $this->db->prepare('INSERT OR REPLACE INTO cache (key, value, fetched_at) VALUES (?,?,?)')->execute([$k, $v, time()]);
    }
}
